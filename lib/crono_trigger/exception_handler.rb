module CronoTrigger
  class ExceptionHandler
    def self.handle_exception(record, ex)
      new(record).handle_exception(ex)
    end

    def initialize(record)
      @record = record
    end

    def handle_exception(ex)
      handlers = CronoTrigger.config.error_handlers + Array(@record.crono_trigger_options[:error_handlers])
      handlers.each do |handler|
        callable, arity = ensure_callable(handler)
        args = [ex, @record]
        args = arity < 0 ? args : args.take(arity)
        callable.call(*args)
      # Rescue each handler so that an error in one handler does not prevent the following handlers
      rescue Exception => e
        @record.logger&.error("CronoTrigger error handler raises error")
        @record.logger&.error(e)
      end
    end

    private

    def ensure_callable(callable)
      if callable.respond_to?(:call)
        return callable, callable.arity
      elsif callable.is_a?(Symbol)
        return @record.method(callable), 1
      else
        raise ArgumentError, "error handler must respond to `call` or be a Symbol: #{callable.inspect}"
      end
    end
  end
end
