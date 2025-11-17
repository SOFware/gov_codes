require_relative "afsc/enlisted"
require_relative "afsc/officer"
require_relative "afsc/ri"

module GovCodes
  module AFSC
    def self.find(code)
      AFSC::Enlisted.find(code) ||
        AFSC::Officer.find(code) ||
        AFSC::RI.find(code)
    end

    def self.reset_data(lookup: $LOAD_PATH)
      Enlisted.reset_data(lookup:)
      Officer.reset_data(lookup:)
      RI.reset_data(lookup:)
    end
  end
end
