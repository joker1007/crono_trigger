require 'rollbar'

module Rollbar
  class CronoTrigger
    def self.handle_exception(ex, record = nil)
      scope = {
        framework: "CronoTrigger: #{::CronoTrigger::VERSION}",
      }

      if record
        scope.merge!({context: "#{record.class}/#{record.id}"})
      end

      Rollbar.scope(scope).error(ex, use_exception_level_filters: true)
    end
  end
end

Rollbar.plugins.define('crono_trigger') do
  require_dependency('crono_trigger')

  execute! do
    CronoTrigger.config.error_handlers << proc do |ex, record|
      Rollbar::CronoTrigger.handle_exception(ex, record)
    end

    CronoTrigger.config.global_error_handlers << proc do |ex|
      Rollbar::CronoTrigger.handle_exception(ex)
    end
  end
end
