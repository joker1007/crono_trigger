module CronoTrigger
  class ExecutionTracker
    def initialize(schedulable)
      @schedulable = schedulable
    end

    def track(&pr)
      if @schedulable.track_execution
        begin
          execution = @schedulable.crono_trigger_executions.create_with_timestamp!
          pr.call
          execution.complete!
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
