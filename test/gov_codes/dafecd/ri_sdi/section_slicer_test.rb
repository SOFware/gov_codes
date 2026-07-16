# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/section_slicer"
require "gov_codes/dafecd/ri_sdi/config"

describe GovCodes::Dafecd::RiSdi::SectionSlicer do
  def slice(text, config: GovCodes::Dafecd::RiSdi::Config.dafecd)
    GovCodes::Dafecd::RiSdi::SectionSlicer.new(text, config: config).sections
  end

  it "slices the enlisted directory into AF SDI, AF RI, SF SDI, SF RI (skipping SFSC)" do
    text = <<~TXT
      TABLE OF CONTENTS
       SPECIALDUTY IDENTIFIERS ................ 304
      SPECIALDUTY IDENTIFIERS (SDI)
      SDI 8A200 body af sdi
      AIR FORCE REPORTING IDENTIFIERS (RI)
      1. 9A000, af ri body
      SPACE FORCE SPECIALTY CODES (SFSC)
      sfsc body should be skipped
      SPACE FORCE SPECIALDUTY IDENTIFIERS (SDI)
      SDI 8B400 sf sdi body
      SPACE FORCE REPORTING IDENTIFIERS (RI)
      1.9S000, sf ri body
    TXT
    sections = slice(text)
    _(sections.map { |s| [s.force, s.kind] }).must_equal [
      [:af, :sdi], [:af, :ri], [:sf, :sdi], [:sf, :ri]
    ]
    _(sections[0].text).must_match(/SDI 8A200/)
    _(sections[0].text).wont_match(/AIR FORCE REPORTING/) # bounded at next header
    _(sections[1].text).must_match(/9A000/)
    _(sections[1].text).wont_match(/sfsc body/) # AF RI ends at SFSC
    _(sections[2].text).must_match(/SDI 8B400/)
    _(sections[2].text).wont_match(/9S000/)
    _(sections[3].text).must_match(/9S000/)
    _(sections.map(&:text).join).wont_match(/sfsc body should be skipped/)
  end

  it "does not match the table-of-contents entries (no parenthetical)" do
    text = <<~TXT
       SPECIALDUTY IDENTIFIERS ................ 304
      SPECIALDUTY IDENTIFIERS (SDI)
      real section body
      AIR FORCE REPORTING IDENTIFIERS (RI)
      ri body
    TXT
    sections = slice(text)
    _(sections.first.text).must_match(/real section body/)
    _(sections.first.text).wont_match(/\.\.\.\.\.\.\.\./)
  end

  it "slices the officer directory into SDI then RI" do
    text = <<~TXT
      SPECIALDUTY IDENTIFIERS (SDI)
      SDI 80C0 officer sdi body
      REPORTING IDENTIFIERS (RI)
      1. 90G0 officer ri body
    TXT
    sections = slice(text, config: GovCodes::Dafecd::RiSdi::Config.dafocd)
    _(sections.map { |s| [s.force, s.kind] }).must_equal [[:officer, :sdi], [:officer, :ri]]
    _(sections[0].text).must_match(/SDI 80C0/)
    _(sections[0].text).wont_match(/90G0/)
    _(sections[1].text).must_match(/90G0/)
  end
end
