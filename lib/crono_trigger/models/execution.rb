module CronoTrigger
  module Models
    class Execution < ActiveRecord::Base
      self.table_name = "crono_trigger_executions"

      belongs_to :schedule, polymorphic: true, inverse_of: :crono_trigger_executions

      scope :recently, ->(schedule_type:) { where(schedule_type: schedule_type).order(executed_at: :desc) }

      enum status: {
        executing: "executing", 
        completed: "completed",
        failed: "failed",
      }

      def self.create_with_timestamp!
        create!(executed_at: Time.current, status: :executing, worker_id: CronoTrigger.config.worker_id)
      end

      def complete!
        update!(status: :completed, completed_at: Time.current)
      end

      def error!(exception)
        update!(status: :failed, completed_at: Time.current, error_name: exception.class.to_s, error_reason: exception.message)
      end

      def retry!
        return false if schedule.locking?

        schedule.retry!
      end
    end
  end
end
