# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/ri_list_parser"
require "gov_codes/dafecd/ri_sdi/config"

describe GovCodes::Dafecd::RiSdi::RiListParser do
  def entries(text, config: GovCodes::Dafecd::RiSdi::Config.dafecd)
    GovCodes::Dafecd::RiSdi::RiListParser.new(text, config: config).entries
  end

  def one(text, **kw)
    es = entries(text, **kw)
    _(es.size).must_equal 1
    es.first
  end

  it "parses a plain comma anchor, title ending at the period" do
    e = one("1. 9A000, EnlistedAirman/Guardian - Disqualified for Reasons Beyond Control.\n")
    _(e[:number]).must_equal 1
    _(e[:code]).must_equal "9A000"
    _(e[:raw_title]).must_equal "EnlistedAirman/Guardian - Disqualified for Reasons Beyond Control"
    _(e[:changed_date]).must_be_nil
  end

  it "tolerates a run of spaces after the list number" do
    e = one("10.    9C100, ExecutiveAssistant to the Chief Master Sergeant of theAir Force. (Changed 31 Oct 21)\n")
    _(e[:code]).must_equal "9C100"
    _(e[:raw_title]).must_equal "ExecutiveAssistant to the Chief Master Sergeant of theAir Force"
    _(e[:changed_date]).must_equal "2021-10-31"
  end

  it "handles no comma after the code with the date on the same line" do
    e = one("12.   9D200 Key Developmental Senior Enlisted Positions (Established 31 Oct 21).\n")
    _(e[:code]).must_equal "9D200"
    _(e[:raw_title]).must_equal "Key Developmental Senior Enlisted Positions"
    _(e[:changed_date]).must_equal "2021-10-31"
  end

  it "strips a decorative star before the code" do
    e = one("13. ★9D300, Wing (Wing level) or Headquarter (HQ level) Senior Enlisted Leader. (Established 31 Oct 25)\n")
    _(e[:code]).must_equal "9D300"
    _(e[:raw_title]).must_equal "Wing (Wing level) or Headquarter (HQ level) Senior Enlisted Leader"
    _(e[:changed_date]).must_equal "2025-10-31"
  end

  it "handles a list number glued to the code (no space)" do
    e = one("34.9T000, Basic Enlisted Airman.\n")
    _(e[:number]).must_equal 34
    _(e[:code]).must_equal "9T000"
    _(e[:raw_title]).must_equal "Basic Enlisted Airman"
  end

  it "handles glue + star together with a same-line date" do
    e = one("33.★9S100, ScientificApplications Specialist (Changed 31 Oct 25).\n")
    _(e[:code]).must_equal "9S100"
    _(e[:raw_title]).must_equal "ScientificApplications Specialist"
    _(e[:changed_date]).must_equal "2025-10-31"
  end

  it "joins a title that wraps across lines, ending at the period" do
    text = <<~TXT
      54.9Z000, Special Warfare Mission Support (SWMS) Career Field Manager (CFM) on HeadquartersAir Force Staff,Air Force
      Special Warfare Division. (Changed 31 Oct 21).
      54.1. Use this identifier to report the awarded AFSCs.
    TXT
    e = one(text)
    _(e[:code]).must_equal "9Z000"
    _(e[:raw_title]).must_equal "Special Warfare Mission Support (SWMS) Career Field Manager (CFM) on HeadquartersAir Force Staff,Air Force Special Warfare Division"
    _(e[:changed_date]).must_equal "2021-10-31"
  end

  it "keeps a trailing acronym parenthetical in the raw title" do
    e = one("26. 9M200, International Health Specialists (IHS). (Changed 30Apr 24) Use this identifier to report duties.\n")
    _(e[:code]).must_equal "9M200"
    _(e[:raw_title]).must_equal "International Health Specialists (IHS)"
    _(e[:changed_date]).must_equal "2024-04-30"
  end

  it "ships a Reserved for Future Use placeholder verbatim" do
    e = one("44.9W100, Reserved for Future Use. (Change effective 11 May 15).\n")
    _(e[:code]).must_equal "9W100"
    _(e[:raw_title]).must_equal "Reserved for Future Use"
    _(e[:changed_date]).must_equal "2015-05-11"
  end

  it "extracts a shredout block within a rich record (reuses ShredoutParser)" do
    text = <<~TXT
      24. 9L100, InternationalAffairs Specialist. (Changed 30Apr 25)
      24.1. Use this identifier to report duties.
      24.5.    Specialty Shredouts:
       Suffix                 Portion of RI to Which Related
       A                      Air Component Manager
       B                      Tactical Specialist
       C                      Institutional Specialist
       D                      Embassy Specialist
    TXT
    e = one(text)
    _(e[:code]).must_equal "9L100"
    _(e[:raw_title]).must_equal "InternationalAffairs Specialist"
    _(e[:shredouts]).must_equal({
      A: "Air Component Manager",
      B: "Tactical Specialist",
      C: "Institutional Specialist",
      D: "Embassy Specialist"
    })
  end

  describe "officer flat list (no comma, title ends at first period)" do
    let(:officer) { GovCodes::Dafecd::RiSdi::Config.dafocd }

    it "parses a no-comma officer record, title before the first period" do
      e = one("1. 90G0 General Officer. Use this identifier to report the duty and primaryAFSC of all officers.\n",
        config: officer)
      _(e[:code]).must_equal "90G0"
      _(e[:raw_title]).must_equal "General Officer"
      _(e[:changed_date]).must_be_nil
    end

    it "handles an officer date parenthetical before the terminating period" do
      e = one("13.92P0 PhysicianAssistant Student (Established 31 Oct 17). Use this identifier to report a duty AFSC.\n",
        config: officer)
      _(e[:code]).must_equal "92P0"
      _(e[:raw_title]).must_equal "PhysicianAssistant Student"
      _(e[:changed_date]).must_equal "2017-10-31"
    end

    it "does not create a record for the 24.Disqualified glue artifact" do
      text = <<~TXT
        23.92W3 Non-Combat Wounded Warrior. (Change to specialty description only effective 11 May 15).Air Force Wounded Warrior
        the PAFSC will be the appropriate
        24.DisqualifiedAirman RI (96X0) following disqualification approval byAFPC/DPMSSM.
        25.92W4 Wounded Warrior – LimitedAssignment Status (LAS). (Change effective 11 May 15).Air Force Wounded Warrior
      TXT
      es = entries(text, config: officer)
      _(es.map { |e| e[:number] }).must_equal [23, 25]
      _(es.map { |e| e[:code] }).must_equal %w[92W3 92W4]
    end

    it "rejects the deeply-indented academic CIP codes (4th char is X)" do
      text = <<~TXT
        41.99G0 Gold Bar Recruiter. (Effective 5 June 2013) Use this identifier to report duties.
                                          14.10XX            Electrical Engineering
                                          52.02XX            Business Administration
      TXT
      es = entries(text, config: officer)
      _(es.map { |e| e[:code] }).must_equal %w[99G0]
    end
  end

  it "returns entries in document order with sequential numbers" do
    text = <<~TXT
      1. 9A000, First. (Changed 31 Oct 25)
      2. 9A100, Second. (Changed 31 Oct 25)
      3. 9A200, Third. (Changed 31 Oct 25)
    TXT
    _(entries(text).map { |e| e[:number] }).must_equal [1, 2, 3]
  end
end
