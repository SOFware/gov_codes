# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "tmpdir"
require "gov_codes/dafecd/shredout_degluer"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::ShredoutDegluer do
  it "returns the clean value map for a covered specialty" do
    degluer = GovCodes::Dafecd::ShredoutDegluer.new("1N1X1": {A: "Imagery Analyst"})
    _(degluer.overrides_for(:"1N1X1")).must_equal({A: "Imagery Analyst"})
  end

  it "returns nil for a specialty with no overrides" do
    degluer = GovCodes::Dafecd::ShredoutDegluer.new("1N1X1": {A: "Imagery Analyst"})
    _(degluer.overrides_for(:"9Z9X9")).must_be_nil
  end

  it "enumerates every (specialty, suffix, value) triple" do
    degluer = GovCodes::Dafecd::ShredoutDegluer.new(
      "1P0X1": {A: "Ejection Seat Aircraft", B: "Non-Ejection Seat Aircraft"}
    )
    triples = []
    degluer.each_override { |spec, suffix, value| triples << [spec, suffix, value] }
    _(triples).must_equal([
      [:"1P0X1", :A, "Ejection Seat Aircraft"],
      [:"1P0X1", :B, "Non-Ejection Seat Aircraft"]
    ])
  end

  it "an empty de-gluer applies no overrides" do
    degluer = GovCodes::Dafecd::ShredoutDegluer.empty
    _(degluer.any?).must_equal false
    _(degluer.overrides_for(:"1N1X1")).must_be_nil
  end

  it "loads nested overrides from a file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "overrides.yml")
      File.write(path, <<~YAML)
        :"1N1X1":
          :A: Imagery Analyst
      YAML
      degluer = GovCodes::Dafecd::ShredoutDegluer.load(path)
      _(degluer.overrides_for(:"1N1X1")).must_equal({A: "Imagery Analyst"})
    end
  end

  it "is empty when the publication's overrides file does not exist" do
    Dir.mktmpdir do |dir|
      # A minimal publication-like double: `for` only needs the overrides path.
      fake_pub = Struct.new(:shredout_overrides_path).new(File.join(dir, "missing.yml"))
      _(GovCodes::Dafecd::ShredoutDegluer.for(fake_pub).any?).must_equal false
    end
  end

  it "loads the shipped per-publication overrides for a publication" do
    degluer = GovCodes::Dafecd::ShredoutDegluer.for(GovCodes::Dafecd::Publication.dafocd)
    _(degluer.overrides_for(:"19ZX")).must_equal({B: "Tactical Air Control Party Officer"})
  end
end
