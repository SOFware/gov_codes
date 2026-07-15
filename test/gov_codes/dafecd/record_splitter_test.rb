# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/record_splitter"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::RecordSplitter do
  let(:fixture) {
    <<~TXT
      DAFECD, 31 Oct 25
      CEM Code 1A100*
      AFSC 1A172*, Craftsman
      AFSC 1A152*, Journeyman
      MOBILITY FORCEAVIATOR
      (Changed 31 Oct 25)
      1. Specialty Summary. Does mobility things.
      DAFECD, 31 Oct 25
      CEM Code 1B000
      AFSC 1B491, Superintendent
      CYBER WARFARE OPERATIONS
      (Changed 30 Apr 24)
      1. Specialty Summary. Does cyber things.
    TXT
  }

  it "splits into one record per specialty" do
    records = GovCodes::Dafecd::RecordSplitter.new(fixture).records
    _(records.size).must_equal 2
    _(records[0]).must_match(/MOBILITY FORCE/)
    _(records[1]).must_match(/CYBER WARFARE/)
  end

  it "strips running page headers" do
    records = GovCodes::Dafecd::RecordSplitter.new(fixture).records
    _(records[0]).wont_match(/DAFECD, 31 Oct 25/)
  end

  it "detects a suffix-glued ladder line (bare code, trailing AFSC)" do
    text = <<~TXT
      CEM Code 1A100
      1A194, SuperintendentAFSC
      1A174, CraftsmanAFSC
      1A114, Helper
      MULTI-DOMAIN OPERATIONS AVIATOR
      (Established 31 Oct 2024)
      1. Specialty Summary. Does things.
    TXT
    records = GovCodes::Dafecd::RecordSplitter.new(text).records
    _(records.size).must_equal 1
    _(records[0]).must_match(/1A194/)
    _(records[0]).must_match(/MULTI-DOMAIN/)
  end

  it "detects a prefix-glued ladder line (Word glued to AFSC)" do
    text = <<~TXT
      CEM Code 1A100
      AFSC 1A198*, Senior Enlisted
      LeaderAFSC 1A178*, Craftsman
      AFSC 1A118, Helper
      EXECUTIVE MISSION AVIATOR
      (Changed 31 Oct 25)
      1. Specialty Summary. Does things.
    TXT
    records = GovCodes::Dafecd::RecordSplitter.new(text).records
    _(records.size).must_equal 1
    _(records[0]).must_match(/AFSC 1A178/)
  end

  it "starts a new record at a ladder group not preceded by a CEM line" do
    text = <<~TXT
      CEM Code 1D700
      AFSC 1D791, Superintendent
      CYBERSPACE OPERATIONS
      (Changed 31 Oct 25)
      1. Specialty Summary. Leads things.
      AFSC 1D771, Craftsman
      AFSC 1D751, Journeyman
      CYBER DEFENSE OPERATIONS
      (Changed 31 Oct 25)
      1. Specialty Summary. Defends things.
    TXT

    records = GovCodes::Dafecd::RecordSplitter.new(text).records
    _(records.size).must_equal 2
    _(records[0]).must_match(/CYBERSPACE OPERATIONS/)
    _(records[1]).must_match(/CYBER DEFENSE OPERATIONS/)
    _(records[1]).must_match(/1D771/)
  end

  describe "the officer (DAFOCD) publication" do
    let(:officer) { GovCodes::Dafecd::Publication.dafocd }

    it "splits into one record per officer ladder family and strips the header" do
      text = <<~TXT
        DAFOCD, 31 Oct 25
        AFSC 11B4*, Staff
        AFSC 11B3*,Aircraft Commander
        AFSC 11B2*, Qualified Pilot/Copilot
        AFSC 11B1*, Entry/Student
        BOMBER PILOT
        (Changed 30Apr 23)
        1. Specialty Summary. Pilots bomber aircraft.
        DAFOCD, 31 Oct 25
        AFSC 11E4*, Staff
        AFSC 11E1*, Entry/Student
        EXPERIMENTAL TEST PILOT
        (Changed 31 Oct 25)
        1. Specialty Summary. Tests aircraft.
      TXT
      records = GovCodes::Dafecd::RecordSplitter.new(text, publication: officer).records
      _(records.size).must_equal 2
      _(records[0]).must_match(/BOMBER PILOT/)
      _(records[1]).must_match(/EXPERIMENTAL TEST PILOT/)
      _(records[0]).wont_match(/DAFOCD, 31 Oct 25/)
    end

    it "treats a bare standalone code line as its own record" do
      text = <<~TXT
        AFSC 10C0
        OPERATIONS COMMANDER
        (Changed 31 Oct 08)
        1. Specialty Summary. Commands operations.
        AFSC 11B4*, Staff
        AFSC 11B1*, Entry/Student
        BOMBER PILOT
        (Changed 30Apr 23)
        1. Specialty Summary. Pilots bombers.
      TXT
      records = GovCodes::Dafecd::RecordSplitter.new(text, publication: officer).records
      _(records.size).must_equal 2
      _(records[0]).must_match(/OPERATIONS COMMANDER/)
      _(records[0]).wont_match(/BOMBER PILOT/)
      _(records[1]).must_match(/BOMBER PILOT/)
    end

    it "recovers a suffix-glued officer ladder group (trailing AFSC)" do
      text = <<~TXT
        11G4, StaffAFSC
        11G3, QualifiedAFSC
        GENERALIST PILOT
        (Changed 30Apr 14, Effective 25 Oct 13)
        1. Specialty Summary. Develops plans.
      TXT
      records = GovCodes::Dafecd::RecordSplitter.new(text, publication: officer).records
      _(records.size).must_equal 1
      _(records[0]).must_match(/11G4/)
      _(records[0]).must_match(/GENERALIST PILOT/)
    end

    it "does not start a record at a prose AFSC mention inside a record" do
      text = <<~TXT
        AFSC 11B4*, Staff
        AFSC 11B1*, Entry/Student
        BOMBER PILOT
        (Changed 30Apr 23)
        1. Specialty Summary. Pilots bombers.
        3.3.2. For award ofAFSC 11B2X, completion of transition training.
      TXT
      records = GovCodes::Dafecd::RecordSplitter.new(text, publication: officer).records
      _(records.size).must_equal 1
    end
  end
end
