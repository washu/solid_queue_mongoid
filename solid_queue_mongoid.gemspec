# frozen_string_literal: true

require_relative "lib/solid_queue_mongoid/version"

Gem::Specification.new do |spec|
  spec.name = "solid_queue_mongoid"
  spec.version = SolidQueueMongoid::VERSION
  spec.authors = ["Sal Scotto"]
  spec.email = ["sal.scotto@gmail.com"]

  spec.summary = "Mongoid adapter for SolidQueue"
  spec.description = "Provides Mongoid models to replace ActiveRecord models in SolidQueue, enabling MongoDB as the backend for job queuing."
  spec.homepage = "https://github.com/washu/solid_queue_mongoid"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/washu/solid_queue_mongoid"
  spec.metadata["changelog_uri"] = "https://github.com/washu/solid_queue_mongoid/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mongoid", "~> 9.0"
  spec.add_dependency "solid_queue", ">= 1.4.0", "< 2.0"
  spec.add_dependency "fugit", "~> 1.11"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
