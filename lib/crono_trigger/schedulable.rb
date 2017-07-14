require "active_support/concern"
require "active_support/core_ext/object"
require "chrono"
require "tzinfo"

require "crono_trigger/exception_handler"

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
      self.crono_trigger_options ||= {}
      self.executable_conditions ||= []

      define_model_callbacks :execute

      scope :executables, ->(from: Time.current, primary_key_offset: nil, limit: 1000) do
        t = arel_table

        rel = where(t[crono_trigger_column_name(:next_execute_at)].lteq(from))
          .where(t[crono_trigger_column_name(:execute_lock)].lteq(from.to_i - execute_lock_timeout))

        rel = rel.where(t[crono_trigger_column_name(:started_at)].lteq(from)) if column_names.include?(crono_trigger_column_name(:started_at))
        rel = rel.where(t[crono_trigger_column_name(:finished_at)].gt(from).or(t[crono_trigger_column_name(:finished_at)].eq(nil)))  if column_names.include?(crono_trigger_column_name(:finished_at))
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
      before_update :update_next_execute_at_if_update_cron

      validate :validate_cron_format
    end

    module ClassMethods
      def executables_with_lock(primary_key_offset: nil, limit: 1000)
        records = nil
        transaction do
          records = executables(primary_key_offset: primary_key_offset, limit: limit).lock.to_a
          unless records.empty?
            where(id: records).update_all(crono_trigger_column_name(:execute_lock) => Time.current.to_i)
          end
          records
        end
      end

      def crono_trigger_column_name(name)
        crono_trigger_options["#{name}_column_name".to_sym].try(:to_s) || name.to_s
      end

      def execute_lock_timeout
        (crono_trigger_options[:execute_lock_timeout] || DEFAULT_EXECUTE_LOCK_TIMEOUT)
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
        catch(:ok_without_reset) do
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
          reset!
        end
      end
    rescue AbortExecution => ex
      save_last_error_info(ex)
      reset!(false)

      raise
    rescue Exception => ex
      save_last_error_info(ex)
      retry_or_reset!(ex)

      raise
    end

    def retry!
      logger.info "Retry #{self.class}-#{id}" if logger

      now = Time.current
      wait = crono_trigger_options[:exponential_backoff] ? retry_interval * [2 * (retry_count - 1), 1].max : retry_interval
      attributes = {crono_trigger_column_name(:next_execute_at) => now + wait, crono_trigger_column_name(:execute_lock) => 0}

      if self.class.column_names.include?("retry_count")
        attributes.merge!(retry_count: retry_count.to_i + 1)
      end

      update_columns(attributes)
    end

    def reset!(update_last_executed_at = true)
      logger.info "Reset execution schedule #{self.class}-#{id}" if logger

      attributes = {crono_trigger_column_name(:next_execute_at) => calculate_next_execute_at, crono_trigger_column_name(:execute_lock) => 0}

      if update_last_executed_at && self.class.column_names.include?(crono_trigger_column_name(:last_executed_at))
        attributes.merge!(crono_trigger_column_name(:last_executed_at) => Time.current)
      end

      if self.class.column_names.include?("retry_count")
        attributes.merge!(retry_count: 0)
      end

      update_columns(attributes)
    end

    def assume_executing?
      execute_lock_timeout = self.class.execute_lock_timeout
      locking? &&
        self[crono_trigger_column_name(:execute_lock)] + execute_lock_timeout >= Time.now.to_i
    end

    def locking?
      self[crono_trigger_column_name(:execute_lock)] > 0
    end

    def idling?
      !locking?
    end

    def crono_trigger_column_name(name)
      self.class.crono_trigger_column_name(name)
    end

    private

    def retry_or_reset!(ex)
      if respond_to?(:retry_count) && retry_count.to_i < retry_limit
        retry!
      else
        CronoTrigger::ExceptionHandler.handle_exception(self, ex)
        reset!(false)
      end
    end

    def calculate_next_execute_at(now = Time.current)
      if self[crono_trigger_column_name(:cron)]
        tz = self[crono_trigger_column_name(:timezone)].try { |zn| TZInfo::Timezone.get(zn) }
        now = tz ? now.in_time_zone(tz) : now
        Chrono::NextTime.new(now: now, source: self[crono_trigger_column_name(:cron)]).to_time
      end
    end

    def ensure_next_execute_at
      self[crono_trigger_column_name(:next_execute_at)] ||= calculate_next_execute_at || Time.current
    end

    def update_next_execute_at_if_update_cron
      if changes[crono_trigger_column_name(:cron)] || changes[crono_trigger_column_name(:timezone)]
        if self[crono_trigger_column_name(:cron)]
          self[crono_trigger_column_name(:next_execute_at)] = calculate_next_execute_at
        end
      end
    end

    def validate_cron_format
      Chrono::NextTime.new(now: Time.current, source: self[crono_trigger_column_name(:cron)]).to_time
    rescue Chrono::Fields::Base::InvalidField
      self.errors.add(
        crono_trigger_column_name(:cron).to_sym,
        crono_trigger_options["invalid_field_error_message"] || "has invalid field"
      )
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

      update_columns(attributes) unless attributes.empty?
    end
  end
end
