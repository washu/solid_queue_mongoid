# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
  end
end

# Railtie integration spec has its own boot path — don't load it via this helper.
# Run it directly: bundle exec rspec spec/integration/railtie_spec.rb

require "active_support/all"
require "active_job"
require "rails"
require "mongoid"
require "solid_queue_mongoid"

# ---------------------------------------------------------------------------
# MongoDB bootstrap helpers
# ---------------------------------------------------------------------------

def ensure_mongodb_running
  return if ENV["CI"]

  mongodb_host = ENV.fetch("MONGODB_HOST", "localhost:27017")
  if mongodb_running?(mongodb_host)
    puts "MongoDB already running at #{mongodb_host}"
    return
  end

  puts "MongoDB not detected at #{mongodb_host}, starting Docker container..."
  start_mongodb_container
end

def mongodb_running?(host)
  require "socket"
  hostname, port = host.split(":")
  Socket.tcp(hostname, port.to_i, connect_timeout: 2) { true }
rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
  false
end

def wait_for_port(host, timeout: 180)
  hostname, port = host.split(":")
  deadline = Time.now + timeout
  loop do
    Socket.tcp(hostname, port.to_i, connect_timeout: 2) { return true }
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
    raise "MongoDB port not reachable at #{host} after #{timeout}s" if Time.now > deadline

    sleep 2
  end
end

def start_mongodb_container
  system("docker rm -f solid_queue_test_mongo 2>/dev/null; true")
  sleep 1

  system(
    "docker run -d --name solid_queue_test_mongo -p 27017:27017 mongo:8 --replSet rs0",
    out: File::NULL, err: File::NULL
  )

  puts "Waiting for MongoDB port to open..."
  wait_for_port("localhost:27017", timeout: 180)
  sleep 2

  puts "Initialising replica set..."
  init_config = '{_id: "rs0", members: [{_id: 0, host: "localhost:27017"}]}'
  system("docker exec solid_queue_test_mongo mongosh --eval 'rs.initiate(#{init_config})'",
         out: File::NULL, err: File::NULL)

  deadline = Time.now + 60
  loop do
    state = `docker exec solid_queue_test_mongo mongosh --quiet --eval 'rs.status().myState' 2>/dev/null`.strip
    break if state == "1"

    raise "Replica set primary not elected within 60s" if Time.now > deadline

    sleep 2
  end

  puts "MongoDB replica set ready."
end

ensure_mongodb_running

# Minimal stub used by recurring_task specs that reference a job class by name.
class MyJob; end

# ---------------------------------------------------------------------------
# RSpec configuration
# ---------------------------------------------------------------------------

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    Mongoid.configure do |mongoid_config|
      mongoid_config.clients.default = {
        hosts: [ENV.fetch("MONGODB_HOST", "localhost:27017")],
        database: "solid_queue_test"
      }
    end

    puts "Creating indexes for SolidQueue models..."
    SolidQueueMongoid.create_indexes
    puts "Indexes created successfully!"
  end

  config.before(:each) do
    Mongoid.purge!
    SolidQueueMongoid.create_indexes
  end

  config.after(:each) do
    # no-op: indexes are created in before(:each)
  end

  config.after(:suite) do
    Mongoid.purge!

    unless ENV["CI"] || ENV["KEEP_MONGO"]
      system("docker stop solid_queue_test_mongo", out: File::NULL, err: File::NULL)
      system("docker rm   solid_queue_test_mongo", out: File::NULL, err: File::NULL)
    end
  end
end
