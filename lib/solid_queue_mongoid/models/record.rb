# frozen_string_literal: true

module SolidQueue
  class Record
    include Mongoid::Document
    include Mongoid::Timestamps

    # Dynamic collection naming with prefix
    def self.inherited(subclass)
      super

      # Set collection name with prefix
      collection_name = subclass.name.demodulize.tableize
      prefixed_name = "#{SolidQueue.collection_prefix}#{collection_name}"

      # Store collection name but don't set client yet
      # Client will be determined at query time
      subclass.store_in collection: prefixed_name
    end

    # Override key Mongoid query methods to ensure correct client usage
    class << self
      # Only alias methods that exist on Mongoid::Document
      [:where, :find, :find_by, :find_or_create_by, :find_or_initialize_by,
       :all, :first, :last, :create, :create!, :exists?, :count,
       :pluck, :limit, :skip, :order_by, :only, :without,
       :delete_all, :destroy_all].each do |method_name|

        original_method = :"original_#{method_name}"

        # Only alias if method exists (will exist after Mongoid::Document is included)
        next unless method_defined?(method_name) || respond_to?(method_name)

        # Alias the original method
        alias_method original_method, method_name

        # Define wrapper that uses correct client
        define_method(method_name) do |*args, &block|
          with(client: SolidQueue.client) do
            __send__(original_method, *args, &block)
          end
        end
      end
    end
  end
end
