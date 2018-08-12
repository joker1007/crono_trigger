class <%= migration_class_name %> < ActiveRecord::Migration<%= Rails::VERSION::MAJOR >= 5 ? "[#{ActiveRecord::Migration.current_version}]" : "" %>
  def change
    create_table :<%= table_name %><%= respond_to?(:primary_key_type) ? primary_key_type : "" %> do |t|
<% attributes.each do |attribute| -%>
<% if attribute.password_digest? -%>
      t.string :password_digest<%= attribute.inject_options %>
<% elsif attribute.respond_to?(:token?) && attribute.token? -%>
      t.string :<%= attribute.name %><%= attribute.inject_options %>
<% else -%>
      t.<%= attribute.type %> :<%= attribute.name %><%= attribute.inject_options %>
<% end -%>
<% end -%>

      # columns for CronoTrigger::Schedulable
      t.string    :cron
      t.datetime  :next_execute_at
      t.datetime  :last_executed_at
      t.string    :timezone
      t.integer   :execute_lock, limit: 8, default: 0, null: false
      t.string    :locked_by
      t.datetime  :started_at, null: false
      t.datetime  :finished_at
      t.string    :last_error_name
      t.string    :last_error_reason
      t.datetime  :last_error_time
      t.integer   :retry_count, default: 0, null: false

<% if options[:timestamps] %>
      t.timestamps<%= Rails::VERSION::MAJOR >=5 ? " null: false" : "" %>
<% end -%>
    end
<% attributes.select { |attribute| attribute.respond_to?(:token?) && attribute.token? }.each do |attribute| -%>
    add_index :<%= table_name %>, :<%= attribute.index_name %><%= attribute.inject_index_options %>, unique: true
<% end -%>
<% attributes_with_index.each do |attribute| -%>
    add_index :<%= table_name %>, :<%= attribute.index_name %><%= attribute.inject_index_options %>
<% end -%>
    add_index :<%= table_name %>, [:next_execute_at, :execute_lock, :started_at, :finished_at], name: "crono_trigger_index_on_<%= table_name %>"
  end
end
