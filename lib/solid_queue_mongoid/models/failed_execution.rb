# frozen_string_literal: true

module SolidQueue
  class FailedExecution < Execution
    include Dispatching

    field :error, type: Hash # stores exception_class, message, backtrace

    attr_accessor :exception

    before_save :expand_error_details_from_exception, if: :exception

    index({ created_at: 1 })

    class << self
      def retry_all(jobs)
        SolidQueue.instrument(:retry_all, jobs_size: jobs.size) do |payload|
          job_ids = jobs.map(&:id)
          payload[:size] = dispatch_jobs(lock_all_from_jobs_ids(job_ids))
        end
      end

      private

      def lock_all_from_jobs_ids(job_ids)
        where(:job_id.in => job_ids).pluck(:job_id)
      end
    end

    def retry
      SolidQueue.instrument(:retry, job_id: job.id) do
        Mongoid.transaction do
          job.reset_execution_counters
          job.prepare_for_execution
          destroy!
        end
      end
    end

    # Error attribute accessors matching SolidQueue API
    %i[exception_class message backtrace].each do |attribute|
      define_method(attribute) { error&.with_indifferent_access&.[](attribute.to_s) }
    end

    private

    # BSON documents are limited to 16 MB. Reserve a generous budget for the
    # backtrace so a deep stack can never blow the limit.
    BACKTRACE_SIZE_LIMIT = 50_000 # bytes of JSON

    def expand_error_details_from_exception
      return unless exception

      self.error = {
        "exception_class" => exception.class.name,
        "message" => exception.message,
        "backtrace" => truncate_backtrace(exception.backtrace)
      }
    end

    def truncate_backtrace(lines)
      return lines if lines.nil?

      truncated = []
      lines.each do |line|
        truncated << line
        break if truncated.to_json.bytesize > BACKTRACE_SIZE_LIMIT
      end
      # Remove the last line that pushed us over the limit
      truncated.pop if truncated.to_json.bytesize > BACKTRACE_SIZE_LIMIT
      truncated
    end
  end
end
