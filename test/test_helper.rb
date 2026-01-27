# frozen_string_literal: true

# SimpleCov must be required BEFORE minitest/autorun to ensure proper at_exit order.
# at_exit handlers run in LIFO order, so SimpleCov's report will generate AFTER
# tests complete only if SimpleCov registers its handler first.
require "simplecov" if ENV["CI"]

# Require minitest components before loading our code to avoid circular require warnings.
# minitest/autorun is loaded by the test task, so we only need minitest/spec here.
require "minitest/autorun"
require "minitest/spec"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "gov_codes"
require "gov_codes/afsc"

require "debug"
