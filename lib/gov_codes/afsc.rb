require_relative "afsc/enlisted"
require_relative "afsc/officer"

module GovCodes
  module AFSC
    def self.find(code)
      AFSC::Enlisted.find(code) ||
        AFSC::Officer.find(code)
    end

    def self.reset_data(lookup: $LOAD_PATH)
      Enlisted.reset_data(lookup:)
      Officer.reset_data(lookup:)
    end
  end
end
