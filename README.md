# SolidQueueMongoid

[![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)

A MongoDB/Mongoid adapter for [SolidQueue](https://github.com/basecamp/solid_queue) that allows you to use MongoDB as the backend instead of ActiveRecord/PostgreSQL/MySQL.

This gem provides a drop-in replacement for SolidQueue's ActiveRecord models, using Mongoid documents instead. All SolidQueue features are supported including job scheduling, concurrency controls, recurring tasks, and more.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'solid_queue_mongoid'
```

And then execute:

```bash
bundle install
```

## How It Works

`solid_queue_mongoid` defines its Mongoid models in the `SolidQueue::` namespace and then requires `solid_queue` for you. This means you only need one gem in your Gemfile — `solid_queue` is pulled in automatically as a dependency.

In Rails, the gem's Railtie runs before Rails freezes `eager_load_paths` and tells Zeitwerk to ignore SolidQueue's `app/models` directory, so the ActiveRecord model files are never autoloaded.

No special require ordering is needed in your application.

## Configuration

### 1. Configure Mongoid

First, ensure you have Mongoid configured in your application. Create or update `config/mongoid.yml`:

```yaml
development:
  clients:
    default:
      database: my_app_development
      hosts:
        - localhost:27017
```

### 2. Configure SolidQueueMongoid

Create an initializer at `config/initializers/solid_queue_mongoid.rb`:

```ruby
# frozen_string_literal: true

SolidQueueMongoid.configure do |config|
  # Optional: Specify which Mongoid client to use for SolidQueue collections
  # Default is :default
  config.client = :default  # or :secondary, :solid_queue, etc.

  # Optional: Set a collection prefix to avoid conflicts with existing collections
  # Default is "solid_queue_"
  config.collection_prefix = "solid_queue_"
end
```

#### Using a Separate MongoDB Client

If you want to store SolidQueue data in a separate MongoDB database, configure a separate client in `config/mongoid.yml`:

```yaml
development:
  clients:
    default:
      database: my_app_development
      hosts:
        - localhost:27017
    solid_queue:
      database: my_app_jobs
      hosts:
        - localhost:27017
```

Then configure SolidQueueMongoid to use it:

```ruby
SolidQueueMongoid.configure do |config|
  config.client = :solid_queue
  config.collection_prefix = "solid_queue_"
end
```

### 3. Create Indexes

After configuration, create the necessary MongoDB indexes:

```bash
# Using rake task (recommended)
bundle exec rake solid_queue_mongoid:create_indexes

# Or in Ruby/Rails console
SolidQueueMongoid.create_indexes
```

### How Client Configuration Works

All SolidQueue models automatically use the configured Mongoid client for all queries and operations. The gem overrides Mongoid's query methods to ensure:

- All queries (`where`, `find`, `create`, etc.) use the configured client
- Cross-model associations work correctly within the same client
- Index creation happens on the correct database
- No manual `with(client:)` calls are needed in your code

This means you can safely use multiple MongoDB databases without any special handling - just configure the client and everything works automatically.

### Collection Naming

With the default `collection_prefix` of `"solid_queue_"`, your collections will be named:

- `solid_queue_jobs`
- `solid_queue_ready_executions`
- `solid_queue_claimed_executions`
- `solid_queue_blocked_executions`
- `solid_queue_scheduled_executions`
- `solid_queue_failed_executions`
- `solid_queue_recurring_executions`
- `solid_queue_processes`
- `solid_queue_pauses`
- `solid_queue_semaphores`
- `solid_queue_recurring_tasks`

This prefix ensures that SolidQueue collections won't conflict with any existing collections in your database.

To see all collection names:

```bash
bundle exec rake solid_queue_mongoid:show_collections
```

## Usage

### 4. Configure the ActiveJob Adapter

In `config/application.rb` (or the appropriate environment file):

```ruby
config.active_job.queue_adapter = :solid_queue
```

### Enqueuing Jobs

Once configured, use SolidQueue exactly as you would with ActiveRecord:

```ruby
# In your ActiveJob
class MyJob < ApplicationJob
  queue_as :default

  def perform(*args)
    # Your job logic
  end
end

# Enqueue jobs
MyJob.perform_later(arg1, arg2)

# Schedule jobs
MyJob.set(wait: 1.hour).perform_later(arg1, arg2)
MyJob.set(wait_until: Date.tomorrow.noon).perform_later(arg1, arg2)
```

### Configuration in Rails

Configure SolidQueue in `config/queue.yml` or through `config.solid_queue` in your Rails configuration:

```yaml
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 2
      polling_interval: 0.1
```

## Rake Tasks

The gem provides several Rake tasks for managing indexes:

```bash
# Create all indexes
bundle exec rake solid_queue_mongoid:create_indexes

# Remove all indexes
bundle exec rake solid_queue_mongoid:remove_indexes

# Show collection names and configuration
bundle exec rake solid_queue_mongoid:show_collections
```

## Index Management

Unlike ActiveRecord migrations, MongoDB uses indexes that can be created on-demand. The gem provides a convenient way to manage these indexes similar to `db:migrate`:

### Creating Indexes

Always run this after:
- Initial installation
- Upgrading the gem
- Changing configuration

```bash
bundle exec rake solid_queue_mongoid:create_indexes
```

### In Production

Add index creation to your deployment process:

```ruby
# In a Rails initializer or deployment script
if Rails.env.production?
  SolidQueueMongoid.create_indexes
end
```

Or use the Rake task in your deployment pipeline:

```bash
bundle exec rake solid_queue_mongoid:create_indexes
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/salsalabs/solid_queue_mongoid. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/salsalabs/solid_queue_mongoid/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SolidQueueMongoid project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/salsalabs/solid_queue_mongoid/blob/main/CODE_OF_CONDUCT.md).
