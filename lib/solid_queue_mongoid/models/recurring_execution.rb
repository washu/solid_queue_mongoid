# frozen_string_literal: true

module SolidQueue
  class RecurringExecution < Record
    field :key, type: String
    field :schedule, type: String
    field :command, type: String
    field :class_name, type: String
    field :arguments, type: Hash
    field :queue_name, type: String
    field :priority, type: Integer, default: 0
    field :last_run_at, type: Time
    field :next_run_at, type: Time

    has_many :jobs, class_name: "SolidQueue::Job", dependent: :nullify

    index({ key: 1 }, { unique: true })
    index({ next_run_at: 1 })

    validates :key, :schedule, :class_name, :queue_name, presence: true

    def self.dispatch_due_tasks
      where(:next_run_at.lte => Time.current).each(&:dispatch)
    end

    def dispatch
      job = Job.create!(
        recurring_execution: self,
        queue_name: queue_name,
        class_name: class_name,
        arguments: arguments || {},
        priority: priority
      )

      job.dispatch

      update!(
        last_run_at: Time.current,
        next_run_at: calculate_next_run_at
      )
    end

    def calculate_next_run_at
      # This would use a cron parser in production
      # For now, simple implementation
      Time.current + 1.hour
    end
  end
end
