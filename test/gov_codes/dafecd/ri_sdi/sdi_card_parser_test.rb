# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/sdi_card_parser"
require "gov_codes/dafecd/ri_sdi/config"

describe GovCodes::Dafecd::RiSdi::SdiCardParser do
  def parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafecd)
    GovCodes::Dafecd::RiSdi::SdiCardParser.new(record, config: config).entries
  end

  it "parses a standard card: code, own-line title, dual date" do
    record = <<~TXT
      SDI 8A200

                          ENLISTEDAIDE

                (Changed 31 Oct 16, Effective 8 Feb 16)
      1. Special Duty Summary. Performs tasks and details.
    TXT
    entries = parse(record)
    _(entries.size).must_equal 1
    e = entries.first
    _(e[:code]).must_equal "8A200"
    _(e[:name]).must_equal "Enlistedaide"
    _(e[:raw_title]).must_equal "ENLISTEDAIDE"
    _(e[:changed_date]).must_equal "2016-10-31"
    _(e[:glued_title]).must_equal true
    _(e[:shredouts]).must_equal({})
  end

  it "strips a decorative star before the title" do
    record = <<~TXT
      SDI 8A400
                     ★TALENT MANAGEMENT CONSULTANT
                          (Changed 31 Oct 25)
      1. Special Duty Summary. Manages talent.
    TXT
    e = parse(record).first
    _(e[:code]).must_equal "8A400"
    _(e[:raw_title]).must_equal "TALENT MANAGEMENT CONSULTANT"
    _(e[:name]).must_equal "Talent Management Consultant"
    _(e[:changed_date]).must_equal "2025-10-31"
  end

  it "skips a page break (page number + running header) before the title" do
    record = <<~TXT
      SDI 8Y000

                                          364
      DAFECD, 31 Oct 25



                          PATHFINDER
                       (Established 31 Oct 23)
      1. PathfinderAirmen. The primary purpose of this position.
    TXT
    e = parse(record).first
    _(e[:code]).must_equal "8Y000"
    _(e[:name]).must_equal "Pathfinder"
    _(e[:changed_date]).must_equal "2023-10-31"
  end

  it "parses a card that carries no change date" do
    record = <<~TXT
      SDI 81T0
                                INSTRUCTOR
      1. Special Duty Summary. Instructs personnel.
    TXT
    e = parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafocd).first
    _(e[:code]).must_equal "81T0"
    _(e[:name]).must_equal "Instructor"
    _(e[:changed_date]).must_be_nil
  end

  it "joins a multi-line own-line title (officer 81D0)" do
    record = <<~TXT
      SDI 81D0
           AIR FORCE RESERVE OFFICER TRAINING CORPS DETACHMENT COMMANDER
                       AND PROFESSOR OFAEROSPACE STUDIES
                          (Established 30Apr20)
      1. Special Duty Summary. Commands an AFROTC unit.
    TXT
    e = parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafocd).first
    _(e[:code]).must_equal "81D0"
    _(e[:raw_title]).must_equal "AIR FORCE RESERVE OFFICER TRAINING CORPS DETACHMENT COMMANDER AND PROFESSOR OFAEROSPACE STUDIES"
  end

  it "emits one entry per code for a multi-code card, using inline titles" do
    record = <<~TXT
      SDI 8L100,AirAdvisor – Basic
      SDI 8L200,AirAdvisor Basic, Team Sergeant
      SDI 8L300,AirAdvisor Basic, Team Leader


                          EnlistedAirAdvisor – Basic
                             (Changed 31 Oct 22)
      1. Special Duty Summary. Facilitates functional management.
    TXT
    entries = parse(record)
    _(entries.map { |e| e[:code] }).must_equal %w[8L100 8L200 8L300]
    _(entries.map { |e| e[:raw_title] }).must_equal [
      "AirAdvisor - Basic",
      "AirAdvisor Basic, Team Sergeant",
      "AirAdvisor Basic, Team Leader"
    ]
    _(entries.map { |e| e[:changed_date] }.uniq).must_equal ["2022-10-31"]
  end

  it "parses a shredout table into the single code's :shredouts (8R300)" do
    record = <<~TXT
      SDI 8R300*
                          THIRD-TIER RECRUITER
                          (Changed 30 Apr 25)
      1. Special Duty Summary. Manages recruiting.
      4. *Specialty Shredouts:
       Suffix      Portion of AFS to Which Related                        Suffix    Portion of AFS to Which Related
         A         Flight Chief                                              C      Production Superintendent
         B        Graduated, Flight Chief                               E      Senior Enlisted Leader
      5. Utilization Note (RegAF only):
    TXT
    e = parse(record).first
    _(e[:code]).must_equal "8R300"
    _(e[:name]).must_equal "Third-Tier Recruiter"
    _(e[:shredouts]).must_equal({
      A: "Flight Chief",
      B: "Graduated, Flight Chief",
      C: "Production Superintendent",
      E: "Senior Enlisted Leader"
    })
  end

  it "rejects a wrapped-prose false positive (lowercase inline 'title')" do
    record = <<~TXT
      SDI 8P000, completion of a current T5 Investigation IAW DoDM 5200.02,AFMAN 16-1405, Air Force Personnel Security Program, is
      mandatory.
      NOTE: Award of this SDI without a completed T5 Investigation is authorized.
    TXT
    _(parse(record)).must_equal []
  end

  it "returns [] when the block carries no SDI anchor at all" do
    _(parse("Just some prose with no anchor.\n")).must_equal []
  end

  it "keeps the standalone title when a false-positive inline anchor trails in the body" do
    record = <<~TXT
      SDI 8P000
                          COURIER
                          (Changed 31 Oct 16, Effective 8 Feb 16)
      1. Special Duty Summary. Couriers.
      3.5.3. For award and retention of
      SDI 8P000, completion of a current T5 Investigation IAW DoDM 5200.02, is
      mandatory.
    TXT
    e = parse(record).first
    _(e[:code]).must_equal "8P000"
    _(e[:name]).must_equal "Courier"
    _(e[:changed_date]).must_equal "2016-10-31"
  end

  it "parses a bare-format officer multi-code card that lacks the 'SDI ' prefix" do
    # The officer Air Advisor cards print as a bare "CODE,Title" line with no
    # leading "SDI " keyword (89A0-89I0). Each code carries its own inline title
    # and shares one body. Both comma spacings occur in the source: no space
    # ("89A0,Air...") and a space ("89G0, Combat...").
    record = <<~TXT
      89A0,AirAdvisor (Basic)
      89B0,AirAdvisor (Basic) Team Leader
      89C0,AirAdvisor (Basic) Mission Commander
                         OfficerAirAdvisor Basic
                            (Changed 31 Oct 22)
      1. Special Duty Summary. Facilitates functional management.
    TXT
    entries = parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafocd)
    _(entries.map { |e| e[:code] }).must_equal %w[89A0 89B0 89C0]
    _(entries.map { |e| e[:raw_title] }).must_equal [
      "AirAdvisor (Basic)",
      "AirAdvisor (Basic) Team Leader",
      "AirAdvisor (Basic) Mission Commander"
    ]
    _(entries.map { |e| e[:changed_date] }.uniq).must_equal ["2022-10-31"]
  end

  it "parses a bare-format officer card with a space after the comma (89G0)" do
    record = <<~TXT
      89G0, CombatAviationAdvisor
      89H0, CombatAviationAdvisor Team Leader
      89I0, CombatAviationAdvisor Mission Commander
                      Officer CombatAviationAdvisor
                            (Changed 30Apr 25)
      1. Special Duty Summary. Advises.
    TXT
    entries = parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafocd)
    _(entries.map { |e| e[:code] }).must_equal %w[89G0 89H0 89I0]
    _(entries.map { |e| e[:raw_title] }).must_equal [
      "CombatAviationAdvisor",
      "CombatAviationAdvisor Team Leader",
      "CombatAviationAdvisor Mission Commander"
    ]
    _(entries.map { |e| e[:changed_date] }.uniq).must_equal ["2025-04-30"]
  end

  it "handles a keyword-less bare date parenthetical (officer 88X0)" do
    record = <<~TXT
      SDI 88X0
                          OPERATIONALSTEM OFFICER
                          (31 Oct 24)
      1. Specialty Summary. Operational STEM Officer.
    TXT
    e = parse(record, config: GovCodes::Dafecd::RiSdi::Config.dafocd).first
    _(e[:code]).must_equal "88X0"
    _(e[:raw_title]).must_equal "OPERATIONALSTEM OFFICER"
    _(e[:changed_date]).must_equal "2024-10-31"
  end
end
