require 'rollbar'

module Rollbar
  class CronoTrigger
    def self.handle_exception(ex, record)
      scope = {
        framework: "CronoTrigger: #{::CronoTrigger::VERSION}",
        context: "#{record.class}/#{record.id}"
      }

      Rollbar.scope(scope).error(ex, use_exception_level_filters: true)
    end
  end
end

Rollbar.plugins.define('crono_trigger') do
  require_dependency('crono_trigger')

  execute! do
    CronoTrigger.config.error_handlers << proc do |ex, record|
      Rollbar.reset_notifier!
      Rollbar::CronoTrigger.handle_exception(ex, record)
    end
  end
end
