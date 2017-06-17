module CronoTrigger
  module Schedulable
    DEFAULT_RETRY_LIMIT = 10
    DEFAULT_RETRY_INTERVAL = 4
    DEFAULT_EXECUTE_LOCK_TIMEOUT = 600

    extend ActiveSupport::Concern

    included do
      scope :executables, ->(from = Time.current) do
        t = arel_table
        where(t[:next_execute_at].lteq(from))
          .where(t[:started_at].lteq(from))
          .where(t[:finished_at].gt(from))
          .where(t[:execute_lock].lteq(from.to_i - (crono_trigger_options[:execute_lock_timeout] || DEFAULT_EXECUTE_LOCK_TIMEOUT)))
      end
    end

    def do_execute
      if respond_to?(:crontab) && crontab
        it = Chrono::Iterator.new(crontab)
        next_execute_at = it.next
      end

      update!(execute_lock: Time.current)
      execute
      update!(next_execute_at: next_execute_at)
    rescue => e
      columns = self.class.column_names
      attributes = {}
      now = Time.current

      if columns.include?("last_error_name")
        attributes.merge!(last_error_name: e.class.to_s)
      end

      if columns.include?("last_error_reason")
        attributes.merge!(last_error_reason: e.message)
      end

      if columns.include?("last_error_time")
        attributes.merge!(last_error_time: now)
      end

      if columns.include?("retry_count")
        attributes.merge!(retry_count: retry_count + 1)
      end

      retry_limit = crono_trigger_options[:retry_limit] || DEFAULT_RETRY_LIMIT
      retry_interval = crono_trigger_options[:retry_interval] || DEFAULT_RETRY_INTERVAL
      if retry_count <= retry_limit
        wait = crono_trigger_options[:exponential_backoff] ? retry_interval * [2 * (retry_count - 1), 1].max : retry_interval
        attributes(next_execute_at: now + wait)
      end

      update_columns(attributes)

      raise e
    end
  end
end
