# frozen_string_literal: true

require "test_helper"
require "minitest/autorun"
require "gov_codes/dafecd/title_degluer"
require "gov_codes/dafecd/publication"

describe GovCodes::Dafecd::TitleDegluer do
  let(:degluer) {
    GovCodes::Dafecd::TitleDegluer.new(
      "1A1X2": "Mobility Force Aviator",
      "1Z3X1": "Tactical Air Control Party (TACP)"
    )
  }

  it "returns the clean override for a known specialty" do
    _(degluer.override_for(:"1A1X2")).must_equal "Mobility Force Aviator"
  end

  it "returns nil for a specialty with no override" do
    _(degluer.override_for(:"9Z9X9")).must_be_nil
  end

  it "normalizes by stripping all whitespace and downcasing" do
    _(GovCodes::Dafecd::TitleDegluer.norm("Mobility Force Aviator")).must_equal "mobilityforceaviator"
    _(GovCodes::Dafecd::TitleDegluer.norm("MOBILITY  FORCEAVIATOR")).must_equal "mobilityforceaviator"
  end

  it "accepts an override that differs from source only in spacing and case" do
    _(GovCodes::Dafecd::TitleDegluer.matches_source?("Mobility Force Aviator", "MOBILITY FORCEAVIATOR")).must_equal true
  end

  it "rejects an override that changes a letter" do
    _(GovCodes::Dafecd::TitleDegluer.matches_source?("Mobility Force Aviatorr", "MOBILITY FORCEAVIATOR")).must_equal false
    _(GovCodes::Dafecd::TitleDegluer.matches_source?("Mobility Naval Aviator", "MOBILITY FORCEAVIATOR")).must_equal false
  end

  it "rejects when there is no raw source title to compare against" do
    _(GovCodes::Dafecd::TitleDegluer.matches_source?("Anything", nil)).must_equal false
  end

  it "loads the shipped overrides file with symbol keys" do
    loaded = GovCodes::Dafecd::TitleDegluer.load
    _(loaded.override_for(:"1A1X2")).must_equal "Mobility Force Aviator"
    _(loaded.override_for(:"1C3X1")).must_equal "All-Domain Command and Control Operations"
  end

  describe ".for a publication" do
    it "loads the enlisted overrides for the enlisted publication" do
      loaded = GovCodes::Dafecd::TitleDegluer.for(GovCodes::Dafecd::Publication.dafecd)
      _(loaded.override_for(:"1A1X2")).must_equal "Mobility Force Aviator"
    end

    it "loads the officer overrides file for the officer publication" do
      loaded = GovCodes::Dafecd::TitleDegluer.for(GovCodes::Dafecd::Publication.dafocd)
      _(loaded).must_be_instance_of GovCodes::Dafecd::TitleDegluer
    end
  end
end
