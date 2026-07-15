# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/shredout_parser"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::ShredoutParser do
  # Real two-column shredout table from the 31 Oct 25 DAFECD (1A1X2).
  let(:table) {
    <<~TXT
      4. *Specialty Shredouts:
         Suffix     Primary Aircraft                   Suffix    Primary Aircraft

            A       C-5 Flight Engineer                   L      C-130H Flight Engineer
            B       C-5 Loadmaster                        N      C-130H Loadmaster

            C       C-17 Loadmaster                       O      EC-130H Flight Engineer
            D       C-130J Loadmaster                     P      LC-130H Loadmaster

            E       WC-130 Loadmaster                     Q      LC-130H Flight Engineer
            F       E-3 Flight Engineer                   Y      General

            G       KC-46 Boom Operator                   Z      Data Mask Mobility Force
                                                                 Aviator
            H       KC-135 Boom Operator
      *NOTE: Y- General shred will be utilized with CFM oversight and approval.
    TXT
  }

  it "parses left-column suffix/name pairs" do
    result = GovCodes::Dafecd::ShredoutParser.new(table).parse
    _(result[:A]).must_equal "C-5 Flight Engineer"
    _(result[:B]).must_equal "C-5 Loadmaster"
    _(result[:G]).must_equal "KC-46 Boom Operator"
    _(result[:Y]).must_equal "General"
  end

  it "parses right-column suffix/name pairs from the interleave" do
    result = GovCodes::Dafecd::ShredoutParser.new(table).parse
    _(result[:L]).must_equal "C-130H Flight Engineer"
    _(result[:N]).must_equal "C-130H Loadmaster"
    _(result[:O]).must_equal "EC-130H Flight Engineer"
    _(result[:Q]).must_equal "LC-130H Flight Engineer"
  end

  it "captures both columns of the A…L, B…N interleave" do
    result = GovCodes::Dafecd::ShredoutParser.new(table).parse
    _(result.keys).must_include :A
    _(result.keys).must_include :L
    _(result.keys).must_include :B
    _(result.keys).must_include :N
  end

  it "does not emit spurious suffixes from the note line" do
    result = GovCodes::Dafecd::ShredoutParser.new(table).parse
    # "*NOTE: Y- General shred..." must not overwrite the real Y or add junk.
    _(result[:Y]).must_equal "General"
    _(result.size).must_equal 15
  end

  it "ignores decorative symbol glyphs embedded between columns" do
    # In the real 1A1X2 table a Private Use Area glyph (U+F0EA) sits in the gap
    # after "E-3 Flight Engineer", which otherwise breaks the column lookahead
    # and drops the F suffix.
    pua = "\u{F0EA}"
    tbl = <<~TXT
      Suffix     Primary Aircraft            Suffix    Primary Aircraft
         E       WC-130 Loadmaster              Q      LC-130H Flight Engineer
         F       E-3 Flight Engineer   #{pua}          Y      General
    TXT
    result = GovCodes::Dafecd::ShredoutParser.new(tbl).parse
    _(result[:F]).must_equal "E-3 Flight Engineer"
    _(result[:Y]).must_equal "General"
  end

  it "returns an empty hash when there is no shredout table" do
    result = GovCodes::Dafecd::ShredoutParser.new("1. Specialty Summary. Nothing here.").parse
    _(result).must_be_empty
  end

  describe "the officer (DAFOCD) publication" do
    let(:officer) { GovCodes::Dafecd::Publication.dafocd }

    # Real two-column officer shredout table from the 31 Oct 25 DAFOCD (11B).
    let(:table) {
      <<~TXT
        4. *Specialty Shredouts:

         Suffix      Portion of AFS to Which Related                             Suffix          Portion of AFS to Which Related

         A               B-1                                                     U               Air Liaison Officer (ALO)
         B               B-2                                                     Y               General

         C               B-52                                                    Z               Other
         D               B-21
      TXT
    }

    it "parses both columns of the officer 'Portion of AFS' table" do
      result = GovCodes::Dafecd::ShredoutParser.new(table, publication: officer).parse
      _(result[:A]).must_equal "B-1"
      _(result[:D]).must_equal "B-21"
      _(result[:U]).must_equal "Air Liaison Officer (ALO)"
      _(result[:Y]).must_equal "General"
      _(result[:Z]).must_equal "Other"
    end
  end
end
