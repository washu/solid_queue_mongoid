# frozen_string_literal: true

module SolidQueue
  class FailedExecution < Execution
    field :error_class, type: String
    field :error_message, type: String
    field :backtrace, type: Array
    field :failed_at, type: Time

    index({ failed_at: 1 })

    def self.create_from_job!(job, error)
      create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        concurrency_key: job.concurrency_key,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace,
        failed_at: Time.current
      )
    end

    def retry
      destroy
      job.create_ready_execution!
    end

    def discard
      destroy
      job.update(finished_at: Time.current)
    end
  end
end
