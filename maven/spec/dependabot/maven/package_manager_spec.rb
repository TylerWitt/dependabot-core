# typed: false
# frozen_string_literal: true

require "dependabot/maven/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Maven::PackageManager do
  subject(:package_manager) { described_class.new }

  describe "#version" do
    it "returns version as nil" do
      expect(package_manager.version).to be_nil
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Maven::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq([])
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq([])
    end
  end
end
