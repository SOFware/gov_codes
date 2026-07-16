require_relative "afsc/enlisted"
require_relative "afsc/officer"
require_relative "afsc/ri"

module GovCodes
  module AFSC
    # Resolve a code as of the classification-directory release in effect on
    # +as_of+ (default: today). +as_of+ applies to every tier: the versioned
    # enlisted (DAFECD) and officer (DAFOCD) AFSC lookups and the versioned
    # RI/SDI lookup (which itself dispatches by code shape to the DAFECD or
    # DAFOCD RI index), each resolved against its own publication.
    def self.find(code, as_of: nil)
      AFSC::Enlisted.find(code, as_of: as_of) ||
        AFSC::Officer.find(code, as_of: as_of) ||
        AFSC::RI.find(code, as_of: as_of)
    end

    # Resolve a code by its acronym (case-insensitive) as of the release in
    # effect on +as_of+ (default: today). Searches the enlisted tier
    # (source-verified acronyms + that release's overlay), then the officer
    # tier (specialty and shredout acronyms + that release's overlay), then the
    # versioned RI/SDI tier (enlisted then officer RI index for that release).
    # Returns a single Code or nil.
    #
    # Acronyms are expected to be unique. If two codes carry the same acronym,
    # the first match wins in a defined order: enlisted before officer before RI,
    # and within a tier by the data's key order.
    def self.find_by_acronym(acronym, as_of: nil)
      AFSC::Enlisted.find_by_acronym(acronym, as_of: as_of) ||
        AFSC::Officer.find_by_acronym(acronym, as_of: as_of) ||
        AFSC::RI.find_by_acronym(acronym, as_of: as_of)
    end

    def self.search(prefix, as_of: nil)
      results = []
      results.concat(Enlisted.search(prefix, as_of: as_of))
      results.concat(Officer.search(prefix, as_of: as_of))
      results.concat(RI.search(prefix, as_of: as_of))
      results
    end

    def self.reset_data(lookup: $LOAD_PATH)
      Enlisted.reset_data(lookup:)
      Officer.reset_data(lookup:)
      RI.reset_data(lookup:)
    end
  end
end
