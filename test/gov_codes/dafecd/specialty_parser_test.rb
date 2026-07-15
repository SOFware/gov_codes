# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/specialty_parser"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::SpecialtyParser do
  # Real snippet from the 31 Oct 25 DAFECD (1A1X2, Mobility Force Aviator).
  # The title arrives glued from pdf-reader ("FORCEAVIATOR"); see the clean-title
  # and glue-flag tests below for how that is handled conservatively.
  let(:mobility_record) {
    <<~TXT
      CEM Code 1A100*
      AFSC 1A192*, Senior Enlisted Leader
      AFSC 1A172*, Craftsman
      AFSC 1A152*, Journeyman

      AFSC 1A132*,Apprentice
      AFSC 1A112, Helper
                            MOBILITY FORCEAVIATOR
                                 (Changed 31 Oct 25)

      1. Specialty Summary. The Lead-MAJCOM for aircraft and mission set will
      determine the Mobility ForceAviator (MFA) performance tasks.
    TXT
  }

  it "parses the X-form specialty and career field from the ladder" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:specialty]).must_equal :"1A1X2"
    _(result[:career_field]).must_equal :"1A"
  end

  it "parses the CEM code" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:cem_code]).must_equal "1A100"
  end

  it "parses the per-specialty change date as ISO 8601" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:changed_date]).must_equal "2025-10-31"
  end

  it "parses the skill ladder keyed by skill-level digit" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:skill_levels][9]).must_equal({code: "1A192", title: "Senior Enlisted Leader"})
    _(result[:skill_levels][7]).must_equal({code: "1A172", title: "Craftsman"})
    _(result[:skill_levels][5]).must_equal({code: "1A152", title: "Journeyman"})
    _(result[:skill_levels][3]).must_equal({code: "1A132", title: "Apprentice"})
    _(result[:skill_levels][1]).must_equal({code: "1A112", title: "Helper"})
  end

  # DEVIATION FROM PLAN: the plan's Task 2 asserts name == "Mobility Force Aviator".
  # pdf-reader glues "FORCE" and "AVIATOR" into "FORCEAVIATOR" with no recoverable
  # boundary. Per the title-de-gluing judgment call, we do NOT invent a split; we
  # emit the conservatively title-cased verbatim title and flag it glued for the
  # deferred C.2 despacer.
  it "title-cases a glued title verbatim without inventing a split" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:name]).must_equal "Mobility Forceaviator"
    _(result[:glued_title]).must_equal true
  end

  # Real snippet from the 31 Oct 25 DAFECD (1B4X1). Its title arrives cleanly
  # spaced, so conservative title-casing yields the correct name.
  let(:cyber_record) {
    <<~TXT
      CEM Code 1B000
      AFSC 1B491, Superintendent
                              CYBER WARFARE OPERATIONS
                                    (Changed 30 Apr 24)

      1. Specialty Summary.
    TXT
  }

  it "title-cases a cleanly spaced title and does not flag it glued" do
    result = GovCodes::Dafecd::SpecialtyParser.new(cyber_record).parse
    _(result[:name]).must_equal "Cyber Warfare Operations"
    _(result[:glued_title]).must_equal false
    _(result[:changed_date]).must_equal "2024-04-30"
  end

  # pdf-reader prepends decorative symbol-font glyphs to many titles: a Private
  # Use Area bullet (U+F0EA) and a black star (U+2605). They are not part of the
  # title and must be dropped before extraction.
  it "strips a leading Private Use Area glyph from the title" do
    pua = "\u{F0EA}"
    record = <<~TXT
      CEM Code 1A100*
      AFSC 1A112, Helper
                            #{pua}MOBILITY FORCEAVIATOR
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Mobility Forceaviator"
  end

  it "strips a leading black-star marker from the title" do
    star = "★"
    record = <<~TXT
      CEM Code 3P000
      AFSC 3P011, Helper
                            #{star}SECURITY FORCES
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Security Forces"
  end

  it "accepts a title containing a unicode en dash" do
    en_dash = "–"
    record = <<~TXT
      CEM Code 3N200
      AFSC 3N291, Superintendent
                    PREMIER BAND #{en_dash} THE USAF BAND
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Premier Band - The Usaf Band"
  end

  # Real 4J0X2 (Diet Therapy): the subdivision superintendent 4J090 carries
  # specific digit 0, while the specialty's own levels are 4J0X2. The record must
  # key by the shared specific digit of the lower levels, not the superintendent.
  it "keys by the lower levels' specific digit, not a specific-0 superintendent" do
    record = <<~TXT
      CEM Code 4J000
      AFSC 4J090, Superintendent
      AFSC 4J072*, Craftsman
      AFSC 4J052*, Journeyman
      AFSC 4J032*,Apprentice
      AFSC 4J012, Helper
                            DIET THERAPY
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"4J0X2"
    _(result[:career_field]).must_equal :"4J"
    _(result[:skill_levels][9]).must_equal({code: "4J090", title: "Superintendent"})
    _(result[:skill_levels][7]).must_equal({code: "4J072", title: "Craftsman"})
    _(result[:skill_levels][1]).must_equal({code: "4J012", title: "Helper"})
  end

  # Real 3E4X1 ladder lines carry an alternate code, e.g. "3E471 or 3E471A".
  it "parses a ladder line that lists an alternate 'or' code" do
    record = <<~TXT
      CEM Code 3E000
      AFSC 3E471 or 3E471A, Craftsman
      AFSC 3E451 or 3E451A, Journeyman
      AFSC 3E431*,Apprentice
      AFSC 3E411, Helper
                            WATER AND FUEL SYSTEMS MAINTENANCE
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"3E4X1"
    _(result[:skill_levels][7]).must_equal({code: "3E471", title: "Craftsman"})
    _(result[:skill_levels][5]).must_equal({code: "3E451", title: "Journeyman"})
  end

  # Real 6C091 ladder line carries a trailing acronym: "Senior Enlisted Leader (SEL)".
  it "parses a ladder line with a trailing parenthetical acronym" do
    record = <<~TXT
      CEM Code 6C000
      AFSC 6C091, Senior Enlisted Leader (SEL)
      AFSC 6C071, Craftsman
      AFSC 6C051, Journeyman
                            CONTRACTING
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:skill_levels][9]).must_equal({code: "6C091", title: "Senior Enlisted Leader"})
  end

  # SUFFIX-GLUE (real 1A1X4, Multi-domain Operations Aviator): pdf-reader shifts
  # each "AFSC" prefix to the end of the previous line, leaving bare codes at
  # line start and a trailing "AFSC", e.g. "1A194, SuperintendentAFSC".
  it "parses a suffix-glued ladder (bare code at start, trailing AFSC)" do
    record = <<~TXT
      CEM Code 1A100
      1A194, SuperintendentAFSC
      1A174, CraftsmanAFSC
      1A154, JourneymanAFSC
      1A134,ApprenticeAFSC
      1A114, Helper
                            MULTI-DOMAIN OPERATIONS AVIATOR
                                 (Established 31 Oct 2024)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"1A1X4"
    _(result[:career_field]).must_equal :"1A"
    _(result[:changed_date]).must_equal "2024-10-31"
    _(result[:skill_levels][9]).must_equal({code: "1A194", title: "Superintendent"})
    _(result[:skill_levels][7]).must_equal({code: "1A174", title: "Craftsman"})
    _(result[:skill_levels][5]).must_equal({code: "1A154", title: "Journeyman"})
    _(result[:skill_levels][3]).must_equal({code: "1A134", title: "Apprentice"})
    _(result[:skill_levels][1]).must_equal({code: "1A114", title: "Helper"})
  end

  # PREFIX-GLUE (real 1A1X8): a wrapped "Leader" glues to the next ladder line's
  # "AFSC", e.g. "LeaderAFSC 1A178*, Craftsman", hiding the level-7 code.
  it "parses a prefix-glued ladder (Word glued to AFSC)" do
    record = <<~TXT
      CEM Code 1A100
      AFSC 1A198*, Senior Enlisted
      LeaderAFSC 1A178*, Craftsman
      AFSC 1A158*, Journeyman
      AFSC 1A138*,Apprentice
      AFSC 1A118, Helper
                            EXECUTIVE MISSION AVIATOR
                                 (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"1A1X8"
    _(result[:skill_levels][9]).must_equal({code: "1A198", title: "Senior Enlisted Leader"})
    _(result[:skill_levels][7]).must_equal({code: "1A178", title: "Craftsman"})
    _(result[:skill_levels][1]).must_equal({code: "1A118", title: "Helper"})
  end

  it "does not treat a prose AFSC mention as a ladder line" do
    record = <<~TXT
      CEM Code 1B000
      AFSC 1B491, Superintendent
                            CYBER WARFARE OPERATIONS
                                 (Changed 30 Apr 24)

      1. Specialty Summary.
      3.4.1. 1B451. Qualification in and possession ofAFSC 1B431 and experience
      performing functions such as CNO/cryptologic activities is mandatory.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"1B4X1"
    # Only the real ladder line (1B491) is captured; the prose codes are ignored.
    _(result[:skill_levels].keys.sort).must_equal [9]
  end

  # Real 1A1X4 / 1A1X8 titles arrive in Title Case, not all caps. They must
  # still be captured (bounded by the date / summary line), not dropped.
  it "captures a mixed-case (title-case) title" do
    record = <<~TXT
      CEM Code 1A100
      1A194, SuperintendentAFSC
      1A114, Helper
                            Multi-domain Operations Aviator
                                 (Established 31 Oct 2024)
      1.Specialty Summary. Leads.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Multi-Domain Operations Aviator"
    _(result[:raw_title]).must_equal "Multi-domain Operations Aviator"
  end

  it "exposes the raw pre-titlecase title for the de-gluing inventory" do
    result = GovCodes::Dafecd::SpecialtyParser.new(mobility_record).parse
    _(result[:raw_title]).must_equal "MOBILITY FORCEAVIATOR"
    _(result[:name]).must_equal "Mobility Forceaviator"
  end

  it "stops the title at a 'Special Duty Summary' section" do
    record = <<~TXT
      CEM Code 1A100
      AFSC 1A118, Helper
                            Executive Mission Aviator
      1. Special Duty Summary. Determines tasks.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Executive Mission Aviator"
  end

  # Real 2A3X7: pdf-reader pads the title with a long run of spaces
  # ("(5<many spaces>TH GENERATION)"). Internal padding must collapse so the
  # title is recognized (not rejected as over-long).
  it "collapses long internal padding within a title" do
    record = <<~TXT
      CEM Code 2A300
      AFSC 2A317*, Helper
                            TACTICALAIRCRAFT MAINTENANCE (5                                   TH  GENERATION)
                                 (Changed 31 Oct 21)
      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:specialty]).must_equal :"2A3X7"
    _(result[:raw_title]).must_equal "TACTICALAIRCRAFT MAINTENANCE (5 TH GENERATION)"
    _(result[:name]).must_equal "Tacticalaircraft Maintenance (5 Th Generation)"
  end

  # Real 1C8X3 uses an "(Effective ...)" annotation on its own line after the
  # title; it must bound the title (not leak in) and be captured as the date.
  it "treats an (Effective ...) annotation as the date boundary" do
    record = <<~TXT
      CEM Code 1C800
      AFSC 1C893, Superintendent
                            RADAR, AIRFIELD & WEATHER SYSTEMS (RAWS)
                                 (Effective 30 Apr 23)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:raw_title]).must_equal "RADAR, AIRFIELD & WEATHER SYSTEMS (RAWS)"
    _(result[:changed_date]).must_equal "2023-04-30"
  end

  it "preserves parenthesized acronyms and joins a two-line title" do
    record = <<~TXT
      CEM Code 1U100
      AFSC 1U171, Craftsman
                 REMOTELY PILOTED AIRCRAFT (RPA)
                        SENSOR OPERATOR
                       (Changed 31 Oct 25)

      1. Specialty Summary.
    TXT
    result = GovCodes::Dafecd::SpecialtyParser.new(record).parse
    _(result[:name]).must_equal "Remotely Piloted Aircraft (RPA) Sensor Operator"
  end

  describe "the officer (DAFOCD) publication" do
    let(:officer) { GovCodes::Dafecd::Publication.dafocd }

    # Real 11B (Bomber Pilot): four qualification levels 1-4, glued change date.
    let(:bomber_record) {
      <<~TXT
        AFSC 11B4*, Staff
        AFSC 11B3*,Aircraft Commander

        AFSC 11B2*, Qualified Pilot/Copilot
        AFSC 11B1*, Entry/Student
                                                     BOMBER PILOT

                                                     (Changed 30Apr 23)

        1. Specialty Summary. Pilots bomber aircraft.
      TXT
    }

    def parse(record)
      GovCodes::Dafecd::SpecialtyParser.new(record, publication: officer).parse
    end

    it "keys the ladder family with X at the level digit" do
      result = parse(bomber_record)
      _(result[:specialty]).must_equal :"11BX"
      _(result[:career_field]).must_equal :"11"
    end

    it "parses qualification levels 1-4 under :qual_levels" do
      result = parse(bomber_record)
      _(result[:qual_levels][4]).must_equal({code: "11B4", title: "Staff"})
      _(result[:qual_levels][3]).must_equal({code: "11B3", title: "Aircraft Commander"})
      _(result[:qual_levels][2]).must_equal({code: "11B2", title: "Qualified Pilot/Copilot"})
      _(result[:qual_levels][1]).must_equal({code: "11B1", title: "Entry/Student"})
      _(result).wont_include :skill_levels
    end

    it "parses the glued day/month change date" do
      _(parse(bomber_record)[:changed_date]).must_equal "2023-04-30"
    end

    it "captures the (glued) officer title" do
      _(parse(bomber_record)[:name]).must_equal "Bomber Pilot"
      _(parse(bomber_record)[:raw_title]).must_equal "BOMBER PILOT"
    end

    it "has no CEM code" do
      _(parse(bomber_record)[:cem_code]).must_be_nil
    end

    # Multi-annotation date: the first (Established/Changed/Effective) is kept.
    it "captures the first of multiple date annotations" do
      record = <<~TXT
        AFSC 13O4, Staff
        AFSC 13O1, Entry Level
        MULTI-DOMAIN WARFARE OFFICER
        (Established 30Apr 18, Changed 31 Oct 21)
        1. Specialty Summary. Leads.
      TXT
      _(parse(record)[:changed_date]).must_equal "2018-04-30"
    end

    # Bare single-code record (10C0): a full record with title/date but no ladder.
    let(:bare_record) {
      <<~TXT
        AFSC 10C0

                                          OPERATIONS COMMANDER

                                                    (Changed 31 Oct 08)

        1. Specialty Summary. Commands operations.
      TXT
    }

    it "keys a bare single-code record by the literal code" do
      result = parse(bare_record)
      _(result[:specialty]).must_equal :"10C0"
      _(result[:career_field]).must_equal :"10"
    end

    it "gives a bare record no qualification levels but keeps its code" do
      result = parse(bare_record)
      _(result[:qual_levels]).must_be_empty
      _(result[:bare_code]).must_equal "10C0"
    end

    it "captures the bare record's title and date" do
      result = parse(bare_record)
      _(result[:name]).must_equal "Operations Commander"
      _(result[:changed_date]).must_equal "2008-10-31"
    end

    it "recovers a suffix-glued officer ladder line (trailing AFSC)" do
      record = <<~TXT
        11G4, StaffAFSC
        11G3, QualifiedAFSC
        GENERALIST PILOT
        (Changed 30Apr 14, Effective 25 Oct 13)
        1. Specialty Summary. Develops plans.
      TXT
      result = parse(record)
      _(result[:specialty]).must_equal :"11GX"
      _(result[:qual_levels][4]).must_equal({code: "11G4", title: "Staff"})
      _(result[:qual_levels][3]).must_equal({code: "11G3", title: "Qualified"})
    end

    it "does not treat a prose AFSC mention as a ladder line" do
      record = <<~TXT
        AFSC 11B4*, Staff
        AFSC 11B1*, Entry/Student
        BOMBER PILOT
        (Changed 30Apr 23)
        1. Specialty Summary. Pilots bombers.
        3.3.2. For award ofAFSC 11B2X, completion of transition training.
      TXT
      result = parse(record)
      _(result[:qual_levels].keys.sort).must_equal [1, 4]
    end
  end
end
