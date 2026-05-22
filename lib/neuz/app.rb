require "roda"
require "json"
require "date"
require "securerandom"

module Neuz
  class App < Roda
    plugin :render,
      views: Config.views_dir,
      engine: "erb",
      escape: true,
      template_opts: { default_encoding: "UTF-8" },
      layout_opts: { template: "layout" }
    plugin :public, root: Config.public_dir
    plugin :json, content_type: "application/json", classes: [Hash, Array]
    plugin :json_parser
    plugin :head
    plugin :error_handler
    plugin :common_logger if Config.production?
    plugin :default_headers,
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "Referrer-Policy" => "no-referrer"

    error do |e|
      if e.is_a?(Sequel::DatabaseError) && e.message.to_s.match?(/locked|busy|disk/i)
        response.status = 503
        response["Retry-After"] = "5"
        { error: "database_busy", retry_after_seconds: 5 }
      else
        warn "[neuz.error] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
        response.status = 500
        if response["Content-Type"]&.include?("json")
          { error: "internal_error" }
        else
          response["Content-Type"] = "text/plain; charset=utf-8"
          "Internal Server Error"
        end
      end
    end

    route do |r|
      # Per-request CSP nonce.
      r.env["neuz.csp_nonce"] = SecureRandom.urlsafe_base64(16)
      response.headers["Content-Security-Policy"] = csp_header(r.env["neuz.csp_nonce"])
      response.headers["Content-Type"] = "text/html; charset=utf-8"

      r.public

      r.on "api" do
        r.is "items" do
          r.post { handle_ingest(r) }
        end
      end

      r.is "healthz" do
        handle_healthz
      end

      r.is "day", String do |date_str|
        render_day(r, date_str)
      end

      r.is "month", String do |ym|
        render_month(r, ym)
      end

      r.root do
        render_index(r)
      end
    end

    # ---------- handlers ----------

    def handle_ingest(r)
      response["Content-Type"] = "application/json"

      api_key = Auth.verify(r.env)
      unless api_key
        response.status = 401
        return { error: "unauthorized" }
      end

      result = RateLimiter.consume(api_key[:id])
      if result.is_a?(Hash)
        response.status = 429
        response["Retry-After"] = result[:retry_after].to_s
        return { error: "rate_limited", retry_after_seconds: result[:retry_after] }
      end

      body = r.params
      unless body.is_a?(Hash) && body["items"].is_a?(Array)
        response.status = 400
        return { error: "invalid_batch", message: "body must be an object with an items array" }
      end

      if body["items"].length > Config.batch_limit
        response.status = 413
        return { error: "batch_too_large", limit: Config.batch_limit }
      end

      summary = Ingest.batch(body["items"], api_key[:id])
      response.status = 200
      summary
    end

    def handle_healthz
      response["Content-Type"] = "application/json"
      items_total = DB.connection[:items].count
      bounds = today_bounds(tz_offset_minutes(request.cookies["tz"]))
      items_today = DB.connection[:items].where(Sequel.lit("created_at >= ? AND created_at < ?", bounds[0], bounds[1])).count
      {
        status: "ok",
        db: DB.healthy? ? "ok" : "error",
        items_total: items_total,
        items_today: items_today,
        version: Neuz.version,
      }
    end

    # ---------- views ----------

    def render_index(r)
      offset_min = tz_offset_minutes(request.cookies["tz"])
      start_utc, end_utc = today_bounds(offset_min)
      items = items_in_range(start_utc, end_utc, r.params["category"])
      chips = chip_set
      view(:index, locals: {
        items: items,
        chips: chips,
        selected: Array(r.params["category"]).flatten.compact,
        today_label: format_user_date(Time.now.utc, offset_min),
        tz_offset: offset_min,
      })
    end

    def render_day(r, date_str)
      unless date_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        response.status = 404
        return "Bad date"
      end
      offset_min = tz_offset_minutes(request.cookies["tz"])
      year, month, day = date_str.split("-").map(&:to_i)
      begin
        local_midnight = Time.utc(year, month, day)
      rescue ArgumentError
        response.status = 404
        return "Bad date"
      end
      start_utc = local_midnight - offset_min * 60
      end_utc = start_utc + 86_400
      items = items_in_range(start_utc, end_utc, r.params["category"])
      view(:day, locals: {
        date_str: date_str,
        items: items,
        chips: chip_set,
        selected: Array(r.params["category"]).flatten.compact,
      })
    end

    def render_month(r, ym)
      unless ym.match?(/\A\d{4}-\d{2}\z/)
        response.status = 404
        return "Bad month"
      end
      year, month = ym.split("-").map(&:to_i)
      begin
        first = Date.new(year, month, 1)
      rescue ArgumentError
        response.status = 404
        return "Bad month"
      end
      offset_min = tz_offset_minutes(request.cookies["tz"])
      last = (first >> 1) - 1
      start_utc = Time.utc(first.year, first.month, first.day) - offset_min * 60
      end_utc = Time.utc(last.year, last.month, last.day) + 86_400 - offset_min * 60

      # Calendar buckets by arrival day (created_at), see comment in
      # items_in_range above.
      rows = DB.connection[:items]
        .where(Sequel.lit("created_at >= ? AND created_at < ?", start_utc, end_utc))
        .select { [Sequel.lit("date(datetime(created_at, ? || ' minutes'))", offset_min.to_s).as(:local_date), Sequel.function(:count).*.as(:count)] }
        .group(Sequel.lit("date(datetime(created_at, ? || ' minutes'))", offset_min.to_s))
        .all
      counts = rows.each_with_object({}) { |row, acc| acc[row[:local_date]] = row[:count] }

      prev_month = first << 1
      next_month = first >> 1

      view(:month, locals: {
        first_day: first,
        last_day: last,
        counts: counts,
        prev_ym: prev_month.strftime("%Y-%m"),
        next_ym: next_month.strftime("%Y-%m"),
        month_label: first.strftime("%B %Y"),
      })
    end

    # ---------- helpers ----------

    def csp_header(nonce)
      [
        "default-src 'self'",
        "img-src 'self' https: data:",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self'",
        "font-src 'self'",
        "connect-src 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "object-src 'none'",
      ].join("; ")
    end

    def public_url(r)
      Config.public_url(r.base_url) || r.base_url
    end

    def tz_offset_minutes(cookie)
      Integer(cookie.to_s)
    rescue ArgumentError, TypeError
      0
    end

    def today_bounds(offset_min)
      now_local = Time.now.utc + offset_min * 60
      local_date = now_local.to_date
      start_local = Time.utc(local_date.year, local_date.month, local_date.day)
      start_utc = start_local - offset_min * 60
      [start_utc, start_utc + 86_400]
    end

    def format_user_date(time_utc, offset_min)
      (time_utc + offset_min * 60).strftime("%A, %B %-d, %Y")
    end

    # NOTE on bucketing: we filter by `created_at` (when Neuz received the
    # item) rather than `published_at` (when the source published it). The
    # mental model is "what arrived on my dashboard today", not "what the
    # world emitted in the last 24h". The source publish date is still
    # shown on each card as "X days ago / Mar 4" for context.
    def items_in_range(start_utc, end_utc, categories)
      ds = DB.connection[:items]
        .where(Sequel.lit("created_at >= ? AND created_at < ?", start_utc, end_utc))
        .order(Sequel.desc(:created_at))
        .limit(500)

      selected = Array(categories).flatten.compact.reject(&:empty?)
      ds = ds.where(category: selected) if selected.any?

      rows = ds.all
      tag_map = tags_for(rows.map { |r| r[:id] })
      rows.each { |r| r[:tags] = tag_map[r[:id]] || [] }
      rows
    end

    def tags_for(item_ids)
      return {} if item_ids.empty?

      DB.connection[:item_tags].where(item_id: item_ids).all.each_with_object({}) do |row, acc|
        (acc[row[:item_id]] ||= []) << row[:tag]
      end
    end

    CHIP_CACHE = { at: Time.at(0), data: [] }
    CHIP_LOCK = Mutex.new

    def chip_set
      now = Time.now.utc
      return CHIP_CACHE[:data] if now - CHIP_CACHE[:at] < 60

      CHIP_LOCK.synchronize do
        return CHIP_CACHE[:data] if now - CHIP_CACHE[:at] < 60

        rows = DB.connection[:items]
          .where(Sequel.lit("created_at >= ?", now - 30 * 86_400))
          .exclude(category: nil)
          .group_and_count(:category)
          .order(Sequel.desc(:count))
          .limit(20)
          .all
        data = rows.map { |row| { category: row[:category], count: row[:count] } }
        CHIP_CACHE[:data] = data
        CHIP_CACHE[:at] = now
        data
      end
    end
  end
end
