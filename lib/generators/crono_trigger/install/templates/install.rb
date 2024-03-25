class CreateCronoTriggerSystemTables < ActiveRecord::Migration<%= Rails::VERSION::MAJOR >= 5 ? "[#{ActiveRecord::Migration.current_version}]" : "" %>
  def change
    create_table :crono_trigger_workers, id: :string, primary_key: :worker_id do |t|
      t.integer  :max_thread_size, null: false
      t.integer  :current_executing_size, null: false
      t.integer  :current_queue_size, null: false
      t.string   :executor_status, null: false
      t.text   :polling_model_names, null: false
      t.datetime :last_heartbeated_at, null: false
    end

    add_index :crono_trigger_workers, :last_heartbeated_at

    create_table :crono_trigger_signals do |t|
      t.string :worker_id, null: false
      t.string :signal, null: false
      t.datetime :sent_at, null: false
      t.datetime :received_at
    end

    add_index :crono_trigger_signals, [:sent_at, :worker_id]

    create_table :crono_trigger_executions do |t|
      t.integer :schedule_id, null: false
      t.string :schedule_type, null: false
      t.string :worker_id, null: false
      t.datetime :executed_at, null: false
      t.datetime :completed_at
      t.string :status, null: false, default: "executing"
      t.string :error_name
      t.string :error_reason
    end

    add_index :crono_trigger_executions, [:schedule_type, :schedule_id, :executed_at], name: "index_crono_trigger_executions_on_schtype_schid_executed_at"
    add_index :crono_trigger_executions, [:schedule_type, :executed_at]
    add_index :crono_trigger_executions, [:executed_at]
  end
end
