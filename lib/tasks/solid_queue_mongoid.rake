# frozen_string_literal: true

namespace :solid_queue_mongoid do
  desc "Create MongoDB indexes for SolidQueue models"
  task create_indexes: :environment do
    require "solid_queue_mongoid"

    puts "Creating indexes for SolidQueue Mongoid models..."
    SolidQueueMongoid.create_indexes
  end

  desc "Remove MongoDB indexes for SolidQueue models"
  task remove_indexes: :environment do
    require "solid_queue_mongoid"

    puts "Removing indexes for SolidQueue Mongoid models..."
    SolidQueueMongoid.remove_indexes
  end

  desc "Show collection names for SolidQueue models"
  task show_collections: :environment do
    require "solid_queue_mongoid"

    puts "\nSolidQueue Mongoid Collections:"
    puts "--------------------------------"
    puts "Configuration:"
    puts "  Client: #{SolidQueue.client}"
    puts "  Prefix: #{SolidQueue.collection_prefix}"
    puts "\nCollections:"

    models = [
      SolidQueue::Job,
      SolidQueue::ReadyExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::BlockedExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::FailedExecution,
      SolidQueue::RecurringExecution,
      SolidQueue::Process,
      SolidQueue::Pause,
      SolidQueue::Semaphore,
      SolidQueue::RecurringTask,
      SolidQueue::Queue
    ]

    models.each do |model|
      puts "  #{model.name.ljust(45)} => #{model.collection.name}"
    end
    puts ""
  end
end
