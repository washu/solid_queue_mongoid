# frozen_string_literal: true

module SolidQueue
  class Job
    module Executable
      extend ActiveSupport::Concern

      included do
        include ConcurrencyControls, Schedulable, Retryable


        has_one :ready_execution,   class_name: "SolidQueue::ReadyExecution",   dependent: :destroy
        has_one :claimed_execution, class_name: "SolidQueue::ClaimedExecution", dependent: :destroy

        after_create :prepare_for_execution

        scope :finished, -> { where(:finished_at.ne => nil) }
        scope :failed,   -> { where(:id.in => SolidQueue::FailedExecution.all.pluck(:job_id)) }
        scope :pending,  -> { where(finished_at: nil) }
      end

      class_methods do
        # Dispatch a collection of jobs, partitioned by schedule and concurrency.
        def prepare_all_for_execution(jobs)
          due, not_yet_due = jobs.partition(&:due?)
          dispatch_all(due) + schedule_all(not_yet_due)
        end

        def dispatch_all(jobs)
          with_concurrency_limits, without_concurrency_limits = jobs.partition(&:concurrency_limited?)

          dispatch_all_at_once(without_concurrency_limits)
          dispatch_all_one_by_one(with_concurrency_limits)

          successfully_dispatched(jobs)
        end

        private

          def dispatch_all_at_once(jobs)
            ReadyExecution.create_all_from_jobs(jobs)
          end

          def dispatch_all_one_by_one(jobs)
            jobs.each(&:dispatch)
          end

          def successfully_dispatched(jobs)
            job_ids = jobs.map(&:id)
            dispatched_and_ready(jobs) + dispatched_and_blocked(jobs)
          end

          def dispatched_and_ready(jobs)
            job_ids = jobs.map(&:id)
            where(:id.in => ReadyExecution.where(:job_id.in => job_ids).pluck(:job_id))
          end

          def dispatched_and_blocked(jobs)
            job_ids = jobs.map(&:id)
            where(:id.in => BlockedExecution.where(:job_id.in => job_ids).pluck(:job_id))
          end
      end

      # status helpers matching SolidQueue runtime expectations
      %w[ ready claimed failed ].each do |status|
        define_method("#{status}?") { public_send("#{status}_execution").present? }
      end

      def prepare_for_execution
        if due?
          dispatch
        else
          schedule
        end
      end

      def dispatch
        if due?
          if acquire_concurrency_lock
            ready
          else
            handle_concurrency_conflict
          end
        else
          schedule
        end
      end

      # Called by ClaimedExecution#release — bypasses the semaphore check.
      def dispatch_bypassing_concurrency_limits
        ready
      end

      def finished!
        if SolidQueue.preserve_finished_jobs?
          update(finished_at: Time.current)
          # Clean up the claimed execution if still present (e.g. called directly
          # outside of ClaimedExecution#finished which does its own destroy!).
          claimed_execution&.destroy
        else
          destroy!
        end
      end

      alias_method :finish, :finished!

      def finished?
        finished_at.present?
      end

      def status
        if finished?
          :finished
        elsif (exec = execution)
          exec.type
        end
      end

      def discard
        execution&.discard
      end

      private

        def ready
          existing = ReadyExecution.where(job_id: id).first
          return existing if existing

          re = ReadyExecution.new(job_id: id)
          re.queue_name = queue_name
          re.priority   = priority
          re.save!
          re
        rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure
          ReadyExecution.where(job_id: id).first
        end

        def execution
          %w[ ready claimed failed ].reduce(nil) do |acc, status|
            acc || public_send("#{status}_execution")
          end
        end
    end
  end
end
