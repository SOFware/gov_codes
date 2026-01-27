# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  # Load test_helper before minitest/autorun to ensure SimpleCov's at_exit
  # handler runs AFTER tests complete (at_exit runs in LIFO order)
  t.test_prelude = 'require "test_helper"'
end

require "standard/rake"

task default: %i[test standard]

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/gov_codes/version.rb"
  task.fragment = :git # Enable git trailer extraction for changelog
end
