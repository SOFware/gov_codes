# Set command name before starting to ensure consistent tracking
SimpleCov.command_name "Unit Tests"

SimpleCov.start do
  # enable_coverage :branch

  # Add any files or directories you want to exclude from coverage
  add_filter "/test/"
  add_filter "lib/gov_codes/version.rb"

  # Set minimum coverage requirements
  # minimum_coverage 80

  # Track all files in the lib directory
  track_files "lib/**/*.rb"

  # Group files by module
  add_group "AFSC", "lib/gov_codes/afsc"

  # Add JSON formatter for easier parsing
  require "simplecov_json_formatter"
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])

  # Enable result merging
  enable_coverage_for_eval
end
