# frozen_string_literal: true

source "https://rubygems.org"

# Fastlane — iOS/Android build automation
# Pin to ~> 2.x to get patch updates but avoid breaking major bumps.
gem "fastlane", "~> 2.225"

# Optional plugins — uncomment as needed
# gem "fastlane-plugin-firebase_app_distribution"
# gem "fastlane-plugin-versioning"

plugins_path = File.join(File.dirname(__FILE__), 'ios', 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
