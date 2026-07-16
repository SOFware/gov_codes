# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/sdi_section_splitter"
require "gov_codes/dafecd/ri_sdi/config"

describe GovCodes::Dafecd::RiSdi::SdiSectionSplitter do
  def split(text, config: GovCodes::Dafecd::RiSdi::Config.dafecd)
    GovCodes::Dafecd::RiSdi::SdiSectionSplitter.new(text, config: config).records
  end

  it "splits a section into one record per card, stripping running headers" do
    text = <<~TXT
      DAFECD, 31 Oct 25
      SDI 8A200
                          ENLISTEDAIDE
                          (Changed 31 Oct 16)
      1. Special Duty Summary. Does aide things.
      DAFECD, 31 Oct 25
      SDI 8A300
                          PROTOCOL
                          (Changed 31 Oct 16)
      1. Special Duty Summary. Does protocol things.
    TXT
    records = split(text)
    _(records.size).must_equal 2
    _(records[0]).must_match(/ENLISTEDAIDE/)
    _(records[0]).wont_match(/PROTOCOL/)
    _(records[1]).must_match(/PROTOCOL/)
    _(records[0]).wont_match(/DAFECD, 31 Oct 25/)
  end

  it "keeps consecutive multi-code anchors in one record" do
    text = <<~TXT
      SDI 8L100,AirAdvisor – Basic
      SDI 8L200,AirAdvisor Basic, Team Sergeant
      SDI 8L300,AirAdvisor Basic, Team Leader
                          EnlistedAirAdvisor – Basic
                          (Changed 31 Oct 22)
      1. Special Duty Summary. Advises.
      SDI 8P000
                          COURIER
                          (Changed 31 Oct 20)
      1. Special Duty Summary. Couriers.
    TXT
    records = split(text)
    _(records.size).must_equal 2
    _(records[0]).must_match(/8L100/)
    _(records[0]).must_match(/8L300/)
    _(records[1]).must_match(/COURIER/)
    _(records[0]).wont_match(/COURIER/)
  end

  it "isolates the embedded CEM ladder record so it never pollutes a card" do
    text = <<~TXT
      SDI 8F100
                          GUARDIAN FIRST SERGEANT
                          (Established 30 Apr 25)
      1. Special Duty Summary. First sergeants.
      CEM Code 8G000
      AFSC 8G091 Superintendent
      AFSC 8G011* Helper
                          ★PREMIER HONOR GUARD
                          (Changed 31 Oct 25)
      1. Special Duty Summary. Honor guard.
      4. Specialty Shredouts:
          Suffix     Portion of AFS to Which Related
            B        Pallbearer
            C        Color Guard
      SDI 8H000
                          AIRMEN DORM LEADER
                          (Changed 31 Oct 16)
      1. Special Duty Summary. Dorm leaders.
    TXT
    records = split(text)
    _(records.size).must_equal 3
    _(records[0]).must_match(/GUARDIAN FIRST SERGEANT/)
    _(records[0]).wont_match(/Pallbearer/) # not polluted by the ladder record
    _(records[1]).must_match(/CEM Code 8G000/)
    _(records[1]).must_match(/Pallbearer/)
    _(records[2]).must_match(/AIRMEN DORM LEADER/)
  end

  it "starts a record at a bare 'CODE,Title' officer card lacking the SDI prefix" do
    # The officer Air Advisor cards (89A0-89I0) have no leading "SDI " keyword;
    # each bare-format block must still be split into its own record.
    text = <<~TXT
      89A0,AirAdvisor (Basic)
      89B0,AirAdvisor (Basic) Team Leader
      89C0,AirAdvisor (Basic) Mission Commander
                         OfficerAirAdvisor Basic
                            (Changed 31 Oct 22)
      1. Special Duty Summary. Advises.
      89G0, CombatAviationAdvisor
      89H0, CombatAviationAdvisor Team Leader
      89I0, CombatAviationAdvisor Mission Commander
                      Officer CombatAviationAdvisor
                            (Changed 30Apr 25)
      1. Special Duty Summary. Advises.
    TXT
    records = split(text, config: GovCodes::Dafecd::RiSdi::Config.dafocd)
    _(records.size).must_equal 2
    _(records[0]).must_match(/89A0/)
    _(records[0]).must_match(/89C0/)
    _(records[0]).wont_match(/CombatAviationAdvisor/)
    _(records[1]).must_match(/89G0/)
    _(records[1]).must_match(/89I0/)
  end

  it "does not start a new record at a wrapped-prose false positive" do
    text = <<~TXT
      SDI 8P000
                          COURIER
                          (Changed 31 Oct 16)
      1. Special Duty Summary. Couriers.
      3.5.3. For award and retention of
      SDI 8P000, completion of a current T5 Investigation IAW DoDM 5200.02, is
      mandatory.
      SDI 8P100
                          DEFENSEATTACHÉ
                          (Changed 31 Oct 20)
      1. Special Duty Summary. Attaches.
    TXT
    records = split(text)
    _(records.size).must_equal 2
    _(records[0]).must_match(/COURIER/)
    _(records[0]).must_match(/completion of a current T5/) # stays as body of 8P000
    _(records[1]).must_match(/DEFENSEATTACHÉ/)
  end
end
