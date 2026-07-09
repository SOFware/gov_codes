# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/index_builder"

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
end
