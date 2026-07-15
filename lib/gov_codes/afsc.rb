require_relative "afsc/enlisted"
require_relative "afsc/officer"
require_relative "afsc/ri"

module GovCodes
  module AFSC
    # Resolve a code as of the DAFECD release in effect on +as_of+ (default: the
    # latest shipped release). +as_of+ applies to the versioned enlisted lookup;
    # Officer/RI are unversioned.
    def self.find(code, as_of: nil)
      AFSC::Enlisted.find(code, as_of: as_of) ||
        AFSC::Officer.find(code) ||
        AFSC::RI.find(code)
    end

    # Resolve a code by its acronym (case-insensitive) as of the DAFECD release
    # in effect on +as_of+ (default: the latest shipped release). Searches the
    # enlisted tier (source-verified acronyms + that release's overlay), then the
    # unversioned Officer/RI overlays. Returns a single Code or nil.
    #
    # Acronyms are expected to be unique. If a consumer overlay maps two codes to
    # the same acronym, the first match wins in a defined order: enlisted before
    # officer before RI, and within a tier by the data's key order.
    def self.find_by_acronym(acronym, as_of: nil)
      AFSC::Enlisted.find_by_acronym(acronym, as_of: as_of) ||
        AFSC::Officer.find_by_acronym(acronym) ||
        AFSC::RI.find_by_acronym(acronym)
    end

    def self.search(prefix, as_of: nil)
      results = []
      results.concat(Enlisted.search(prefix, as_of: as_of))
      results.concat(Officer.search(prefix))
      results.concat(RI.search(prefix))
      results
    end

    def self.reset_data(lookup: $LOAD_PATH)
      Enlisted.reset_data(lookup:)
      Officer.reset_data(lookup:)
      RI.reset_data(lookup:)
    end
  end
end
