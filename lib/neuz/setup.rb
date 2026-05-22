require "securerandom"

module Neuz
  # CLI-facing setup primitives. Web routes do not exist; the source
  # of truth for "where does the raw key live" is data/first_boot_key.txt.
  module Setup
    module_function

    # Ensure DB schema, mint a key if none exists, return raw key
    # (read from disk if it's still there, nil if already acknowledged).
    def prepare!
      Neuz.boot!
      raw = read_raw_key
      raw
    end

    def read_raw_key
      path = Config.first_boot_key_path
      return nil unless File.exist?(path)
      File.binread(path)
    end

    def acknowledge!
      path = Config.first_boot_key_path
      if File.exist?(path)
        File.delete(path)
        Neuz::DB.connection[:settings].insert_conflict(
          target: :key,
          update: { value: Sequel[:excluded][:value], updated_at: Time.now.utc },
        ).insert(
          key: "key_acknowledged_at",
          value: Time.now.utc.iso8601,
          updated_at: Time.now.utc,
        )
        true
      else
        false
      end
    end

    # Rotate the key: generate a new raw key, replace the api_keys row,
    # clear the rate bucket, drop the acknowledged setting, write a new
    # raw-key file. Returns the new raw key.
    def rotate!
      Neuz.boot!
      raw = SecureRandom.urlsafe_base64(32)
      digest = Auth.digest(raw)
      DB.connection.transaction do
        row = DB.connection[:api_keys].order(:id).first
        if row
          DB.connection[:api_keys].where(id: row[:id]).update(
            sha256: digest,
            last_used_at: nil,
          )
          DB.connection[:rate_buckets].where(api_key_id: row[:id]).delete
        else
          DB.connection[:api_keys].insert(
            user_id: 1, sha256: digest, label: "default",
            created_at: Time.now.utc,
          )
        end
        DB.connection[:settings].where(key: "key_acknowledged_at").delete
      end
      File.binwrite(Config.first_boot_key_path, raw)
      File.chmod(0o600, Config.first_boot_key_path)
      raw
    end

    def acknowledged?
      DB.connection[:settings].where(key: "key_acknowledged_at").any?
    end

    def status
      Neuz.boot!
      {
        url: Config.public_url || "(set NEUZ_URL or rely on request base URL)",
        version: Neuz.version,
        items_total: DB.connection[:items].count,
        items_today: items_today_count,
        key_file_present: File.exist?(Config.first_boot_key_path),
        key_acknowledged: acknowledged?,
        data_dir: Config.data_dir,
        db_path: Config.database_path,
      }
    end

    def items_today_count
      now = Time.now.utc
      start = Time.utc(now.year, now.month, now.day)
      DB.connection[:items]
        .where(Sequel.lit("published_at >= ? AND published_at < ?", start, start + 86_400))
        .count
    end

    # Build the banner string. url and raw_key are passed in so callers
    # can decide where to source them (env, request, file, freshly minted).
    def banner(url:, raw_key:, acknowledged: false)
      rule = "─" * 64
      buf = +"\n#{rule}\n  Neuz setup\n#{rule}\n\n"
      buf << "  Instance URL : #{url}\n"
      buf << "  Version      : #{Neuz.version}\n\n"

      if raw_key
        buf << "  API key (copy this once):\n\n"
        buf << "      #{raw_key}\n\n"
        buf << "  After you've copied it, run:  bin/neuz acknowledge\n"
        buf << "  (Or pass --acknowledge to setup to do it now.)\n\n"
      elsif acknowledged
        buf << "  This instance has already been acknowledged.\n"
        buf << "  The raw key is no longer recoverable. Rotate to mint a new one:\n"
        buf << "      bin/neuz rotate\n\n"
      else
        buf << "  Neuz is configured but the raw key file is missing.\n"
        buf << "  Rotate to mint a new one:\n"
        buf << "      bin/neuz rotate\n\n"
      end

      buf << "#{rule}\n"
      buf << "  Claude prompt (paste into Claude Code)\n"
      buf << "#{rule}\n\n"

      if raw_key
        buf << "  This is the ONE-TIME interview prompt. Paste it into Claude Code\n"
        buf << "  and answer the AskUserQuestion sequence. Claude will then print\n"
        buf << "  a personalized recurring prompt — paste THAT into Claude\n"
        buf << "  Routines / Cowork on the cadence you want.\n\n"
        Prompts.interview(url: url, api_key: raw_key).each_line { |l| buf << "      #{l}" }
        buf << "\n\n"
      else
        buf << "  (Run `bin/neuz rotate` first; the prompt needs a raw key to substitute into.)\n\n"
      end
      buf << "#{rule}\n"
      buf
    end
  end
end
