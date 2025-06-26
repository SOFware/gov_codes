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
end
