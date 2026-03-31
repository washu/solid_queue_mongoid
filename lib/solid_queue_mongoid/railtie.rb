# frozen_string_literal: true

module SolidQueueMongoid
  class Railtie < Rails::Railtie
    rake_tasks do
      load "tasks/solid_queue_mongoid.rake"
    end

    # Ensure our Mongoid models are loaded and win over SolidQueue's AR models.
    # We hook into :before_initialize so we run before SolidQueue's own Railtie,
    # and before Rails eager-loading sweeps app/models.
    initializer "solid_queue_mongoid.shim", before: :load_config_initializers do
      # Prevent SolidQueue's app/models from being added to the autoload/eager paths.
      # SolidQueue registers its app/ path via its own Railtie; we remove it after
      # it's added so our Mongoid classes remain the authoritative definitions.
      ActiveSupport.on_load(:after_initialize) do
        if defined?(SolidQueue::Engine)
          sq_app_path = SolidQueue::Engine.root.join("app").to_s

          Rails.autoloaders.each do |loader|
            loader.ignore(sq_app_path) if loader.respond_to?(:ignore)
          end

          # Also remove from eager load paths to prevent AR model eager-loading
          Rails.application.config.eager_load_paths.delete_if { |p| p.start_with?(sq_app_path) }
        end
      end
    end
  end
end
