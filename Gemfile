# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in solid_queue_mongoid.gemspec
gemspec

gem "rake", "~> 13.0"
# rspec
gem "rspec", "~> 3.0"
gem "rspec-rails", require: false
# simple cov
gem "simplecov", require: false
# rubocop
gem "rubocop", "~> 1.21"

rails_version = ENV.fetch("RAILS_VERSION", "8.1")
gem "rails", "~> #{rails_version}.0"
