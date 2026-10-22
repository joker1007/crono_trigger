module CronoTrigger
  class GlobalExceptionHandler
    def self.handle_global_exception(ex)
      new.handle_global_exception(ex)
    end

    def handle_global_exception(ex)
      handlers = CronoTrigger.config.global_error_handlers
      handlers.each do |handler|
        callable, arity = ensure_callable(handler)

        args = [ex]
        args = arity < 0 ? args : args.take(arity)
        callable.call(*args)
      # Rescue each handler so that an error in one handler does not prevent the following handlers
      rescue Exception => e
        ActiveRecord::Base.logger&.error("CronoTrigger error handler raises error")
        ActiveRecord::Base.logger&.error(e)
      end
    end

    private

    def ensure_callable(callable)
      if callable.respond_to?(:call)
        return callable, callable.arity
      else
        raise ArgumentError, "global error handler must respond to `call`: #{callable.inspect}"
      end
    end
  end
end
