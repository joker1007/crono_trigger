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

      scope :executables, ->(from: Time.current, limit: CronoTrigger.config.executor_thread * 3, including_locked: false) do
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

      before_create :set_current_cycle_id
      before_update :update_next_execute_at_if_update_cron

      validate :validate_cron_format
    end

    module ClassMethods
      # Requires a database that supports `FOR UPDATE SKIP LOCKED` (MySQL 8.0+, PostgreSQL 9.5+).
      # Rows locked by other workers' transactions are skipped instead of waited for.
      def executables_with_lock(limit: CronoTrigger.config.fetch_records)
        now = Time.current
        attributes = {
          crono_trigger_column_name(:execute_lock) => now.to_i,
          crono_trigger_column_name(:locked_by) => CronoTrigger.config.worker_id,
        }
        attributes["updated_at"] = now if column_names.include?("updated_at")

        records = transaction do
          rs = executables(from: now, limit: limit).lock("FOR UPDATE SKIP LOCKED").to_a
          unscoped.where(primary_key => rs.map(&:id)).update_all(attributes) unless rs.empty?
          rs
        end

        records.each do |r|
          r.assign_attributes(attributes)
          r.clear_changes_information
        end

        [records, records.size >= limit]
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

      # Reassign instead of mutating because class_attribute shares the same object with subclasses
      def add_executable_conditions(pr)
        self.executable_conditions = executable_conditions + [pr]
      end

      def clear_executable_conditions
        self.executable_conditions = []
      end
    end

    # A copy does not hold the lock, but `dup` would share the lock state of the original during an execution
    private def initialize_dup(other)
      super
      @crono_trigger_holding_lock = nil
    end

    def do_execute
      @crono_trigger_holding_lock = {
        crono_trigger_column_name(:execute_lock) => self[crono_trigger_column_name(:execute_lock)],
        crono_trigger_column_name(:locked_by) => self[crono_trigger_column_name(:locked_by)],
      }
      ExecutionTracker.track(self) do
        do_execute_with_catch
      end
    rescue Exception => ex
      logger.error(ex) if logger
      save_last_error_info(ex)
      retry_or_reset!(ex)
    ensure
      @crono_trigger_holding_lock = nil
    end

    private def do_execute_with_catch
      catch(:ok_without_reset) do
        catch(:ok) do
          catch(:retry) do
            catch(:abort) do
              run_callbacks :execute do
                execute
              end
              throw :ok
            end
            abort_execution!
            return :abort
          end
          retry!
          return :retry
        end
        reset!
        return :ok
      end
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
        has_retry_count = self.class.column_names.include?("retry_count")
        current_retry_count = has_retry_count ? retry_count.to_i : 0
        if immediately
          wait = 0
        else
          wait = crono_trigger_options[:exponential_backoff] ? retry_interval * (2 ** current_retry_count) : retry_interval
        end
        attributes = {
          crono_trigger_column_name(:next_execute_at) => now + wait,
          crono_trigger_column_name(:execute_lock) => 0,
          crono_trigger_column_name(:locked_by) => nil,
        }

        if has_retry_count
          attributes.merge!(retry_count: current_retry_count + 1)
        end

        merge_updated_at_for_crono_trigger!(attributes, now)
        update_crono_trigger_columns(attributes)
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

      if self.class.column_names.include?(crono_trigger_column_name(:current_cycle_id))
        attributes.merge!(crono_trigger_column_name(:current_cycle_id) => SecureRandom.uuid)
      end

      merge_updated_at_for_crono_trigger!(attributes, now)
      update_crono_trigger_columns(attributes)
    end

    def abort_execution!
      reset!(false)
    end

    def crono_trigger_lock!(**attributes)
      attributes = {
        crono_trigger_column_name(:execute_lock) => Time.current.to_i,
        crono_trigger_column_name(:locked_by) => CronoTrigger.config.worker_id
      }.merge(attributes)
      merge_updated_at_for_crono_trigger!(attributes)
      if new_record?
        self.attributes = attributes
      else
        update_columns(attributes)
      end
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

    def execute_now
      crono_trigger_lock!(next_execute_at: Time.now)
      save! if new_record?
      do_execute
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
        started_at = self[crono_trigger_column_name(:started_at)]
        if started_at&.>(now)
          calculated = calculate_next_execute_at_by_started_at(started_at, tz)
        else
          cron_now = tz ? now.in_time_zone(tz) : now
          calculated = Chrono::NextTime.new(now: cron_now, source: self[crono_trigger_column_name(:cron)]).to_time
        end

        return calculated unless self[crono_trigger_column_name(:finished_at)]
        return if calculated > self[crono_trigger_column_name(:finished_at)]

        calculated
      end
    end

    # If the cron definition and started_at match, include the time of started_at as the next execute_at
    def calculate_next_execute_at_by_started_at(started_at, timezone)
      cron_now = timezone ? started_at.in_time_zone(timezone) : started_at
      schedule = Chrono::Schedule.new(self[crono_trigger_column_name(:cron)])

      if schedule.minutes.include?(cron_now.min) &&
        schedule.hours.include?(cron_now.hour) &&
        (schedule.days.include?(cron_now.day) || schedule.days.empty?) &&
        schedule.months.include?(cron_now.month) &&
        schedule.wdays.include?(cron_now.wday) &&
        cron_now.sec == 0

        # Execute job at started_at
        cron_now
      else
        Chrono::NextTime.new(now: cron_now, source: self[crono_trigger_column_name(:cron)]).to_time
      end
    end

    def set_current_cycle_id
      if self.class.column_names.include?(crono_trigger_column_name(:current_cycle_id)) &&
          self[crono_trigger_column_name(:current_cycle_id)].nil?
        self[crono_trigger_column_name(:current_cycle_id)] = SecureRandom.uuid
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
      update_crono_trigger_columns(attributes) unless attributes.empty?
    end

    # While executing, update only if this record still holds the lock acquired before the execution.
    # Otherwise, the record has been locked by another worker after execute_lock_timeout, and updating it would
    # overwrite the schedule which another worker is executing.
    # Outside of executions (e.g. operations from the admin web), update unconditionally as before.
    def update_crono_trigger_columns(attributes)
      return update_columns(attributes) unless @crono_trigger_holding_lock

      updated_count = self.class.unscoped
        .where(self.class.primary_key => id)
        .where(@crono_trigger_holding_lock)
        .update_all(attributes)
      if updated_count.zero?
        logger&.warn("Skip updating #{self.class}-#{id} because the record has been deleted or locked by another worker")
        return false
      end

      attributes.each { |name, value| self[name] = value }
      clear_attribute_changes(attributes.keys.map(&:to_s))
      @crono_trigger_holding_lock.each_key do |name|
        @crono_trigger_holding_lock[name] = attributes[name] if attributes.key?(name)
      end
      true
    end

    def merge_updated_at_for_crono_trigger!(attributes, time = Time.current)
      if self.class.column_names.include?("updated_at")
        attributes.merge!("updated_at" => time)
      end
    end
  end
end
