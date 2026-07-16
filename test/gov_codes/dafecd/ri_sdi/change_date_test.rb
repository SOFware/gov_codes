# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/ri_sdi/change_date"

describe GovCodes::Dafecd::RiSdi::ChangeDate do
  def extract(text)
    GovCodes::Dafecd::RiSdi::ChangeDate.extract(text)
  end

  it "parses the plain enlisted form" do
    _(extract("(Changed 31 Oct 25)")).must_equal "2025-10-31"
  end

  it "parses Established / Effective keywords" do
    _(extract("(Established 31 Oct 21)")).must_equal "2021-10-31"
    _(extract("(Effective 12Aug 13)")).must_equal "2013-08-12"
  end

  it "parses a glued day/month" do
    _(extract("(Established 30Apr 25)")).must_equal "2025-04-30"
    _(extract("(Effective 30Apr 22)")).must_equal "2022-04-30"
  end

  it "parses a fully glued day/month/year (officer 81D0)" do
    _(extract("(Established 30Apr20)")).must_equal "2020-04-30"
  end

  it "captures the FIRST date of a dual-date annotation" do
    _(extract("(Changed 31 Oct 16, Effective 8 Feb 16)")).must_equal "2016-10-31"
  end

  it "tolerates a leading extra word before the date" do
    _(extract("(Change Effective 31 Oct 18)")).must_equal "2018-10-31"
    _(extract("(Established Effective 31 Oct 22)")).must_equal "2022-10-31"
    _(extract("(Established effective 31 Oct 21).")).must_equal "2021-10-31"
  end

  it "tolerates a long leading clause with a lowercase 'effective'" do
    _(extract("(Change to description only effective 11 May 15)")).must_equal "2015-05-11"
    _(extract("(Change to specialty description only effective 11 May 15)")).must_equal "2015-05-11"
  end

  it "tolerates a missing/misplaced open paren (pdf glue)" do
    _(extract("Established 31 Oct 25   )")).must_equal "2025-10-31"
  end

  it "parses a spelled-out month and a 4-digit year" do
    _(extract("(Effective 5 June 2013)")).must_equal "2013-06-05"
    _(extract("(Effective 20Apr 15)")).must_equal "2015-04-20"
  end

  it "returns nil when there is no change-date annotation" do
    _(extract("1. Special Duty Summary. Performs tasks.")).must_be_nil
    _(extract("")).must_be_nil
  end

  it "does not treat an unrelated numeric mention as a date" do
    _(extract("For award and retention, see AFMAN 16-1405 for guidance.")).must_be_nil
  end
end
