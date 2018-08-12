require "crono_trigger/worker"

module CronoTrigger
  module Models
    class Worker < ActiveRecord::Base
      self.table_name = "crono_trigger_workers"

      ALIVE_THRESHOLD = CronoTrigger::Worker::HEARTBEAT_INTERVAL * 5

      enum executor_status: {running: "running", quiet: "quiet", shuttingdown: "shuttingdown", shutdown: "shutdown"}
      serialize :polling_model_names, JSON

      scope :alive_workers, proc { where(arel_table[:last_heartbeated_at].gteq(Time.current - ALIVE_THRESHOLD)) }
    end
  end
end
