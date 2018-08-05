class CreateCronoTriggerSystemTables < ActiveRecord::Migration<%= Rails::VERSION::MAJOR >= 5 ? "[#{ActiveRecord::Migration.current_version}]" : "" %>
  def change
    create_table :crono_trigger_workers, id: :string, primary_key: :worker_id do |t|
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
  end
end
