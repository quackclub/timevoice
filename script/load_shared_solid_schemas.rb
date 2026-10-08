# When cache, queue and cable share the primary database (DATABASE__SHARED=true),
# `db:prepare` sees an existing database and skips their schema files. Load any that are missing.
{ cache: "solid_cache_entries", queue: "solid_queue_jobs", cable: "solid_cable_messages" }.each do |name, table|
  config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name.to_s)
  next unless config

  ActiveRecord::Base.establish_connection(config)
  next if ActiveRecord::Base.connection.table_exists?(table)

  puts "Loading #{name} schema into shared database"
  load Rails.root.join("db/#{name}_schema.rb")
ensure
  ActiveRecord::Base.establish_connection(:primary)
end
