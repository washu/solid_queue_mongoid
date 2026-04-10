# frozen_string_literal: true

module SolidQueue
  class ScheduledExecution < Execution
    include Dispatching

    assumes_attributes_from_job :scheduled_at

    field :scheduled_at, type: Time

    scope :due,        -> { where(:scheduled_at.lte => Time.current) }
    scope :due_order,  -> { order_by(scheduled_at: :asc, priority: :asc, job_id: :asc) }
    scope :next_batch, ->(batch_size) { due.due_order.limit(batch_size) }

    index({ scheduled_at: 1, priority: 1 })

    class << self
      def dispatch_next_batch(batch_size)
        Mongoid.transaction do
          SolidQueue.instrument(:dispatch_scheduled, batch_size: batch_size) do |payload|
            job_ids = next_batch(batch_size).pluck(:job_id)
            if job_ids.empty?
              payload[:size] = 0
            else
              payload[:size] = dispatch_jobs(job_ids)
            end
            payload[:size]
          end
        end
      end

      alias_method :dispatch_due_batch, :dispatch_next_batch
    end

    # Instance method: dispatch this single execution if the job is due now.
    # Mirrors the AR behaviour used in tests.
    def dispatch
      return unless job.due?

      self.class.dispatch_jobs([ job_id ])
    end
  end
end

