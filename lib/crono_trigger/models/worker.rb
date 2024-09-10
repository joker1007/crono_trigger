require "crono_trigger/worker"

module CronoTrigger
  module Models
    class Worker < ActiveRecord::Base
      self.table_name = "crono_trigger_workers"

      ALIVE_THRESHOLD = CronoTrigger::Worker::HEARTBEAT_INTERVAL * 5

      if ActiveRecord.version >= Gem::Version.new("7.0")
        enum :executor_status, {running: "running", quiet: "quiet", shuttingdown: "shuttingdown", shutdown: "shutdown"}
      else
        enum executor_status: {running: "running", quiet: "quiet", shuttingdown: "shuttingdown", shutdown: "shutdown"}
      end

      if ActiveRecord.version >= Gem::Version.new("7.1.0")
        serialize :polling_model_names, coder: JSON
      else
        serialize :polling_model_names, JSON
      end

      scope :alive_workers, proc { where(arel_table[:last_heartbeated_at].gteq(Time.current - ALIVE_THRESHOLD)) }
    end
  end
end
