# frozen_string_literal: true

require "fugit"

module SolidQueue
  class RecurringTask < Record
    field :key, type: String
    field :schedule, type: String
    field :command, type: String
    field :class_name, type: String
    field :arguments, type: Array, default: []
    field :queue_name, type: String
    field :priority, type: Integer, default: 0
    field :description, type: String
    field :static, type: Boolean, default: false

    index({ key: 1 }, { unique: true })

    scope :static, -> { where(static: true) }
    scope :dynamic, -> { where(static: false) }

    validates :key, presence: true

    validate :ensure_schedule_supported
    validate :ensure_command_or_class_present
    validate :ensure_existing_job_class

    has_many :recurring_executions, foreign_key: :task_key, primary_key: :key,
             class_name: "SolidQueue::RecurringExecution"

    mattr_accessor :default_job_class
    self.default_job_class = "SolidQueue::RecurringJob".safe_constantize

    class << self
      def wrap(args)
        args.is_a?(self) ? args : from_configuration(args.first, **args.second)
      end

      def from_configuration(key, **options)
        new(
          key: key,
          class_name: options[:class],
          command: options[:command],
          arguments: Array(options[:args]),
          schedule: options[:schedule],
          queue_name: options[:queue].presence,
          priority: options[:priority].presence,
          description: options[:description],
          static: options.fetch(:static, true)
        )
      end

      def create_dynamic_task(key, **options)
        from_configuration(key, **options.merge(static: false)).save!
      end

      def delete_dynamic_task(key)
        RecurringTask.dynamic.find_by!(key: key).destroy
      end

      # Upsert all static tasks; used by Scheduler::RecurringSchedule#persist_tasks.
      def create_or_update_all(tasks)
        tasks.each do |task|
          existing = where(key: task.key).first
          if existing
            existing.update!(task.attributes_for_upsert)
          else
            create!(task.attributes_for_upsert.merge(key: task.key))
          end
        end
      end
    end

    def delay_from_now
      [(next_time - Time.current).to_f, 0.1].max
    end

    def next_time
      parsed_schedule.next_time.utc
    end

    def previous_time
      parsed_schedule.previous_time.utc
    end

    def last_enqueued_time
      recurring_executions.maximum(:run_at)
    end

    def enqueue(at:)
      SolidQueue.instrument(:enqueue_recurring_task, task: key, at: at) do |payload|
        active_job = if using_solid_queue_adapter?
                       enqueue_and_record(run_at: at)
                     else
                       payload[:other_adapter] = true
                       perform_later.tap do |job|
                         unless job.successfully_enqueued?
                           payload[:enqueue_error] = job.enqueue_error&.message
                         end
                       end
                     end

        active_job.tap do |enqueued_job|
          payload[:active_job_id] = enqueued_job.job_id if enqueued_job
        end
      rescue RecurringExecution::AlreadyRecorded
        payload[:skipped] = true
        false
      rescue Job::EnqueueError => error
        payload[:enqueue_error] = error.message
        false
      end
    end

    def to_s
      "#{class_name}.perform_later(#{arguments.map(&:inspect).join(",")}) [ #{parsed_schedule.original} ]"
    end

    def attributes_for_upsert
      attrs = attributes.except("_id", "id", "created_at", "updated_at")
      attrs.delete("key")
      attrs
    end

    private

    def ensure_schedule_supported
      unless parsed_schedule.instance_of?(Fugit::Cron)
        errors.add :schedule, :unsupported, message: "is not a supported recurring schedule"
      end
    rescue ArgumentError => error
      message = if error.message.include?("multiple crons")
                  "generates multiple cron schedules. Please use separate recurring tasks for each schedule, " \
                    "or use explicit cron syntax (e.g., '40 0,15 * * *' for multiple times with the same minutes)"
                else
                  error.message
                end
      errors.add :schedule, :unsupported, message: message
    end

    def ensure_command_or_class_present
      unless command.present? || class_name.present?
        errors.add :base, :command_and_class_blank, message: "either command or class must be present"
      end
    end

    def ensure_existing_job_class
      if class_name.present? && job_class.nil?
        errors.add :class_name, :undefined, message: "doesn't correspond to an existing class"
      end
    end

    def using_solid_queue_adapter?
      job_class.respond_to?(:queue_adapter_name) &&
        job_class.queue_adapter_name.inquiry.solid_queue?
    end

    def enqueue_and_record(run_at:)
      RecurringExecution.record(key, run_at) do
        job_class.new(*arguments_with_kwargs).set(enqueue_options).tap do |active_job|
          active_job.run_callbacks(:enqueue) do
            Job.enqueue(active_job)
          end
        end
      end
    end

    def perform_later
      job_class.new(*arguments_with_kwargs).tap do |active_job|
        active_job.enqueue(enqueue_options)
      end
    end

    def arguments_with_kwargs
      if class_name.nil?
        command
      elsif arguments.last.is_a?(Hash)
        arguments[0...-1] + [Hash.ruby2_keywords_hash(arguments.last)]
      else
        arguments
      end
    end

    def parsed_schedule
      @parsed_schedule ||= Fugit.parse(schedule, multi: :fail)
    end

    def job_class
      @job_class ||= class_name.present? ? class_name.safe_constantize : self.class.default_job_class
    end

    def enqueue_options
      { queue: queue_name, priority: priority }.compact
    end
  end
end
