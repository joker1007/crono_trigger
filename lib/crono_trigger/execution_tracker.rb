module CronoTrigger
  class ExecutionTracker
    def initialize(schedulable)
      @schedulable = schedulable
    end

    def self.track(schedulable, &pr)
      new(schedulable).track(&pr)
    end

    def track(&pr)
      if @schedulable.track_execution
        begin
          execution = @schedulable.crono_trigger_executions.create_with_timestamp!
          result = pr.call
          case result
          when :ok
            execution.complete!
          when :retry
            execution.retrying!
          when :abort
            execution.aborted!
          else
            execution.complete!
          end
        rescue => e
          execution.error!(e)
          raise
        end
      else
        pr.call
      end
    end
  end
end
