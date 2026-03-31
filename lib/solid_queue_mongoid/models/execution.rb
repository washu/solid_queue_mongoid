# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    include JobAttributes

    scope :ordered, -> { order_by(priority: :asc, job_id: :asc) }

    class << self
      def type
        model_name.element.sub("_execution", "").to_sym
      end

      def create_all_from_jobs(jobs)
        jobs.each do |job|
          attrs = attributes_from_job(job).merge(job_id: job.id)
          create_or_find_by!(attrs)
        end
      end

      def discard_all_in_batches(batch_size: 500)
        pending = count
        discarded = 0

        loop do
          job_ids = limit(batch_size).order_by(job_id: :asc).pluck(:job_id)
          break if job_ids.empty?

          discarded = Job.where(:id.in => job_ids).delete_all
          where(:job_id.in => job_ids).delete_all
          pending -= discarded

          break if pending <= 0 || discarded == 0
        end
      end

      def discard_all_from_jobs(jobs)
        job_ids = jobs.map(&:id)
        discard_jobs(job_ids)
        where(:job_id.in => job_ids).delete_all
      end

      private

        def discard_jobs(job_ids)
          Job.where(:id.in => job_ids).delete_all
        end
    end

    def type
      self.class.type
    end

    def discard
      SolidQueue.instrument(:discard, job_id: job_id, status: type) do
        job.destroy
        destroy
      end
    end
  end
end
