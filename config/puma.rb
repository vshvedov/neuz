# Puma configuration for Neuz.
# Tuned for single-process operation suitable for a Pi or a small VPS.

_workers = Integer(ENV.fetch("NEUZ_WEB_WORKERS", "0"))
workers _workers
threads_min = Integer(ENV.fetch("NEUZ_WEB_THREADS_MIN", "1"))
threads_max = Integer(ENV.fetch("NEUZ_WEB_THREADS_MAX", "5"))
threads threads_min, threads_max

port Integer(ENV.fetch("PORT", "9292"))
environment ENV.fetch("RACK_ENV", "production")

# Single-mode (workers=0) is the default: no forking, no SQLite fork hazards,
# and the prune daemon thread that boot.rb starts lives in the same process
# as the web threads. Bump NEUZ_WEB_WORKERS only if you also set
# NEUZ_PRUNE_DAYS=0 and run prune from an external cron — and be aware that
# SQLite WAL is fine across processes but the rate-limit token bucket has
# higher contention.
if _workers.positive?
  preload_app!
  before_fork do
    if defined?(Neuz::DB)
      Neuz::DB.disconnect!
    end
  end
  on_worker_boot do
    Neuz.instance_variable_set(:@booted, false)
    Neuz.boot!
  end
end
