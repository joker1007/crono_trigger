module CronoTrigger
  class Railtie < ::Rails::Railtie
    config.after_initialize do
      CronoTrigger.reloader = CronoTrigger::Railtie::Reloader.new
    end

    class Reloader
      def initialize(app = ::Rails.application)
        @app = app
      end

      def call
        @app.reloader.wrap do
          yield
        end
      end
    end
  end
end
