require "rake/testtask"
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

namespace :db do
  desc "Run Sequel migrations against the configured database"
  task :migrate, [:version] do |_, args|
    require "sequel"
    require "neuz/config"
    Neuz::Config.ensure_data_dir!
    Sequel.extension :migration
    db = Sequel.connect(Neuz::Config.database_url)
    migrations = File.expand_path("db/migrations", __dir__)
    if args[:version]
      Sequel::Migrator.run(db, migrations, target: args[:version].to_i)
    else
      Sequel::Migrator.run(db, migrations)
    end
    puts "Migrations applied."
  end

  desc "Drop the SQLite database file"
  task :drop do
    require "neuz/config"
    path = Neuz::Config.database_path
    File.delete(path) if File.exist?(path)
    File.delete("#{path}-wal") if File.exist?("#{path}-wal")
    File.delete("#{path}-shm") if File.exist?("#{path}-shm")
    puts "Dropped #{path}"
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test
