# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/index_builder"
require "gov_codes/dafecd/publication"

# Simulates a future value-transforming step (the C.2 title de-gluer) that emits
# a value not present in the source, so the gate's regression-guard behavior can
# be exercised through #build.
class TransformingBuilder < GovCodes::Dafecd::IndexBuilder
  private

  def emitted_values_to_verify(entry)
    return [] unless entry[:name]
    ["FABRICATED-#{entry[:name]}-NOT-IN-SOURCE"]
  end
end

# Fabricates an acronym that does NOT appear in the source title, to prove the
# acronym verification gate rejects a drifting/ungrounded acronym.
class FabricatedAcronymBuilder < GovCodes::Dafecd::IndexBuilder
  private

  def capture_acronym(specialty, entry)
    entry[:acronym] = "ZZZ" if entry[:name]
  end
end

# Fabricates an acronym that IS a substring of the source title but is NOT the
# parenthetical acronym, to prove the gate verifies `(ACRONYM)` specifically.
class SubstringAcronymBuilder < GovCodes::Dafecd::IndexBuilder
  private

  def capture_acronym(specialty, entry)
    entry[:acronym] = "PARTY" if entry[:name]
  end
end

describe GovCodes::Dafecd::IndexBuilder do
  # Inline "full text" combining two real specialty records: 1A1X2 (glued title,
  # with a shredout table) and 1B4X1 (cleanly spaced title).
  let(:full_text) {
    <<~TXT
      DAFECD, 31 Oct 25
      CEM Code 1A100*
      AFSC 1A192*, Senior Enlisted Leader
      AFSC 1A172*, Craftsman
      AFSC 1A152*, Journeyman
      AFSC 1A132*,Apprentice
      AFSC 1A112, Helper
                            MOBILITY FORCEAVIATOR
                                 (Changed 31 Oct 25)

      1. Specialty Summary. Does mobility things.

      4. *Specialty Shredouts:
         Suffix     Primary Aircraft                   Suffix    Primary Aircraft

            A       C-5 Flight Engineer                   L      C-130H Flight Engineer
            B       C-5 Loadmaster                        N      C-130H Loadmaster
            Y       General
      *NOTE: Y- General shred will be utilized with CFM oversight and approval.

      DAFECD, 31 Oct 25
      CEM Code 1B000
      AFSC 1B491, Superintendent
                            CYBER WARFARE OPERATIONS
                                 (Changed 30 Apr 24)

      1. Specialty Summary. Does cyber things.
    TXT
  }

  it "keys the index by X-form specialty" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index.keys).must_include :"1A1X2"
    _(index.keys).must_include :"1B4X1"
  end

  it "assembles the header fields" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index[:"1A1X2"][:career_field]).must_equal :"1A"
    _(index[:"1A1X2"][:cem_code]).must_equal "1A100"
    _(index[:"1A1X2"][:changed_date]).must_equal "2025-10-31"
    _(index[:"1A1X2"][:skill_levels][7][:code]).must_equal "1A172"
  end

  # DEVIATION FROM PLAN: the plan asserts "Mobility Force Aviator"; the glued
  # source ("FORCEAVIATOR") is emitted conservatively (see SpecialtyParser).
  it "emits the conservatively normalized glued title" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index[:"1A1X2"][:name]).must_equal "Mobility Forceaviator"
  end

  it "emits a cleanly spaced title unchanged" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index[:"1B4X1"][:name]).must_equal "Cyber Warfare Operations"
  end

  it "attaches the shredout map" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index[:"1A1X2"][:shredouts][:Y]).must_equal "General"
    _(index[:"1A1X2"][:shredouts][:L]).must_equal "C-130H Flight Engineer"
  end

  it "reports no unverified codes for a grounded source" do
    _(GovCodes::Dafecd::IndexBuilder.new(full_text).unverified_codes).must_be_empty
  end

  it "verifies a code that appears verbatim in the source" do
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text)
    _(builder.verified?("1A172")).must_equal true
    _(builder.verified?("1A100")).must_equal true
  end

  it "rejects a code absent from the source (anti-hallucination gate)" do
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text)
    _(builder.verified?("9Z999")).must_equal false
  end

  # The gate is a regression guard for future value-transforming steps (the C.2
  # title de-gluer). Transforms register the values they emit via the
  # #emitted_values_to_verify hook; the gate flags any not grounded in the
  # source. TransformingBuilder (top of file) simulates such a transform.
  it "build collects an ungrounded transform value into unverified_codes" do
    builder = TransformingBuilder.new(full_text)
    builder.build
    _(builder.unverified_codes).wont_be_empty
    _(builder.unverified_codes).must_include "FABRICATED-Cyber Warfare Operations-NOT-IN-SOURCE"
  end

  # C1: a record with a CEM but no skill-ladder line (a career-field CEM manager)
  # must be surfaced as dropped, never silently discarded.
  let(:cem_only_text) {
    <<~TXT
      CEM Code 1N000
      INTELLIGENCE
      (Changed 31 Oct 21)
      1. Specialty Summary. Leads intelligence.

      CEM Code 1B000
      AFSC 1B491, Superintendent
      CYBER WARFARE OPERATIONS
      (Changed 30 Apr 24)
      1. Specialty Summary.
    TXT
  }

  it "surfaces a CEM-only record as dropped instead of silently discarding it" do
    builder = GovCodes::Dafecd::IndexBuilder.new(cem_only_text)
    index = builder.build
    _(index.keys).must_equal [:"1B4X1"]
    _(builder.dropped_records.size).must_equal 1
    _(builder.dropped_records.first[:cem_code]).must_equal "1N000"
    _(builder.dropped_records.first[:reason]).must_match(/no.*ladder/i)
  end

  it "reconciles: records split == parsed + merged + dropped" do
    builder = GovCodes::Dafecd::IndexBuilder.new(cem_only_text)
    index = builder.build
    _(builder.records_split).must_equal(index.size + builder.merged_count + builder.dropped_records.size)
  end

  it "counts a re-encountered specialty as merged" do
    text = <<~TXT
      AFSC 1B491, Superintendent
      CYBER WARFARE OPERATIONS
      (Changed 30 Apr 24)
      1. Specialty Summary.

      AFSC 1B471, Craftsman
      AFSC 1B451, Journeyman
      CYBER WARFARE OPERATIONS
      (Changed 30 Apr 24)
      2. Duties.
    TXT
    builder = GovCodes::Dafecd::IndexBuilder.new(text)
    index = builder.build
    _(index.size).must_equal 1
    _(builder.merged_count).must_equal 1
    _(builder.records_split).must_equal(index.size + builder.merged_count + builder.dropped_records.size)
  end

  it "still rejects a code absent from the source via the predicate" do
    gate = GovCodes::Dafecd::IndexBuilder.new("no codes here")
    _(gate.verified?("1Z351")).must_equal false
  end

  # --- Title de-gluing (verified overrides) --------------------------------

  it "applies a matching title override and keeps the gate clean" do
    degluer = GovCodes::Dafecd::TitleDegluer.new("1A1X2": "Mobility Force Aviator")
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text, degluer: degluer)
    index = builder.build
    _(index[:"1A1X2"][:name]).must_equal "Mobility Force Aviator"
    _(builder.unverified_titles).must_be_empty
    _(builder.unverified_codes).must_be_empty
    _(builder.unverified?).must_equal false
  end

  it "flags a drifting override that changed letters and refuses to apply it" do
    degluer = GovCodes::Dafecd::TitleDegluer.new("1A1X2": "Mobility Naval Aviator")
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text, degluer: degluer)
    index = builder.build
    _(builder.unverified_titles).wont_be_empty
    _(builder.unverified_titles.first[:specialty]).must_equal :"1A1X2"
    _(builder.unverified?).must_equal true
    # The stale override is NOT silently applied; the auto title is retained.
    _(index[:"1A1X2"][:name]).must_equal "Mobility Forceaviator"
  end

  it "flags a drifting override that added a stray letter" do
    degluer = GovCodes::Dafecd::TitleDegluer.new("1A1X2": "Mobility Force Aviatorr")
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text, degluer: degluer)
    builder.build
    _(builder.unverified_titles).wont_be_empty
  end

  it "retains the auto-titlecased name and flags specialties needing de-gluing" do
    builder = GovCodes::Dafecd::IndexBuilder.new(full_text) # default: no overrides
    index = builder.build
    _(index[:"1A1X2"][:name]).must_equal "Mobility Forceaviator"
    _(builder.specialties_needing_deglue).must_include :"1A1X2"
    _(builder.specialties_needing_deglue).must_include :"1B4X1"
  end

  # --- Specialty acronyms (trailing parenthetical) -------------------------

  # A real specialty whose de-glued title ends in a parenthesized acronym:
  # "TACTICAL AIR CONTROL PARTY (TACP)" -> acronym TACP.
  let(:acronym_text) {
    <<~TXT
      DAFECD, 31 Oct 25
      CEM Code 1Z300
      AFSC 1Z391, Superintendent
      AFSC 1Z371, Craftsman
      AFSC 1Z351, Journeyman
      AFSC 1Z331, Apprentice
      AFSC 1Z311, Helper
                            TACTICAL AIR CONTROL PARTY (TACP)
                                 (Changed 31 Oct 25)

      1. Specialty Summary. Directs air power.
    TXT
  }

  it "captures a trailing parenthetical acronym into :acronym" do
    index = GovCodes::Dafecd::IndexBuilder.new(acronym_text).build
    _(index[:"1Z3X1"][:acronym]).must_equal "TACP"
  end

  it "leaves the name unchanged (retains the parenthetical)" do
    index = GovCodes::Dafecd::IndexBuilder.new(acronym_text).build
    _(index[:"1Z3X1"][:name]).must_equal "Tactical Air Control Party (TACP)"
  end

  it "reports no unverified acronyms for a grounded acronym" do
    builder = GovCodes::Dafecd::IndexBuilder.new(acronym_text)
    builder.build
    _(builder.unverified_acronyms).must_be_empty
    _(builder.unverified?).must_equal false
  end

  it "omits :acronym when the title has no trailing parenthetical" do
    index = GovCodes::Dafecd::IndexBuilder.new(full_text).build
    _(index[:"1B4X1"].key?(:acronym)).must_equal false
  end

  it "does not capture a non-trailing (mid-title) parenthetical" do
    text = <<~TXT
      AFSC 1T051, Journeyman
      AFSC 1T031, Apprentice
      AFSC 1T011, Helper
      SURVIVAL, EVASION, RESISTANCE, ESCAPE (SERE) SPECIALIST
      (Changed 31 Oct 25)
      1. Specialty Summary.
    TXT
    index = GovCodes::Dafecd::IndexBuilder.new(text).build
    _(index[:"1T0X1"].key?(:acronym)).must_equal false
  end

  it "excludes documented phrase-abbreviation specialties (1D7X2, 1A8X0)" do
    text = <<~TXT
      AFSC 1D752, Journeyman
      AFSC 1D732, Apprentice
      AFSC 1D712, Helper
      RADIO FREQUENCY TRANSMISSIONS AND ELECTROMAGNETIC ACTIVITIES (EMA)
      (Changed 31 Oct 25)
      1. Specialty Summary.
    TXT
    index = GovCodes::Dafecd::IndexBuilder.new(text).build
    _(index[:"1D7X2"][:name]).must_match(/\(EMA\)\z/)
    _(index[:"1D7X2"].key?(:acronym)).must_equal false
  end

  # The acronym gate is anti-hallucination (DEC-003): an emitted acronym absent
  # from the source title must be rejected and fail the build.
  it "gate fires on a fabricated acronym absent from the source title" do
    builder = FabricatedAcronymBuilder.new(acronym_text)
    builder.build
    _(builder.unverified_acronyms).must_include "ZZZ"
    _(builder.unverified?).must_equal true
  end

  # The gate verifies the parenthetical `(ACRONYM)` specifically, not any
  # substring: "PARTY" appears in "...CONTROL PARTY (TACP)" but not as "(PARTY)".
  it "gate fires on a substring that is not the parenthetical acronym" do
    builder = SubstringAcronymBuilder.new(acronym_text)
    builder.build
    _(builder.unverified_acronyms).must_include "PARTY"
    _(builder.unverified?).must_equal true
  end

  # --- Shredout de-gluing (verified overrides) -----------------------------

  # A record whose shredout table carries a pdf-reader-glued value
  # ("ImageryAnalyst") that a verified override should de-glue.
  let(:glued_shredout_text) {
    <<~TXT
      DAFECD, 31 Oct 25
      CEM Code 1N100*
      AFSC 1N151, Journeyman
      AFSC 1N131, Apprentice
      AFSC 1N111, Helper
                            GEOSPATIAL INTELLIGENCE (GEOINT)
                                 (Changed 31 Oct 25)

      1. Specialty Summary. Analyzes imagery.

      4. *Specialty Shredouts:
         Suffix     Portion                            Suffix    Portion

            A       ImageryAnalyst
    TXT
  }

  def sh_degluer(hash)
    GovCodes::Dafecd::ShredoutDegluer.new(hash)
  end

  it "applies a matching shredout override and keeps the gate clean" do
    builder = GovCodes::Dafecd::IndexBuilder.new(
      glued_shredout_text, shredout_degluer: sh_degluer("1N1X1": {A: "Imagery Analyst"})
    )
    index = builder.build
    _(index[:"1N1X1"][:shredouts][:A]).must_equal "Imagery Analyst"
    _(builder.unverified_shredouts).must_be_empty
    _(builder.unverified?).must_equal false
  end

  it "flags a drifting shredout override that changed letters and refuses it" do
    builder = GovCodes::Dafecd::IndexBuilder.new(
      glued_shredout_text, shredout_degluer: sh_degluer("1N1X1": {A: "Imagery Analysts"})
    )
    index = builder.build
    _(builder.unverified_shredouts).wont_be_empty
    _(builder.unverified_shredouts.first[:specialty]).must_equal :"1N1X1"
    _(builder.unverified_shredouts.first[:suffix]).must_equal :A
    _(builder.unverified?).must_equal true
    # The stale override is NOT applied; the verbatim value is retained.
    _(index[:"1N1X1"][:shredouts][:A]).must_equal "ImageryAnalyst"
  end

  it "flags an override targeting a shredout absent from the source" do
    builder = GovCodes::Dafecd::IndexBuilder.new(
      glued_shredout_text, shredout_degluer: sh_degluer("1N1X1": {Z: "Nonexistent Shred"})
    )
    builder.build
    _(builder.unverified_shredouts).wont_be_empty
    _(builder.unverified?).must_equal true
  end

  it "flags an override targeting a specialty absent from the index" do
    builder = GovCodes::Dafecd::IndexBuilder.new(
      glued_shredout_text, shredout_degluer: sh_degluer("9Z9X9": {A: "Ghost"})
    )
    builder.build
    _(builder.unverified_shredouts).wont_be_empty
    _(builder.unverified?).must_equal true
  end

  it "makes no shredout changes when given no override de-gluer" do
    index = GovCodes::Dafecd::IndexBuilder.new(glued_shredout_text).build
    _(index[:"1N1X1"][:shredouts][:A]).must_equal "ImageryAnalyst"
  end

  describe "the officer (DAFOCD) publication" do
    let(:officer) { GovCodes::Dafecd::Publication.dafocd }

    def build(text)
      GovCodes::Dafecd::IndexBuilder.new(text, publication: officer)
    end

    # Real 11B (Bomber Pilot) with its officer shredout table.
    let(:bomber_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 11B4*, Staff
        AFSC 11B3*,Aircraft Commander
        AFSC 11B2*, Qualified Pilot/Copilot
        AFSC 11B1*, Entry/Student
                                                     BOMBER PILOT
                                                     (Changed 30Apr 23)

        1. Specialty Summary. Pilots bomber aircraft.

        4. *Specialty Shredouts:

         Suffix      Portion of AFS to Which Related                 Suffix          Portion of AFS to Which Related

         A               B-1                                         U               Air Liaison Officer (ALO)
         B               B-2                                         Y               General
         C               B-52                                        Z               Other
         D               B-21
      TXT
    }

    it "keys the officer index by ladder-family X-form" do
      index = build(bomber_text).build
      _(index.keys).must_include :"11BX"
    end

    it "emits officer qualification levels under :qual_levels" do
      entry = build(bomber_text).build[:"11BX"]
      _(entry[:qual_levels][4][:code]).must_equal "11B4"
      _(entry[:qual_levels][1][:title]).must_equal "Entry/Student"
      _(entry.key?(:skill_levels)).must_equal false
    end

    it "keeps the shredout value verbatim and records its trailing acronym" do
      entry = build(bomber_text).build[:"11BX"]
      _(entry[:shredouts][:U]).must_equal "Air Liaison Officer (ALO)"
      _(entry[:shredout_acronyms][:U]).must_equal "ALO"
    end

    it "does not flag a grounded shredout acronym" do
      builder = build(bomber_text)
      builder.build
      _(builder.unverified_acronyms).must_be_empty
      _(builder.unverified?).must_equal false
    end

    # Real 19Z (Special Warfare) with the numbered shred-out enumeration.
    let(:special_warfare_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 19Z4*, Staff
        AFSC 19Z3*, Qualified
        AFSC 19Z2*, Intermediate
        AFSC 19Z1*, Entry
                                 SPECIALWARFARE
                                 (Changed 30Apr 25)

        4 Specialty Summary. The AFSPECWAR officers lead ground combat.

        5 Duties and Responsibilities:
        5.719ZXA(Special Tactics Officer (STO)) - Specializes in global access.
        5.819ZXB (Tactical Air Control Party Officer (TACPO)) - Specializes in strike.
        5.919ZXC (Combat Rescue Officer (CRO)) - Specializes in recovery.
      TXT
    }

    it "extracts numbered-enumeration shredout acronyms (19ZXB -> TACPO)" do
      entry = build(special_warfare_text).build[:"19ZX"]
      _(entry[:shredout_acronyms][:B]).must_equal "TACPO"
      _(entry[:shredout_acronyms][:A]).must_equal "STO"
      _(entry[:shredout_acronyms][:C]).must_equal "CRO"
    end

    it "does not flag grounded enumeration acronyms" do
      builder = build(special_warfare_text)
      builder.build
      _(builder.unverified_acronyms).must_be_empty
    end

    # Real 17D (Warfighter Communications): the ladder prints a glued shredout
    # letter and a leading decorative glyph on every level, and the card's
    # shredout table documents the same suffixes. The shred letter must NOT end
    # up baked into the concrete code -- it flows through as a shredout instead.
    let(:warfighter_text) {
      pua = "\u{F0EA}"
      <<~TXT
        DAFOCD, 31 Oct 25
        #{pua}AFSC 17D4W*, Staff
        #{pua}AFSC 17D3W*, Qualified
        #{pua}AFSC 17D1W*, Entry
                                     WARFIGHTER COMMUNICATIONS
                                     (Changed 31 Oct 25)

        1. Specialty Summary. Operates cyberspace infrastructure.

        4. *Specialty Shredouts:

         Suffix        Portion of AFS to Which Related
            T          Technical Track
         W             Warfighter Communications
      TXT
    }

    it "keys the glued-shred 17D card by its X-form family with clean codes" do
      index = build(warfighter_text).build
      _(index.keys).must_include :"17DX"
      entry = index[:"17DX"]
      _(entry[:qual_levels][4]).must_equal({code: "17D4", title: "Staff"})
      _(entry[:qual_levels][1]).must_equal({code: "17D1", title: "Entry"})
    end

    it "flows the glued shred letter through as a shredout, not into the code" do
      entry = build(warfighter_text).build[:"17DX"]
      _(entry[:shredouts][:W]).must_equal "Warfighter Communications"
      _(entry[:shredouts][:T]).must_equal "Technical Track"
      # The concrete ladder codes never carry the W.
      codes = entry[:qual_levels].values.map { |l| l[:code] }
      _(codes.any? { |c| c.include?("W") }).must_equal false
    end

    it "keeps the verification gate clean for the 17D card" do
      builder = build(warfighter_text)
      builder.build
      _(builder.unverified?).must_equal false
    end

    # Bare single-code record (10C0, Operations Commander).
    let(:bare_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 10C0
                                          OPERATIONS COMMANDER
                                          (Changed 31 Oct 08)

        1. Specialty Summary. Commands operations.
      TXT
    }

    it "keys a bare single-code record by the literal code" do
      index = build(bare_text).build
      _(index.keys).must_include :"10C0"
      _(index[:"10C0"][:name]).must_equal "Operations Commander"
      _(index[:"10C0"][:qual_levels]).must_be_empty
    end

    it "reconciles: records split == parsed + merged + dropped" do
      builder = build(bomber_text + special_warfare_text + bare_text)
      index = builder.build
      _(builder.records_split).must_equal(index.size + builder.merged_count + builder.dropped_records.size)
      _(builder.dropped_records).must_be_empty
    end

    # Real 16F: trailing "(FAO)" is a genuine specialty acronym.
    let(:fao_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 16F4*, Staff
        AFSC 16F1, Entry
                                 FOREIGNAREAOFFICER (FAO)
                                 (Changed 31 Oct 25)

        1. Specialty Summary. Advises on foreign areas.
      TXT
    }

    it "captures a trailing specialty acronym into :acronym" do
      entry = build(fao_text).build[:"16FX"]
      _(entry[:acronym]).must_equal "FAO"
    end

    # A shredout table with a glued value ("MobileAir Control") plus a value
    # carrying a trailing acronym ("Trainer (UABMT)"), to prove that de-gluing
    # the value leaves the independently-captured acronym intact.
    let(:glued_officer_shredout_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 13B4*, Staff
        AFSC 13B1*, Entry
                                 AIR BATTLE MANAGER
                                 (Changed 31 Oct 25)

        4. *Specialty Shredouts:

         Suffix      Portion of AFS to Which Related
         D               MobileAir Control
         M               Trainer (UABMT)
      TXT
    }

    it "de-glues a shredout value while retaining its table acronym" do
      degluer = GovCodes::Dafecd::ShredoutDegluer.new("13BX": {D: "Mobile Air Control"})
      builder = GovCodes::Dafecd::IndexBuilder.new(
        glued_officer_shredout_text, publication: officer, shredout_degluer: degluer
      )
      entry = builder.build[:"13BX"]
      _(entry[:shredouts][:D]).must_equal "Mobile Air Control"
      _(entry[:shredout_acronyms][:M]).must_equal "UABMT"
      _(builder.unverified?).must_equal false
    end

    # --- I1: wrapped prose must never become a qual-ladder entry -----------

    # A real DAFOCD source line ("AFSC 14F3, but applied to developing")
    # wrapped onto its own line inside the specialty's summary prose. It must
    # not overwrite the real level-3 title.
    let(:prose_after_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 14F4*, Staff
        AFSC 14F3*, Qualified
        AFSC 14F1*, Entry
                                 INFORMATION OPERATIONS
                                 (Changed 31 Oct 25)

        1. Specialty Summary. Information operations doctrine,
        AFSC 14F3, but applied to developing
        information operations across the force.
      TXT
    }

    it "does not admit a wrapped-prose line as an officer ladder entry" do
      builder = build(prose_after_text)
      entry = builder.build[:"14FX"]
      _(entry[:qual_levels][3][:title]).must_equal "Qualified"
      _(entry[:qual_levels].keys.sort).must_equal [1, 3, 4]
    end

    # The reviewer's flipped-order scenario: the prose fragment for 42G3
    # appears (as its own would-be record) BEFORE the real ladder. Under the
    # old anchor, existing-wins merge would let the garbage title win; the
    # tightened anchor drops the fragment entirely so the real title survives.
    let(:prose_before_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        2. Duties. Provides physician-assistant care that is
        AFSC 42G3, current and continuous
        across the beneficiary population.

        AFSC 42G4*, Staff
        AFSC 42G3*, Qualified
        AFSC 42G1*, Entry
                                 PHYSICIAN ASSISTANT
                                 (Changed 31 Oct 25)

        1. Specialty Summary.
      TXT
    }

    it "does not let a prose fragment before the real record corrupt its title" do
      builder = build(prose_before_text)
      entry = builder.build[:"42GX"]
      _(entry[:qual_levels][3][:title]).must_equal "Qualified"
      _(builder.merged_count).must_equal 0
      _(builder.records_split).must_equal(
        builder.build.size + builder.merged_count + builder.dropped_records.size
      )
    end

    # --- I1 layer (b): a merge title conflict must be surfaced, never silent -

    let(:conflicting_title_text) {
      <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 11B3*, Aircraft Commander
                                 BOMBER PILOT
                                 (Changed 30Apr 23)

        1. Specialty Summary. Pilots bombers.

        AFSC 11B3*, Flight Lead
                                 BOMBER PILOT
                                 (Changed 30Apr 23)

        2. Duties and Responsibilities.
      TXT
    }

    it "surfaces a merge conflict when a level digit gets a different title" do
      builder = build(conflicting_title_text)
      entry = builder.build[:"11BX"]
      # Existing (first) wins: the level-3 title is unchanged.
      _(entry[:qual_levels][3][:title]).must_equal "Aircraft Commander"
      _(builder.merge_conflicts).wont_be_empty
      conflict = builder.merge_conflicts.first
      _(conflict[:specialty]).must_equal :"11BX"
      _(conflict[:level]).must_equal 3
      _(conflict[:kept]).must_equal "Aircraft Commander"
      _(conflict[:discarded]).must_equal "Flight Lead"
    end

    it "records no merge conflict when there is no title disagreement" do
      builder = build(bomber_text)
      builder.build
      _(builder.merge_conflicts).must_be_empty
    end
  end
end
