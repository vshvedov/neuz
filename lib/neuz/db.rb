require "sequel"
require "logger"

module Neuz
  module DB
    module_function

    def connect!
      @connection ||= begin
        Sequel.default_timezone = :utc
        Sequel.database_timezone = :utc
        Sequel.application_timezone = :utc

        db = Sequel.connect(Config.database_url,
          max_connections: Integer(ENV.fetch("NEUZ_DB_POOL", "5")),
          pool_timeout: 5,
          after_connect: ->(conn) { apply_pragmas(conn) },
        )
        # Run after_connect synchronously on the first connection too.
        # Sequel applies after_connect for new connections; we also want
        # the very first one to have pragmas before the pool hands it out.
        db.pool.send(:sync) { } if db.pool.respond_to?(:sync, true)
        db
      end
    end

    def connection
      connect!
    end

    def disconnect!
      @connection&.disconnect
      @connection = nil
    end

    def apply_pragmas(raw_conn)
      pragmas = [
        "journal_mode=#{Config.journal_mode}",
        "synchronous=NORMAL",
        "busy_timeout=5000",
        "temp_store=MEMORY",
        "foreign_keys=ON",
        "cache_size=#{Config.cache_size}",
        "mmap_size=#{Config.mmap_size}",
      ]
      pragmas.each do |p|
        raw_conn.execute_batch("PRAGMA #{p};")
      rescue StandardError
        # journal_mode returns a row; execute_batch is fine on most adapters.
        # Fall back to plain execute when execute_batch is missing.
        raw_conn.execute("PRAGMA #{p};") rescue nil
      end
    end

    def migrate!
      Sequel.extension :migration
      Sequel::Migrator.run(connection, Config.migrations_dir)
    end

    def warn_if_networked_filesystem
      return unless File.exist?(Config.data_dir)
      return unless RUBY_PLATFORM.include?("linux")

      output = `df -T #{Config.data_dir} 2>/dev/null`
      return if output.nil? || output.empty?

      bad = %w[nfs nfs4 cifs smb smbfs fuse.sshfs]
      type_line = output.lines.last
      return unless type_line

      type = type_line.split[1]
      if type && bad.include?(type.downcase)
        warn "[neuz] WARNING: data dir #{Config.data_dir} appears to live on a #{type} mount; SQLite WAL requires a local filesystem. Set NEUZ_JOURNAL_MODE=DELETE to fall back, or move the volume."
      end
    rescue StandardError => e
      warn "[neuz] could not probe data dir filesystem: #{e.class}: #{e.message}"
    end

    def healthy?
      connection.fetch("SELECT 1 AS ok").first[:ok] == 1
    rescue StandardError
      false
    end
  end
end
