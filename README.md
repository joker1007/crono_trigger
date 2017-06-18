# CronoTrigger

Asynchronous Job Scheduler for Rails.

The purpose of this gem is to integrate job schedule into Service Domain.

Because of it, this gem uses ActiveRecord model as definition of job schedule.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'crono_trigger'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install crono_trigger

## Usage

Execute `schedule_model` generator.

```
TODO: Implement generator
```

Implement `#execute` method.

```ruby
class MailNotification < ActiveRecord::Base
  include CronoTrigger::Schedulable

  self.crono_trigger_options = {
    retry_limit: 5,
    retry_interval: 10,
    exponential_backoff: true,
    execute_lock_timeout: 300,
  }

  def execute
    send_mail
  end
end
```

Run Worker.

```
$ crono_trigger MailNotification
```

```
$ crono_trigger --help
Usage: crono_trigger [options] MODEL [MODEL..]
    -f, --config-file=CONFIG         Config file (ex. ./crono_trigger.rb)
    -e, --envornment=ENV             Set environment name (ex. development, production)
    -p, --polling-thread=SIZE        Polling thread size (Default: 1)
    -i, --polling-interval=SECOND    Polling interval seconds (Default: 5)
    -c, --concurrency=SIZE           Execute thread size (Default: 25)
    -l, --log=LOGFILE                Set log output destination (Default: STDOUT or ./crono_trigger.log if daemonize is true)
        --log-level=LEVEL            Set log level (Default: info)
    -d, --daemonize                  Daemon mode
        --pid=PIDFILE                Set pid file
    -h, --help                       Prints this help
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joker1007/crono_trigger.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

