# frozen_string_literal: true

module SolidQueueMongoid
  class Railtie < Rails::Railtie
    rake_tasks do
      load "tasks/solid_queue_mongoid.rake"
    end

    # Prevent SolidQueue's AR models from loading via Zeitwerk.
    #
    # Must run BEFORE :set_eager_load_paths (which freezes eager_load_paths)
    # and before SolidQueue's own Railtie initializer adds its app/ path.
    initializer "solid_queue_mongoid.shim",
                before: :set_eager_load_paths do |app|
      next unless defined?(SolidQueue::Engine)

      sq_app_path = SolidQueue::Engine.root.join("app").to_s

      # Tell Zeitwerk to ignore SolidQueue's app/ tree so it never autoloads
      # the AR model files.
      Rails.autoloaders.each do |loader|
        loader.ignore(sq_app_path) if loader.respond_to?(:ignore)
      end

      # Remove from eager_load_paths before Rails freezes it.
      app.config.eager_load_paths.delete_if { |p| p.start_with?(sq_app_path) }
    end
  end
end
