# frozen_string_literal: true

require "simplecov" if ENV["CI"]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "gov_codes"
require "gov_codes/afsc"

require "minitest/spec"
require "debug"
