# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    module JobAttributes
      extend ActiveSupport::Concern

      included do
        class_attribute :assumable_attributes_from_job, instance_accessor: false,
                        default: %i[ queue_name priority ]

        field :queue_name, type: String
        field :priority,   type: Integer, default: 0
        field :job_id,     type: BSON::ObjectId

        index({ queue_name: 1, priority: 1, created_at: 1 })

        belongs_to :job, class_name: "SolidQueue::Job", optional: false

        # NOTE: uniqueness is enforced by the MongoDB unique index on job_id
        # (added per-subclass by assumes_attributes_from_job), not by a Rails
        # validator.  Rails-level uniqueness checks are susceptible to stale
        # QueryCache reads and are redundant given the DB constraint.
      end

      class_methods do
        # Subclasses call this to declare which additional job attributes they mirror.
        # It registers a before_create callback that copies those attributes from the
        # associated job at creation time.
        # Also ensures a unique index on job_id for the calling class's collection.
        def assumes_attributes_from_job(*attribute_names)
          self.assumable_attributes_from_job = (assumable_attributes_from_job + attribute_names).uniq
          before_create :assume_attributes_from_job
          # Add unique job_id index to THIS subclass's collection (not parent's)
          unless index_specifications.any? { |s| s.spec.keys.map(&:to_s) == ["job_id"] && s.options[:unique] }
            index({ job_id: 1 }, { unique: true })
          end
        end

        def attributes_from_job(job)
          job.attributes.symbolize_keys.slice(*assumable_attributes_from_job)
        end
      end

      private

        def assume_attributes_from_job
          self.class.assumable_attributes_from_job.each do |attr|
            send("#{attr}=", job.send(attr)) if job.respond_to?(attr)
          end
        end
    end
  end
end
