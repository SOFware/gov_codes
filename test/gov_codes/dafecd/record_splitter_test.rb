# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/record_splitter"

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
end
