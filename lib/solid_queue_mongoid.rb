# frozen_string_literal: true

require_relative "solid_queue_mongoid/version"
require "mongoid"
require "active_support/all"

# Load Railtie if in Rails — must happen before SolidQueue loads its AR models
require_relative "solid_queue_mongoid/railtie" if defined?(Rails::Railtie)

module SolidQueueMongoid
  class Error < StandardError; end

  # Configuration
  mattr_accessor :client, :collection_prefix

  @@client            = :default
  @@collection_prefix = "solid_queue_"

  def self.configure
    yield self
  end

  def self.create_indexes
    all_models.each(&:create_indexes)
  end

  def self.remove_indexes
    all_models.each(&:remove_indexes)
  end

  def self.all_models
    [
      SolidQueue::Job,
      SolidQueue::ReadyExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::BlockedExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::FailedExecution,
      SolidQueue::RecurringExecution,
      SolidQueue::Process,
      SolidQueue::Pause,
      SolidQueue::Queue,
      SolidQueue::Semaphore,
      SolidQueue::RecurringTask
      # Queue is now a Mongoid-backed model
    ]
  end
end

# ─── Shim: inject SolidQueue namespace helpers before SolidQueue runtime loads ───
# SolidQueue runtime calls SolidQueue.client, SolidQueue.collection_prefix, etc.
# We also need clear_finished_jobs_after, process_alive_threshold, preserve_finished_jobs?
# — if SolidQueue gem is present those will already exist; if not we stub sensible defaults.
module SolidQueue
  def self.client
    SolidQueueMongoid.client
  end

  def self.collection_prefix
    SolidQueueMongoid.collection_prefix
  end

  # These defaults mirror SolidQueue::Configuration defaults and are only
  # active when solid_queue itself is not loaded.
  unless respond_to?(:clear_finished_jobs_after)
    def self.clear_finished_jobs_after
      1.day
    end
  end

  unless respond_to?(:process_alive_threshold)
    def self.process_alive_threshold
      5.minutes
    end
  end

  unless respond_to?(:preserve_finished_jobs?)
    def self.preserve_finished_jobs?
      true
    end
  end

  # Stub for SolidQueue.instrument — the real implementation in solid_queue
  # uses ActiveSupport::Notifications. When solid_queue is loaded it already
  # defines this, so we only add it when missing.
  unless respond_to?(:instrument)
    def self.instrument(event, payload = {}, &block)
      return yield(payload) if block_given?
    end
  end
end

# ─── Load order ───────────────────────────────────────────────────────────────
# 1. Base record class
require_relative "solid_queue_mongoid/models/record"

# 2. Pre-declare all classes (avoids superclass mismatch)
require_relative "solid_queue_mongoid/models/classes"

# 3. Execution concerns
require_relative "solid_queue_mongoid/models/execution/job_attributes"
require_relative "solid_queue_mongoid/models/execution/dispatching"

# 4. Base execution
require_relative "solid_queue_mongoid/models/execution"

# 5. Job concerns (order matters — ConcurrencyControls/Schedulable/Retryable
#    must exist before Executable includes them)
require_relative "solid_queue_mongoid/models/job/clearable"
require_relative "solid_queue_mongoid/models/job/recurrable"
require_relative "solid_queue_mongoid/models/job/schedulable"
require_relative "solid_queue_mongoid/models/job/retryable"
require_relative "solid_queue_mongoid/models/job/concurrency_controls"
require_relative "solid_queue_mongoid/models/job/executable"

# 6. Concrete models
require_relative "solid_queue_mongoid/models/job"
require_relative "solid_queue_mongoid/models/semaphore"          # needed by BlockedExecution
require_relative "solid_queue_mongoid/models/ready_execution"
require_relative "solid_queue_mongoid/models/claimed_execution"
require_relative "solid_queue_mongoid/models/blocked_execution"
require_relative "solid_queue_mongoid/models/scheduled_execution"
require_relative "solid_queue_mongoid/models/failed_execution"
require_relative "solid_queue_mongoid/models/recurring_task/arguments"
require_relative "solid_queue_mongoid/models/recurring_task"
require_relative "solid_queue_mongoid/models/recurring_execution"
require_relative "solid_queue_mongoid/models/process/executor"
require_relative "solid_queue_mongoid/models/process/prunable"
require_relative "solid_queue_mongoid/models/process"
require_relative "solid_queue_mongoid/models/pause"
require_relative "solid_queue_mongoid/models/queue"
require_relative "solid_queue_mongoid/models/queue_selector"
