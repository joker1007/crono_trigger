require "crono_trigger"
require "serverengine"

require "timecop"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

class Notification < ActiveRecord::Base
  include CronoTrigger::Schedulable

  @results = {}
  def self.results
    @results
  end

  def execute
    self.class.results[id] = "executed"
  end
end

ActiveRecord::Migration.verbose = false
ActiveRecord::Migrator.migrate File.expand_path("../db/migrate", __FILE__), nil

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after(:each) do
    Notification.delete_all
    Notification.results.clear
  end
end
