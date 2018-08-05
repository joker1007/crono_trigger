require "crono_trigger/worker"

module CronoTrigger
  module Models
    class Worker < ActiveRecord::Base
      self.table_name = "crono_trigger_workers"

      ALIVE_THRESHOLD = CronoTrigger::Worker::HEARTBEAT_INTERVAL * 5

      scope :alive_workers, proc { where(arel_table[:last_heartbeated_at].gteq(Time.current - ALIVE_THRESHOLD)) }
    end
  end
end
