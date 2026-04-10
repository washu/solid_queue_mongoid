# frozen_string_literal: true

require "active_job/serializers"
require "active_job/arguments"

module SolidQueue
  class RecurringTask
    # Serializer for recurring task arguments — stores as an ActiveJob-serialized
    # JSON array in MongoDB. Matches solid_queue 1.3.2 RecurringTask::Arguments exactly.
    module Arguments
      class << self
        # Called when writing to MongoDB: serialize ActiveJob arguments to an Array.
        def mongoize(data)
          data.nil? ? [] : ActiveJob::Arguments.serialize(Array(data))
        end

        # Called when reading from MongoDB: deserialize back to Ruby objects.
        def demongoize(data)
          data.nil? ? [] : ActiveJob::Arguments.deserialize(Array(data))
        end

        # Called for query conditions.
        def evolve(data)
          mongoize(data)
        end
      end
    end
  end
end

