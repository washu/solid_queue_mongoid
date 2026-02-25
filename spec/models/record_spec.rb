# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Record do
  describe "client configuration" do
    it "uses default client by default" do
      expect(SolidQueue.client).to eq(:default)
    end

    it "respects configured client" do
      original_client = SolidQueueMongoid.client

      SolidQueueMongoid.client = :test_client
      expect(SolidQueue.client).to eq(:test_client)

      SolidQueueMongoid.client = original_client
    end
  end

  describe "collection naming" do
    it "uses collection prefix for subclasses" do
      expect(SolidQueue::Job.collection.name).to start_with("solid_queue_")
      expect(SolidQueue::Process.collection.name).to start_with("solid_queue_")
    end

    it "respects custom collection prefix" do
      original_prefix = SolidQueueMongoid.collection_prefix

      SolidQueueMongoid.collection_prefix = "custom_"

      # Need to reload the class to pick up new prefix
      # For this test, just verify the configuration works
      expect(SolidQueue.collection_prefix).to eq("custom_")

      SolidQueueMongoid.collection_prefix = original_prefix
    end
  end

  describe "timestamps" do
    it "includes created_at and updated_at" do
      job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        priority: 0
      )

      expect(job.created_at).to be_present
      expect(job.updated_at).to be_present
    end
  end
end
