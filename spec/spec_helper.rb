if ENV["CI"]
  require 'simplecov'
  SimpleCov.start

  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

require "rollbar"
require "crono_trigger"
require "serverengine"
require "crono_trigger/rollbar"

require "timecop"

Time.zone = "UTC"

case ENV["DB"]
when "mysql"
  ActiveRecord::Base.establish_connection(
    adapter: "mysql2",
    database: "test"
  )
else
  db_path = File.join(__dir__, "testdb.sqlite3")
  File.unlink(db_path) if File.exist?(db_path)
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: File.join(__dir__, "testdb.sqlite3")
  )

  RSpec.configure do |config|
    config.after(:suite) do
      File.unlink(db_path) if File.exist?(db_path)
    end
  end
end

class Notification < ActiveRecord::Base
  include CronoTrigger::Schedulable
  attr_accessor :execute_callback, :retry_callback

  before_execute do |record|
    record.execute_callback = :before
  end

  after_retry do |record|
    record.retry_callback = :after
  end

  self.crono_trigger_options = {
    retry_limit: 1,
    error_handlers: [
      proc { |ex, record| record.class.results[record.id] = ex.message },
      :error_handler
    ]
  }
  self.track_execution = true

  @results = {}
  def self.results
    @results
  end

  after_execute :after

  def execute
    self.class.results[id] = "executed"
  end

  def after
  end

  def error_handler(ex)
    @error = ex
  end
end

ActiveRecord::Migration.verbose = true

if ActiveRecord.version >= Gem::Version.new("5.2.0")
  ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __FILE__)
  ActiveRecord::Base.connection.migration_context.migrate
else
  ActiveRecord::Migrator.migrate File.expand_path("../db/migrate", __FILE__), nil
end

CronoTrigger.config.model_names = ["Notification"]

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after(:each) do
    ActiveRecord::Base.connection.verify!
    CronoTrigger::Models::Execution.delete_all
    Notification.delete_all
    Notification.results.clear
  end
end
