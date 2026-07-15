# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/shredout_acronyms"

describe GovCodes::Dafecd::ShredoutAcronyms do
  # Reference the module under test via a scoped local rather than polluting the
  # top-level namespace with a generic `Acronyms` constant.
  let(:acronyms) { GovCodes::Dafecd::ShredoutAcronyms }

  describe ".from_table" do
    it "lifts the trailing acronym from a shredout meaning" do
      shredouts = {U: "Air Liaison Officer (ALO)", Y: "General", A: "B-1"}
      _(acronyms.from_table(shredouts)).must_equal({U: "ALO"})
    end

    it "captures multiple trailing acronyms" do
      shredouts = {F: "Magnetic Resonance Imaging (MRI)", M: "Trainer (UABMT)"}
      _(acronyms.from_table(shredouts)).must_equal({F: "MRI", M: "UABMT"})
    end

    it "ignores a meaning with no trailing parenthetical" do
      _(acronyms.from_table({A: "B-52", Z: "Other"})).must_be_empty
    end
  end

  describe ".from_enumeration" do
    let(:record) {
      <<~TXT
        5.719ZXA(Special Tactics Officer (STO)) - global access.
        5.819ZXB (Tactical Air Control Party Officer (TACPO)) - strike.
        5.919ZXC (Combat Rescue Officer (CRO)) - recovery.
      TXT
    }

    it "extracts shred letter => acronym for the record's own family" do
      _(acronyms.from_enumeration(record, "19Z")).must_equal({A: "STO", B: "TACPO", C: "CRO"})
    end

    it "returns nothing for a family that does not appear" do
      _(acronyms.from_enumeration(record, "11B")).must_be_empty
    end

    it "returns nothing for a blank family" do
      _(acronyms.from_enumeration(record, "")).must_be_empty
    end
  end
end
