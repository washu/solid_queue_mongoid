# frozen_string_literal: true
require "spec_helper"

RSpec.describe "Debug ScheduledExecution" do
  it "tracks ScheduledExecution count during test" do
    puts "\n--- Initial ---"
    puts "RE: #{SolidQueue::ReadyExecution.count}, SE: #{SolidQueue::ScheduledExecution.count}"

    due_jobs = 5.times.map do |i|
      job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "ScheduledJob",
        arguments: { id: i },
        scheduled_at: 1.minute.ago
      )
      job.dispatch
      job
    end

    puts "--- After due jobs ---"
    puts "RE: #{SolidQueue::ReadyExecution.count}, SE: #{SolidQueue::ScheduledExecution.count}"

    future_jobs = 5.times.map do |i|
      job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "FutureJob",
        arguments: { id: i },
        scheduled_at: 1.hour.from_now
      )
      job.dispatch
      job
    end

    puts "--- After future jobs ---"
    puts "RE: #{SolidQueue::ReadyExecution.count}, SE: #{SolidQueue::ScheduledExecution.count}"
    SolidQueue::ScheduledExecution.all.each do |se|
      j = SolidQueue::Job.find(se.job_id)
      puts "  SE job_id=#{se.job_id} scheduled_at=#{j.scheduled_at}"
    end

    threads = 3.times.map do
      Thread.new { SolidQueue::ScheduledExecution.dispatch_due_batch(10) }
    end
    threads.each(&:join)

    puts "--- After dispatch_due_batch ---"
    puts "RE: #{SolidQueue::ReadyExecution.count}, SE: #{SolidQueue::ScheduledExecution.count}"
    SolidQueue::ScheduledExecution.all.each do |se|
      j = SolidQueue::Job.find(se.job_id) rescue nil
      puts "  SE job_id=#{se.job_id} scheduled_at=#{j&.scheduled_at}"
    end

    expect(SolidQueue::ReadyExecution.count).to eq(5)
    expect(SolidQueue::ScheduledExecution.count).to eq(5)
  end
end

