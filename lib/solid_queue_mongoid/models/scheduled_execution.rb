# frozen_string_literal: true

module SolidQueue
  class ScheduledExecution < Execution
    field :scheduled_at, type: Time

    index({ scheduled_at: 1 })

    def self.dispatch_due_batch(batch_size)
      where(:scheduled_at.lte => Time.current)
        .limit(batch_size)
        .order_by(scheduled_at: :asc)
        .each(&:dispatch)
    end

    def dispatch
      return if scheduled_at > Time.current

      destroy
      job.create_ready_execution!
    end
  end
end
