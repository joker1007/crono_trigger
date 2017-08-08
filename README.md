# CronoTrigger
[![Gem Version](https://badge.fury.io/rb/crono_trigger.svg)](https://badge.fury.io/rb/crono_trigger)
[![Build Status](https://travis-ci.org/joker1007/crono_trigger.svg?branch=master)](https://travis-ci.org/joker1007/crono_trigger)
[![codecov](https://codecov.io/gh/joker1007/crono_trigger/branch/master/graph/badge.svg)](https://codecov.io/gh/joker1007/crono_trigger)

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

#### Execute `crono_trigger:model` generator.

```
$ rails g crono_trigger:model mail_notification
      create  db/migrate/20170619064928_create_mail_notifications.rb
      create  app/models/mail_notification.rb
      # ...
```

#### Migration sample

```ruby
class CreateMailNotifications < ActiveRecord::Migration
  def change
    create_table :mail_notifications do |t|

      # columns for CronoTrigger::Schedulable
      t.string    :cron
      t.datetime  :next_execute_at
      t.datetime  :last_executed_at
      t.integer   :execute_lock, limit: 8, default: 0, null: false
      t.datetime  :started_at, null: false
      t.datetime  :finished_at
      t.string    :last_error_name
      t.string    :last_error_reason
      t.datetime  :last_error_time
      t.integer   :retry_count, default: 0, null: false


      t.timestamps
    end
    add_index :mail_notifications, [:next_execute_at, :execute_lock, :started_at, :finished_at], name: "crono_trigger_index_on_mail_notifications"
  end
end
```

#### Implement `#execute` method

```ruby
class MailNotification < ActiveRecord::Base
  include CronoTrigger::Schedulable

  self.crono_trigger_options = {
    retry_limit: 5,
    retry_interval: 10,
    exponential_backoff: true,
    execute_lock_timeout: 300,
  }

  # `execute` callback is defined
  # can use `before_execute`, `after_execute`, `around_execute`

  # If execute method raise Exception, worker retry task until reach `retry_limit`
  # If `retry_count` reaches `retry_limit`, task schedule is reset.
  #
  # If record has cron value, reset process set next execution time by cron definition
  # If record has no cron value, reset process clear next execution time
  def execute
    send_mail

    throw :retry # break execution and retry task
    throw :abort # break execution and raise AbortExecution. AbortExecution is not retried
    throw :ok    # break execution and handle task as success
    throw :ok_without_reset    # break execution and handle task as success but without schedule reseting and unlocking
  end
end

# one time schedule
MailNotification.create(next_execute_at: Time.current.since(5.minutes))

# cron schedule
MailNotification.create(cron: "0 12 * * *", started_at: Time.current).activate_schedule!
# or
MailNotification.new(cron: "0 12 * * *", started_at: Time.current).activate_schedule!.save

# if update cron column or timezone column
# update next_execute_at automatically by before_update callback
mail = MailNotification.create(cron: "0 12 * * *", started_at: Time.current).activate_schedule!
mail.next_execute_at # => next 12:00 with Time.zone
mail.update(cron: "0 13 * * *")
mail.next_execute_at # => next 13:00 with Time.zone
mail.update(timezone: "Asia/Tokyo")
mail.next_execute_at # => next 13:00 with Asia/Japan
```

#### Run Worker

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

## Specification

### Columns

|name             |type    |required|rename|description                                                                                                                                                  |
|-----------------|--------|--------|------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
|cron             |string  |no      |no    |Recurring schedule formatted by cron style                                                                                                                   |
|next_execute_at  |datetime|yes     |yes   |Timestamp of next execution. Worker executes task if this column <= now                                                                                      |
|last_executed_at |datetime|no      |yes   |Timestamp of last execution                                                                                                                                  |
|timezone         |datetime|no      |yes   |Timezone name (Parsed by tzinfo)                                                                                                                             |
|execute_lock     |integer |yes     |yes   |Timestamp of fetching record in order to hide record from other transaction during execute lock timeout. <br> when execution complete this column is reset to 0|
|started_at       |datetime|no      |yes   |Timestamp of schedule activated                                                                                                                              |
|finished_at      |datetime|no      |yes   |Timestamp of schedule deactivated                                                                                                                            |
|last_error_name  |string  |no      |no    |Class name of last error                                                                                                                                     |
|last_error_reason|string  |no      |no    |Error message of last error                                                                                                                                  |
|last_error_time  |datetime|no      |no    |Timestamp of last error occured                                                                                                                              |
|retry_count      |integer |no      |no    |Retry count. <br> If execution succeed retry_count is reset to 0                                                                                                  |

You can rename some columns.
ex. `crono_trigger_options[:next_execute_at_column_name] = "next_time"`

## Rollbar integration
This gem has rollbar plugin.
If `crono_trigger/rollbar` is required, Add Rollbar logging process to `CronoTrigger.config.error_handlers`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joker1007/crono_trigger.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
