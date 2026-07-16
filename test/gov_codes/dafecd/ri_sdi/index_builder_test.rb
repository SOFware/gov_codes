# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/index_builder"
require "gov_codes/dafecd/ri_sdi/config"
require "gov_codes/dafecd/title_degluer"

describe GovCodes::Dafecd::RiSdi::IndexBuilder do
  # A compact but structurally faithful enlisted directory: an AF SDI card, the
  # embedded 8G000 CEM ladder record, an AF RI item with a trailing acronym and
  # one with a shredout table, a Space Force SDI card, and a Space Force RI item.
  let(:enlisted_text) {
    <<~TXT
      SPECIALDUTY IDENTIFIERS (SDI)
      SDI 8A200
                          ENLISTEDAIDE
                          (Changed 31 Oct 16, Effective 8 Feb 16)
      1. Special Duty Summary. Aide.
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
      AIR FORCE REPORTING IDENTIFIERS (RI)
      8. 9B100, Senior EnlistedAdvisor to the Chief of the National Guard Bureau (CNGB) (Established 31 Oct 23)
      26. 9M200, International Health Specialists (IHS). (Changed 30Apr 24) Use this to report duties.
      33.★9S100, ScientificApplications Specialist (Changed 31 Oct 25).
      33.4. Specialty Shredouts:
          Suffix     Portion of RI to Which Related
            D        ISR Applied Data Science
      SPACE FORCE SPECIALTY CODES (SFSC)
      out of scope
      SPACE FORCE SPECIALDUTY IDENTIFIERS (SDI)
      SDI 8B400
                          ★Military Training Instructor (Space Force)
                          (Changed 31 Oct 25)
      1. Special Duty Summary. Trains.
      SPACE FORCE REPORTING IDENTIFIERS (RI)
      1.9S000, Chief Master Sergeant of the Space Force. (Established 30Apr 20)
    TXT
  }

  def build(text = enlisted_text, config: GovCodes::Dafecd::RiSdi::Config.dafecd,
    degluer: GovCodes::Dafecd::TitleDegluer.empty)
    b = GovCodes::Dafecd::RiSdi::IndexBuilder.new(text, config: config, degluer: degluer)
    b.build
    b
  end

  def degluer(hash)
    GovCodes::Dafecd::TitleDegluer.new(hash)
  end

  it "combines every section into one code-keyed index" do
    index = build.index
    _(index.keys.sort).must_equal %i[8A200 8B400 8G000 9B100 9M200 9S000 9S100].sort
  end

  it "keys the embedded ladder record by its CEM code with its shredouts" do
    entry = build.index[:"8G000"]
    _(entry[:name]).must_equal "Premier Honor Guard"
    _(entry[:changed_date]).must_equal "2025-10-31"
    _(entry[:shredouts]).must_equal({B: "Pallbearer", C: "Color Guard"})
  end

  it "captures a trailing acronym that names the identifier (IHS)" do
    _(build.index[:"9M200"][:acronym]).must_equal "IHS"
  end

  it "excludes an organization-abbreviation acronym (CNGB) per the config" do
    _(build.index[:"9B100"][:acronym]).must_be_nil
  end

  it "parses an RI shredout block (9S100)" do
    _(build.index[:"9S100"][:shredouts]).must_equal({D: "ISR Applied Data Science"})
  end

  it "reports the acronym classification (shipped vs excluded) for every candidate" do
    candidates = build.acronym_candidates
    by_code = candidates.to_h { |c| [c[:code], c] }
    _(by_code[:"9M200"][:shipped]).must_equal true
    _(by_code[:"9B100"][:shipped]).must_equal false
  end

  it "counts entries per section" do
    counts = build.section_counts
    _(counts[[:af, :sdi]]).must_equal 2  # 8A200 card + 8G000 ladder
    _(counts[[:af, :ri]]).must_equal 3
    _(counts[[:sf, :sdi]]).must_equal 1
    _(counts[[:sf, :ri]]).must_equal 1
  end

  it "passes the verification gate (0 unverified codes/titles/acronyms)" do
    b = build
    _(b.unverified_codes).must_equal []
    _(b.unverified_titles).must_equal []
    _(b.unverified_acronyms).must_equal []
    _(b.unverified?).must_equal false
  end

  it "exposes a raw-title inventory for the governed de-glue pass" do
    inv = build.title_inventory.to_h { |row| [row[:code], row[:raw_title]] }
    _(inv[:"8A200"]).must_equal "ENLISTEDAIDE"
    _(inv[:"9M200"]).must_equal "International Health Specialists (IHS)"
  end

  it "runs a 1..N sequential completeness check on RI numbers" do
    report = build.sequence_report[:af]
    _(report[:present]).must_equal [8, 26, 33]
    _(report[:duplicates]).must_equal []
  end

  it "flags gaps and duplicates in the sequence" do
    text = <<~TXT
      AIR FORCE REPORTING IDENTIFIERS (RI)
      1. 9A000, First.
      2. 9A100, Second.
      2. 9A200, Duplicate two.
      4. 9A300, Fourth.
    TXT
    report = build(text).sequence_report[:af]
    _(report[:missing]).must_equal [3]
    _(report[:duplicates]).must_equal [2]
  end

  # --- Title de-gluing (verified overrides) --------------------------------
  # Mirrors the AFSC IndexBuilder de-glue gate: an override may change SPACING
  # and CASE only; letter/digit/punctuation drift fails the build. A code with
  # no override keeps its verbatim (glued) title and is reported, not errored.

  it "applies a matching title override and keeps the gate clean (8A200)" do
    b = build(degluer: degluer("8A200": "Enlisted Aide"))
    _(b.index[:"8A200"][:name]).must_equal "Enlisted Aide"
    _(b.unverified_titles).must_be_empty
    _(b.unverified?).must_equal false
    _(b.codes_needing_deglue).wont_include :"8A200"
  end

  it "flags a drifting override that changed letters and refuses to apply it" do
    b = build(degluer: degluer("8A200": "Enlisted Aid"))
    _(b.unverified_titles).wont_be_empty
    _(b.unverified_titles.first[:code]).must_equal :"8A200"
    _(b.unverified?).must_equal true
    # The stale override is NOT silently applied; the verbatim title is retained.
    _(b.index[:"8A200"][:name]).must_equal "Enlistedaide"
  end

  it "keeps the verbatim (glued) title and does not error when no override exists" do
    b = build # default: empty degluer
    _(b.index[:"8A200"][:name]).must_equal "Enlistedaide"
    _(b.codes_needing_deglue).must_include :"8A200"
    _(b.unverified_titles).must_be_empty
    _(b.unverified?).must_equal false
  end

  # --- Bare-format officer SDI cards (no "SDI " prefix) --------------------
  # The officer Air Advisor cards (89A0-89I0) print as a bare "CODE,Title" line
  # with no leading "SDI " keyword. They must still be captured, de-glued via a
  # whitespace-only override, and pass the verification gate.
  let(:officer_bare_text) {
    <<~TXT
      SPECIAL DUTY IDENTIFIERS (SDI)
      89A0,AirAdvisor (Basic)
      89B0,AirAdvisor (Basic) Team Leader
      89C0,AirAdvisor (Basic) Mission Commander
                         OfficerAirAdvisor Basic
                            (Changed 31 Oct 22)
      1. Special Duty Summary. Facilitates functional management.
      89G0, CombatAviationAdvisor
      89H0, CombatAviationAdvisor Team Leader
      89I0, CombatAviationAdvisor Mission Commander
                      Officer CombatAviationAdvisor
                            (Changed 30Apr 25)
      1. Special Duty Summary. Advises.
      REPORTING IDENTIFIERS (RI)
      1. 90G0, General Officer. Use this identifier.
    TXT
  }

  it "captures bare-format officer SDI cards and de-glues them past the gate" do
    deg = degluer(
      "89A0": "Air Advisor (Basic)",
      "89B0": "Air Advisor (Basic) Team Leader",
      "89C0": "Air Advisor (Basic) Mission Commander",
      "89G0": "Combat Aviation Advisor",
      "89H0": "Combat Aviation Advisor Team Leader",
      "89I0": "Combat Aviation Advisor Mission Commander"
    )
    b = build(officer_bare_text, config: GovCodes::Dafecd::RiSdi::Config.dafocd, degluer: deg)
    _(b.index.keys).must_include :"89A0"
    _(b.index.keys).must_include :"89I0"
    _(b.index[:"89A0"][:name]).must_equal "Air Advisor (Basic)"
    _(b.index[:"89A0"][:changed_date]).must_equal "2022-10-31"
    _(b.index[:"89I0"][:name]).must_equal "Combat Aviation Advisor Mission Commander"
    _(b.index[:"89I0"][:changed_date]).must_equal "2025-04-30"
    _(b.unverified?).must_equal false
    _(b.dropped_records).must_equal []
  end

  it "loads the shipped RI/SDI overrides via TitleDegluer.for(config)" do
    loaded = GovCodes::Dafecd::TitleDegluer.for(GovCodes::Dafecd::RiSdi::Config.dafecd)
    _(loaded.override_for(:"8A200")).must_equal "Enlisted Aide"
    officer = GovCodes::Dafecd::TitleDegluer.for(GovCodes::Dafecd::RiSdi::Config.dafocd)
    _(officer.override_for(:"88A0")).must_equal "Aide-de-camp"
  end
end
