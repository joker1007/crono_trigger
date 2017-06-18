require "crono_trigger/version"

require "ostruct"
require "active_record"
require "concurrent"
require "crono_trigger/worker"
require "crono_trigger/polling_thread"
require "crono_trigger/schedulable"

module CronoTrigger
  @config = OpenStruct.new(
    polling_thread: 1,
    polling_interval: 5,
    executor_thread: 25,
    model_names: [],
  )

  def self.config
    @config
  end

  def self.configure
    yield config
  end

  def self.load_config(yml, environment = nil)
    config = YAML.load_file(yml)[environment || "default"]
    config.each do |k, v|
      @config[k] = v
    end
  end
end

if defined?(Rails)
  require "crono_trigger/railtie"
end
