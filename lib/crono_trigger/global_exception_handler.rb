module CronoTrigger
  class GlobalExceptionHandler
    def self.handle_global_exception(ex)
      new.handle_global_exception(ex)
    end

    def handle_global_exception(ex)
      handlers = CronoTrigger.config.global_error_handlers
      handlers.each do |callable|
        callable, arity = ensure_callable(callable)

        args = [ex]
        args = arity < 0 ? args : args.take(arity)
        callable.call(*args)
      end
    rescue Exception => e
      ActiveRecord::Base.logger.error("CronoTrigger error handler raises error")
      ActiveRecord::Base.logger.error(e)
    end

    private

    def ensure_callable(callable)
      if callable.respond_to?(:call)
        return callable, callable.arity
      end
    end
  end
end
