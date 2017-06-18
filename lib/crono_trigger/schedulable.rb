require "active_support/concern"
require "chrono"

module CronoTrigger
  module Schedulable
    DEFAULT_RETRY_LIMIT = 10
    DEFAULT_RETRY_INTERVAL = 4
    DEFAULT_EXECUTE_LOCK_TIMEOUT = 600

    extend ActiveSupport::Concern

    included do
      class_attribute :crono_trigger_options
      self.crono_trigger_options = {}

      scope :executables, ->(from: Time.current, primary_key_offset: nil, limit: 1000) do
        t = arel_table

        rel = where(t[:next_execute_at].lteq(from))
          .where(t[:execute_lock].lteq(from.to_i - (crono_trigger_options[:execute_lock_timeout] || DEFAULT_EXECUTE_LOCK_TIMEOUT)))

        rel = rel.where(t[:started_at].lteq(from)) if column_names.include?("started_at")
        rel = rel.where(t[:finished_at].gt(from).or(t[:finished_at].eq(nil)))  if column_names.include?("finished_at")
        rel = rel.where(t[primary_key].gt(primary_key_offset)) if primary_key_offset

        rel = rel.order("#{quoted_table_name}.#{quoted_primary_key} ASC").limit(limit)

        rel
      end

      before_create :calculate_next_execute_at
    end

    module ClassMethods
      def executables_with_lock(primary_key_offset: nil, limit: 1000)
        records = nil
        transaction do
          records = executables(primary_key_offset: primary_key_offset, limit: limit).lock.to_a
          unless records.empty?
            where(id: records).update_all(execute_lock: Time.current.to_i)
          end
          records
        end
      end
    end

    def do_execute
      if respond_to?(:crontab) && crontab
        next_time = Chrono::NextTime.new(now: Time.now, source: crontab)
        next_execute_at = next_time.to_time
      end

      execute
      update!(next_execute_at: next_execute_at, execute_lock: 0)
    rescue => e
      columns = self.class.column_names
      attributes = {execute_lock: 0}
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

    private

    def calculate_next_execute_at
      if crontab
        it = Chrono::Iterator.new(crontab)
        next_execute_at = it.next
      end

      self.next_execute_at ||= next_execute_at || Time.current
    end
  end
end
