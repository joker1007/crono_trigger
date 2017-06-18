require "optparse"
require "crono_trigger"
require "serverengine"

options = {
  daemonize: false,
  pid_path: "./crono_trigger.pid",
}

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: crono_trigger [options] MODEL [MODEL..]"

  opts.on("-f", "--config-file=CONFIG", "Config file (ex. ./crono_trigger.rb)") do |cfg|
    options[:config] = cfg
  end

  opts.on("-e", "--envornment=ENV", "Set environment name (ex. development, production)") do |env|
    options[:env] = env
  end

  opts.on("-p", "--polling-thread=SIZE", Integer, "Polling thread size (Default: 1)") do |i|
    options[:polling_thread] = i
  end

  opts.on("-i", "--polling-interval=SECOND", Integer, "Polling interval seconds (Default: 5)") do |i|
    options[:polling_interval] = i
  end

  opts.on("-c", "--concurrency=SIZE", Integer, "Execute thread size (Default: 25)") do |i|
    options[:execute_thread] = i
  end

  opts.on("-l", "--log=LOGFILE", "Set log output destination (Default: STDOUT)") do |log|
    options[:log] = log
  end

  opts.on("-d", "--daemonize", "Daemon mode") do
    options[:daemonize] = true
  end

  opts.on(nil, "--pid=PIDFILE", "Set pid file") do |pid|
    options[:pid_path] = pid
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end

opt_parser.parse!

CronoTrigger.load_config(options[:config], options[:env]) if options[:config]

%i(polling_thread polling_interval execute_thread).each do |name|
  CronoTrigger.config[name] = options[name] if options[name]
end

CronoTrigger.config.model_names.concat(ARGV)

se = ServerEngine.create(nil, CronoTrigger::Worker, {
  daemonize: options[:daemonize],
  log: options[:log] || "-",
  log_level: options[:log_level] || "info",
  pid_path: options[:pid_path],
  supervisor: true,
  server_process_name: "crono_trigger[worker]",
  restart_server_process: true,
})
se.run
