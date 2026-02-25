# frozen_string_literal: true

module SolidQueue
  class RecurringTask < Record
    field :key, type: String
    field :schedule, type: String
    field :command, type: String
    field :class_name, type: String
    field :arguments, type: Hash
    field :queue_name, type: String
    field :priority, type: Integer, default: 0

    index({ key: 1 }, { unique: true })

    validates :key, :schedule, :class_name, :queue_name, presence: true

    def self.load_tasks(tasks_config)
      tasks_config.each do |key, config|
        find_or_initialize_by(key: key).tap do |task|
          task.assign_attributes(
            schedule: config[:schedule],
            command: config[:command],
            class_name: config[:class],
            arguments: config[:args] || {},
            queue_name: config[:queue] || "default",
            priority: config[:priority] || 0
          )
          task.save!
        end
      end
    end

    def to_recurring_execution
      RecurringExecution.find_or_initialize_by(key: key).tap do |execution|
        execution.assign_attributes(
          schedule: schedule,
          command: command,
          class_name: class_name,
          arguments: arguments,
          queue_name: queue_name,
          priority: priority
        )
      end
    end
  end
end
