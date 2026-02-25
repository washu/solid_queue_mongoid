# frozen_string_literal: true

module SolidQueueMongoid
  class Railtie < Rails::Railtie
    rake_tasks do
      load "tasks/solid_queue_mongoid.rake"
    end
  end
end
