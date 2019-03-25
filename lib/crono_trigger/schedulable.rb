require "active_support/concern"
require "active_support/core_ext/object"
require "chrono"
require "tzinfo"

require "crono_trigger/exception_handler"
require "crono_trigger/execution_tracker"

module CronoTrigger
  module Schedulable
    DEFAULT_RETRY_LIMIT = 10
    DEFAULT_RETRY_INTERVAL = 4
    DEFAULT_EXECUTE_LOCK_TIMEOUT = 600

    class NoRestrictedUnlockError < StandardError; end

    @included_by = []

    def self.included_by
      @included_by
    end

    class AbortExecution < StandardError; end

    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    included do
      CronoTrigger::Schedulable.included_by << self
      class_attribute :crono_trigger_options, :executable_conditions, :track_execution
      self.crono_trigger_options ||= {}
      self.executable_conditions ||= []
      self.track_execution ||= false

      has_many :crono_trigger_executions, class_name: "CronoTrigger::Models::Execution", as: :schedule, inverse_of: :schedule

      define_model_callbacks :execute, :retry

      scope :executables, ->(from: Time.current, limit: CronoTrigger.config.executor_thread * 3 || 100, including_locked: false) do
        t = arel_table

        rel = where(t[crono_trigger_column_name(:next_execute_at)].lteq(from))
        rel = rel.where(t[crono_trigger_column_name(:execute_lock)].lt(from.to_i - execute_lock_timeout)) unless including_locked

        rel = rel.where(t[crono_trigger_column_name(:started_at)].lteq(from)) if column_names.include?(crono_trigger_column_name(:started_at))
        rel = rel.where(t[crono_trigger_column_name(:finished_at)].gt(from).or(t[crono_trigger_column_name(:finished_at)].eq(nil)))  if column_names.include?(crono_trigger_column_name(:finished_at))

        rel = rel.order(crono_trigger_column_name(:next_execute_at) => :asc).limit(limit)

        rel = executable_conditions.reduce(rel) do |merged, pr|
          if pr.arity == 0
            merged.merge(instance_exec(&pr))
          else
            merged.merge(instance_exec(from, &pr))
          end
        end

        rel
      end

      before_update :update_next_execute_at_if_update_cron

      validate :validate_cron_format
    end

    module ClassMethods
      def executables_with_lock(limit: CronoTrigger.config.executor_thread * 3 || 100)
        ids = executables(limit: limit).pluck(:id)
        records = []
        ids.each do |id|
          transaction do
            r = all.lock.find(id)
            unless r.locking?
              r.crono_trigger_lock!
              records << r
            end
          end
        end
        records
      end

      def crono_trigger_column_name(name)
        crono_trigger_options["#{name}_column_name".to_sym].try(:to_s) || name.to_s
      end

      def execute_lock_timeout
        (crono_trigger_options[:execute_lock_timeout] || DEFAULT_EXECUTE_LOCK_TIMEOUT)
      end

      def crono_trigger_unlock_all!
        wheres = all.where_values_hash
        if wheres.empty?
          raise NoRestrictedUnlockError, "Need `where` filter at least one, because this method is danger"
        else
          update_all(
            crono_trigger_column_name(:execute_lock) => 0,
            crono_trigger_column_name(:locked_by) => nil,
          )
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
      execution_tracker = ExecutionTracker.new(self)
      run_callbacks :execute do
        catch(:ok_without_reset) do
          catch(:ok) do
            catch(:retry) do
              catch(:abort) do
                execution_tracker.track do
                  execute
                end
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

    def activate_schedule!(at: Time.current)
      time = calculate_next_execute_at || at

      attributes = {}
      unless self[crono_trigger_column_name(:next_execute_at)]
        attributes[crono_trigger_column_name(:next_execute_at)] = time
      end

      if self.class.column_names.include?(crono_trigger_column_name(:started_at))
        unless self[crono_trigger_column_name(:started_at)]
          attributes[crono_trigger_column_name(:started_at)] = time
        end
      end

      if new_record?
        self.attributes = attributes
      else
        merge_updated_at_for_crono_trigger!(attributes)
        update_columns(attributes)
      end

      self
    end

    def retry!(immediately: false)
      run_callbacks :retry do
        logger.info "Retry #{self.class}-#{id}" if logger

        now = Time.current
        if immediately
          wait = 0
        else
          wait = crono_trigger_options[:exponential_backoff] ? retry_interval * [2 * (retry_count - 1), 1].max : retry_interval
        end
        attributes = {
          crono_trigger_column_name(:next_execute_at) => now + wait,
          crono_trigger_column_name(:execute_lock) => 0,
          crono_trigger_column_name(:locked_by) => nil,
        }

        if self.class.column_names.include?("retry_count")
          attributes.merge!(retry_count: retry_count.to_i + 1)
        end

        merge_updated_at_for_crono_trigger!(attributes, now)
        update_columns(attributes)
      end
    end

    def reset!(update_last_executed_at = true)
      logger.info "Reset execution schedule #{self.class}-#{id}" if logger

      attributes = {
        crono_trigger_column_name(:next_execute_at) => calculate_next_execute_at,
        crono_trigger_column_name(:execute_lock) => 0,
        crono_trigger_column_name(:locked_by) => nil,
      }

      now = Time.current

      if update_last_executed_at && self.class.column_names.include?(crono_trigger_column_name(:last_executed_at))
        attributes.merge!(crono_trigger_column_name(:last_executed_at) => now)
      end

      if self.class.column_names.include?("retry_count")
        attributes.merge!(retry_count: 0)
      end

      merge_updated_at_for_crono_trigger!(attributes, now)
      update_columns(attributes)
    end

    def crono_trigger_lock!
      attributes = {
        crono_trigger_column_name(:execute_lock) => Time.current.to_i,
        crono_trigger_column_name(:locked_by) => CronoTrigger.config.worker_id
      }
      merge_updated_at_for_crono_trigger!(attributes)
      update_columns(attributes)
    end

    def crono_trigger_unlock!
      attributes = {
        crono_trigger_column_name(:execute_lock) => 0,
        crono_trigger_column_name(:locked_by) => nil,
      }
      merge_updated_at_for_crono_trigger!(attributes)
      update_columns(attributes)
    end

    def crono_trigger_status
      case
      when locking?
        :locked
      when waiting?
        :waiting
      when not_scheduled?
        :not_scheduled
      end
    end

    def waiting?
      !!self[crono_trigger_column_name(:next_execute_at)]
    end

    def not_scheduled?
      self[crono_trigger_column_name(:next_execute_at)].nil? && last_executed_at.nil?
    end

    def locking?(at: Time.now)
      self[crono_trigger_column_name(:execute_lock)] > 0 && 
        self[crono_trigger_column_name(:execute_lock)] >= at.to_f - self.class.execute_lock_timeout
    end

    def assume_executing?
      locking?
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
        base = [now, self[crono_trigger_column_name(:started_at)]].compact.max
        cron_now = tz ? base.in_time_zone(tz) : base
        Chrono::NextTime.new(now: cron_now, source: self[crono_trigger_column_name(:cron)]).to_time
      end
    end

    def update_next_execute_at_if_update_cron
      if changes[crono_trigger_column_name(:cron)] || changes[crono_trigger_column_name(:timezone)]
        if self[crono_trigger_column_name(:cron)]
          self[crono_trigger_column_name(:next_execute_at)] = calculate_next_execute_at
        end
      end
    end

    def validate_cron_format
      return unless self[crono_trigger_column_name(:cron)]

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

      merge_updated_at_for_crono_trigger!(attributes)
      update_columns(attributes) unless attributes.empty?
    end

    def merge_updated_at_for_crono_trigger!(attributes, time = Time.current)
      if self.class.column_names.include?("updated_at")
        attributes.merge!("updated_at" => time)
      end
    end
  end
end
