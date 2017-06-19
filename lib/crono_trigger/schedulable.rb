require "active_support/concern"
require "chrono"

module CronoTrigger
  module Schedulable
    DEFAULT_RETRY_LIMIT = 10
    DEFAULT_RETRY_INTERVAL = 4
    DEFAULT_EXECUTE_LOCK_TIMEOUT = 600

    class AbortExecution < StandardError; end

    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    included do
      class_attribute :crono_trigger_options, :executable_conditions
      self.crono_trigger_options = {}
      self.executable_conditions = []

      define_model_callbacks :execute

      scope :executables, ->(from: Time.current, primary_key_offset: nil, limit: 1000) do
        t = arel_table

        rel = where(t[:next_execute_at].lteq(from))
          .where(t[:execute_lock].lteq(from.to_i - (crono_trigger_options[:execute_lock_timeout] || DEFAULT_EXECUTE_LOCK_TIMEOUT)))

        rel = rel.where(t[:started_at].lteq(from)) if column_names.include?("started_at")
        rel = rel.where(t[:finished_at].gt(from).or(t[:finished_at].eq(nil)))  if column_names.include?("finished_at")
        rel = rel.where(t[primary_key].gt(primary_key_offset)) if primary_key_offset

        rel = rel.order("#{quoted_table_name}.#{quoted_primary_key} ASC").limit(limit)

        rel = executable_conditions.reduce(rel) do |merged, pr|
          if pr.arity == 0
            merged.merge(instance_exec(&pr))
          else
            merged.merge(instance_exec(from, &pr))
          end
        end

        rel
      end

      before_create :ensure_next_execute_at
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

      private

      def add_executable_conditions(pr)
        self.executable_conditions << pr
      end

      def clear_executable_conditions
        self.executable_conditions.clear
      end
    end

    def do_execute
      run_callbacks :execute do
        catch(:ok) do
          catch(:retry) do
            catch(:abort) do
              execute
              throw :ok
            end
            raise AbortExecution
          end
          retry!
          return
        end
        reset!(true)
      end
    rescue AbortExecution => ex
      save_last_error_info(ex)
      reset!

      raise
    rescue Exception => ex
      save_last_error_info(ex)
      retry_or_reset!

      raise
    end

    def retry!
      logger.info "Retry #{self.class}-#{id}" if logger

      now = Time.current
      wait = crono_trigger_options[:exponential_backoff] ? retry_interval * [2 * (retry_count - 1), 1].max : retry_interval
      attributes = {next_execute_at: now + wait, execute_lock: 0}

      if self.class.column_names.include?("retry_count")
        attributes.merge!(retry_count: retry_count.to_i + 1)
      end

      update_columns(attributes)
    end

    def reset!(update_last_executed_at = false)
      logger.info "Reset execution schedule #{self.class}-#{id}" if logger

      attributes = {next_execute_at: calculate_next_execute_at, execute_lock: 0}

      if update_last_executed_at && self.class.column_names.include?("last_executed_at")
        attributes.merge!(last_executed_at: Time.current)
      end

      if self.class.column_names.include?("retry_count")
        attributes.merge!(retry_count: 0)
      end

      update_columns(attributes)
    end

    private

    def retry_or_reset!
      if respond_to?(:retry_count) && retry_count.to_i <= retry_limit
        retry!
      else
        reset!
      end
    end

    def calculate_next_execute_at
      if respond_to?(:cron) && cron
        it = Chrono::Iterator.new(cron)
        it.next
      end
    end

    def ensure_next_execute_at
      self.next_execute_at ||= calculate_next_execute_at || Time.current
    end

    def retry_limit
      crono_trigger_options[:retry_limit] || DEFAULT_RETRY_LIMIT
    end

    def retry_interval
      crono_trigger_options[:retry_interval] || DEFAULT_RETRY_INTERVAL
    end

    def save_last_error_info(ex)
      columns = self.class.column_names
      attributes = {}
      now = Time.current

      if columns.include?("last_error_name")
        attributes.merge!(last_error_name: ex.class.to_s)
      end

      if columns.include?("last_error_reason")
        attributes.merge!(last_error_reason: ex.message)
      end

      if columns.include?("last_error_time")
        attributes.merge!(last_error_time: now)
      end

      update_columns(attributes)
    end
  end
end
