module CronoTrigger
  module Models
    class Signal < ActiveRecord::Base
      self.table_name = "crono_trigger_signals"

      IGNORE_THRESHOLD = 300

      if ActiveRecord.version >= Gem::Version.new("7.0")
        enum :signal, {TERM: "TERM", USR1: "USR1", CONT: "CONT", TSTP: "TSTP"}
      else
        enum signal: {TERM: "TERM", USR1: "USR1", CONT: "CONT", TSTP: "TSTP"}
      end

      scope :sent_to_me, proc {
        raise "Must set worker_id" unless CronoTrigger.config.worker_id

        where(arel_table[:sent_at].gteq(Time.current - IGNORE_THRESHOLD))
          .where(worker_id: CronoTrigger.config.worker_id)
          .where(received_at: nil)
          .order(:sent_at)
      }

      class << self
        def send_signal(signal, worker_id)
          create!(signal: signal, worker_id: worker_id, sent_at: Time.current)
        end

        def send_term(worker_id)
          send_signal("TERM", worker_id)
        end

        def send_usr1(worker_id)
          send_signal("USR1", worker_id)
        end

        def send_cont(worker_id)
          send_signal("CONT", worker_id)
        end

        def send_tstp(worker_id)
          send_signal("TSTP", worker_id)
        end
      end

      def kill_me(to_supervisor: true)
        if update(received_at: Time.current)
          if to_supervisor && Process.ppid != 1
            Process.kill(signal, Process.ppid)
          else
            Process.kill(signal, Process.pid)
          end
        end
      end
    end
  end
end
