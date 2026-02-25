# frozen_string_literal: true

require_relative "solid_queue_mongoid/version"
require "mongoid"

# Don't load solid_queue gem - we replace its models entirely
# require "solid_queue"

# Load Railtie if in Rails
require_relative "solid_queue_mongoid/railtie" if defined?(Rails::Railtie)

module SolidQueueMongoid
  class Error < StandardError; end

  # Configuration
  mattr_accessor :client, :collection_prefix

  @@client = :default # Use Mongoid default client
  @@collection_prefix = "solid_queue_"

  def self.configure
    yield self
  end

  # Create indexes for all SolidQueue models
  def self.create_indexes
    models = [
      SolidQueue::Job,
      SolidQueue::ReadyExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::BlockedExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::FailedExecution,
      SolidQueue::RecurringExecution,
      SolidQueue::Process,
      SolidQueue::Pause,
      SolidQueue::Semaphore,
      SolidQueue::RecurringTask,
      SolidQueue::Queue
    ]

    models.each do |model|
      #puts "Creating indexes for #{model.name}..."
      model.create_indexes
    end

    #puts "All indexes created successfully!"
  end

  # Remove indexes for all SolidQueue models
  def self.remove_indexes
    models = [
      SolidQueue::Job,
      SolidQueue::ReadyExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::BlockedExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::FailedExecution,
      SolidQueue::RecurringExecution,
      SolidQueue::Process,
      SolidQueue::Pause,
      SolidQueue::Semaphore,
      SolidQueue::RecurringTask,
      SolidQueue::Queue
    ]

    models.each do |model|
      #puts "Removing indexes for #{model.name}..."
      model.remove_indexes
    end

    #puts "All indexes removed successfully!"
  end
end

# Extend SolidQueue module to add configuration
module SolidQueue
  def self.client
    SolidQueueMongoid.client
  end

  def self.collection_prefix
    SolidQueueMongoid.collection_prefix
  end
end

# Load all Mongoid models to override SolidQueue's ActiveRecord models
require_relative "solid_queue_mongoid/models/record"
# Pre-declare all model classes to avoid superclass mismatch errors
require_relative "solid_queue_mongoid/models/classes"
# Now load execution concerns and reopen the class
require_relative "solid_queue_mongoid/models/execution/job_attributes"
require_relative "solid_queue_mongoid/models/execution/dispatching"
require_relative "solid_queue_mongoid/models/execution"
# Load job concerns and reopen the class
require_relative "solid_queue_mongoid/models/job/clearable"
require_relative "solid_queue_mongoid/models/job/recurrable"
require_relative "solid_queue_mongoid/models/job/schedulable"
require_relative "solid_queue_mongoid/models/job/retryable"
require_relative "solid_queue_mongoid/models/job/concurrency_controls"
require_relative "solid_queue_mongoid/models/job/executable"
require_relative "solid_queue_mongoid/models/job"
require_relative "solid_queue_mongoid/models/ready_execution"
require_relative "solid_queue_mongoid/models/claimed_execution"
require_relative "solid_queue_mongoid/models/blocked_execution"
require_relative "solid_queue_mongoid/models/scheduled_execution"
require_relative "solid_queue_mongoid/models/failed_execution"
require_relative "solid_queue_mongoid/models/recurring_execution"
require_relative "solid_queue_mongoid/models/process"
require_relative "solid_queue_mongoid/models/pause"
require_relative "solid_queue_mongoid/models/semaphore"
require_relative "solid_queue_mongoid/models/recurring_task"
require_relative "solid_queue_mongoid/models/queue"
