#!/bin/bash
set -e

# Extract version from version.rb
VERSION=$(ruby -r ./lib/solid_queue_mongoid/version.rb -e "puts SolidQueueMongoid::VERSION")

echo "Building gem version ${VERSION}..."
gem build solid_queue_mongoid.gemspec

echo "Pushing to RubyGems..."
gem push solid_queue_mongoid-${VERSION}.gem

echo "Done!"
