# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::Publication do
  # Reference the class under test via a scoped local rather than polluting the
  # top-level namespace with a generic `Publication` constant.
  let(:publication_class) { GovCodes::Dafecd::Publication }

  describe "the enlisted (DAFECD) publication" do
    let(:pub) { publication_class.dafecd }

    it "identifies itself" do
      _(pub.id).must_equal :dafecd
    end

    it "matches the DAFECD running header, not DAFOCD" do
      _("   DAFECD, 31 Oct 25").must_match pub.header
      _("   DAFOCD, 31 Oct 25").wont_match pub.header
    end

    it "matches an enlisted ladder line capturing code and level" do
      m = "AFSC 1A172*, Craftsman".match(pub.ladder)
      _(m[1]).must_equal "1A172"
      _(m[2]).must_equal "Craftsman"
    end

    it "has no bare-code or nothing that matches an officer standalone code" do
      _(pub.bare_code).must_be_nil
    end

    it "recognizes the enlisted CEM line" do
      _("CEM Code 1A100*").must_match pub.cem
    end

    it "keys skill levels under :skill_levels" do
      _(pub.levels_key).must_equal :skill_levels
    end

    it "derives the X-form key by dropping the superintendent and keeping the specific digit" do
      _(pub.specialty_key(%w[1A192 1A172 1A152 1A132 1A112])).must_equal :"1A1X2"
      _(pub.specialty_key(%w[4J090 4J072 4J052 4J032 4J012])).must_equal :"4J0X2"
    end

    it "derives the career field from the basis codes" do
      _(pub.career_field(%w[1A192 1A172 1A152])).must_equal :"1A"
    end
  end

  describe "the officer (DAFOCD) publication" do
    let(:pub) { publication_class.dafocd }

    it "identifies itself" do
      _(pub.id).must_equal :dafocd
    end

    it "matches the DAFOCD running header, not DAFECD" do
      _("   DAFOCD, 31 Oct 25").must_match pub.header
      _("   DAFECD, 31 Oct 25").wont_match pub.header
    end

    it "matches an officer ladder line with a free-form title" do
      m = "AFSC 11B4*, Staff".match(pub.ladder)
      _(m[1]).must_equal "11B4"
      _(m[2]).must_equal "Staff"

      m2 = "AFSC 11B3*,Aircraft Commander".match(pub.ladder)
      _(m2[1]).must_equal "11B3"
      _(m2[2]).must_equal "Aircraft Commander"
    end

    it "does not match a prose AFSC mention (long title, 5-char code)" do
      _("AFSC 11U3X, completion of a current T5 Investigation IAW DoDM").wont_match pub.ladder
      _("AFSC 63A4,Acquisition Manager, identifies staff positions with").wont_match pub.ladder
    end

    # I1: these are REAL DAFOCD source lines (short, 4-char code) that wrapped
    # onto their own line and leaked in as phantom ladder records. The anchor
    # requires the qualification title to start uppercase; both start lowercase.
    it "rejects a wrapped-prose line whose title starts lowercase" do
      _("AFSC 14F3, but applied to developing").wont_match pub.ladder
      _("AFSC 42G3, current and continuous").wont_match pub.ladder
    end

    it "still matches a real qual title that starts uppercase" do
      m = "AFSC 14F3, Qualified".match(pub.ladder)
      _(m[1]).must_equal "14F3"
      _(m[2]).must_equal "Qualified"
    end

    it "matches a suffix-glued officer ladder line (trailing AFSC)" do
      m = "11G4, StaffAFSC".match(pub.ladder)
      _(m[1]).must_equal "11G4"
      _(m[2]).must_equal "Staff"
    end

    it "matches the bare standalone officer code line" do
      m = "AFSC 10C0".match(pub.bare_code)
      _(m[1]).must_equal "10C0"
    end

    it "has no CEM line concept" do
      _(pub.cem).must_be_nil
    end

    it "keys qualification levels under :qual_levels" do
      _(pub.levels_key).must_equal :qual_levels
    end

    it "derives the ladder-family X-form key from a 4-char code" do
      _(pub.specialty_key(%w[11B4 11B3 11B2 11B1])).must_equal :"11BX"
      _(pub.specialty_key(%w[19Z4 19Z3 19Z2 19Z1])).must_equal :"19ZX"
    end

    it "derives the officer career field from the first two digits" do
      _(pub.career_field(%w[11B4 11B3])).must_equal :"11"
      _(pub.career_field(%w[10C0])).must_equal :"10"
    end
  end

  describe ".for" do
    it "looks a publication up by its id symbol or string" do
      _(publication_class.for(:dafecd).id).must_equal :dafecd
      _(publication_class.for("dafocd").id).must_equal :dafocd
    end

    it "raises a clear ArgumentError naming the bad value and valid options" do
      error = _ { publication_class.for(:nope) }.must_raise ArgumentError
      _(error.message).must_include "nope"
      _(error.message).must_include "dafecd"
      _(error.message).must_include "dafocd"
    end
  end

  describe ".detect" do
    it "selects the officer publication from DAFOCD text" do
      _(publication_class.detect("blah\n   DAFOCD, 31 Oct 25\nAFSC 11B4*, Staff").id).must_equal :dafocd
    end

    it "selects the enlisted publication from DAFECD text" do
      _(publication_class.detect("blah\n   DAFECD, 31 Oct 25\nAFSC 1A172*, Craftsman").id).must_equal :dafecd
    end
  end
end
