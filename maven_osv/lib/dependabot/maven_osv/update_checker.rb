# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/maven_osv/file_parser/property_value_finder"

module Dependabot
  module MavenOSV
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"
      require_relative "update_checker/property_updater"
      require_relative "utils/osv_scanner"

      def latest_version
        latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        # Maven's version resolution algorithm is very simple: it just uses
        # the version defined "closest", with the first declaration winning
        # if two declarations are equally close. As a result, we can just
        # return that latest version unless dealing with a property dep.
        # https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Transitive_Dependencies
        return nil if version_comes_from_multi_dependency_property?

        latest_version
      end

      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Maven has a single dependency file (the pom.xml).
        #
        # For completeness we ought to resolve the pom.xml and return the
        # latest version that satisfies the current constraint AND any
        # constraints placed on it by other dependencies. Seeing as we're
        # never going to take any action as a result, though, we just return
        # nil.
        nil
      end

      def updated_requirements
        property_names =
          declarations_using_a_property
          .map { |req| req.dig(:metadata, :property_name) }

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url),
          properties_to_update: property_names
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        declarations_using_a_property.none? do |requirement|
          prop_name = requirement.dig(:metadata, :property_name)
          pom = dependency_files.find { |f| f.name == requirement[:file] }

          declaration_pom_name =
            property_value_finder
            .property_details(property_name: prop_name, callsite_pom: pom)
            &.fetch(:file)

          declaration_pom_name == "remote_pom.xml"
        end
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pomfiles
        @pomfiles ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?(".xml") && !f.name.end_with?("extensions.xml")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      def latest_version_resolvable_with_full_unlock?
        return false unless version_comes_from_multi_dependency_property?

        property_updater.update_possible?
      end

      def updated_dependencies_after_full_unlock
        property_updater.updated_dependencies
      end

      def numeric_version_up_to_date?
        return false unless version_class.correct?(dependency.version)

        super
      end

      def numeric_version_can_update?(requirements_to_unlock:)
        return false unless version_class.correct?(dependency.version)

        super
      end

      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      def latest_version_details
        return @latest_version_details if defined?(@latest_version_details)

        @latest_version_details = version_finder.versions.find { |v| v.fetch(:version) == osv_updated_version }
      end

      def lowest_security_fix_version_details
        return @lowest_security_fix_version_details if defined?(@lowest_security_fix_version_details)

        @lowest_security_fix_version_details =
          version_finder.versions.find { |v| v.fetch(:version) == osv_updated_version }
      end

      def osv_updated_version
        return @osv_updated_version if defined?(@osv_updated_version)

        @osv_updated_version = begin
          pomfile = pomfiles.find do |f|
            File.dirname(File.join(repo_contents_path, f.realpath)) == dependency.directory
          end
          return unless pomfile

          pomfile_path = File.join(repo_contents_path, pomfile.realpath)
          Utils::OSVScanner.fix(pomfile_path:)

          source = Utils::SourceFinder.from_repo(repo_contents_path:)
          updated_dependency_files = MavenOSV::FileFetcher.new(
            source:,
            credentials:,
            repo_contents_path:
          ).files
          dependencies = MavenOSV::FileParser.new(
            dependency_files: updated_dependency_files,
            repo_contents_path:,
            source:
          ).parse

          updated_dependency = dependencies.find do |d|
            d.name == dependency.name && d.directory == dependency.directory
          end
          return unless updated_dependency && version_class.correct?(updated_dependency.version)

          version_class.new(updated_dependency.version)
        end
      end

      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
      end

      def property_updater
        @property_updater ||=
          PropertyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            target_version_details: latest_version_details,
            credentials: credentials,
            ignored_versions: ignored_versions
          )
      end

      def property_value_finder
        @property_value_finder ||=
          MavenOSV::FileParser::PropertyValueFinder
          .new(dependency_files: dependency_files, credentials: credentials.map(&:to_s))
      end

      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = requirement.fetch(:metadata).fetch(:property_name)
          property_source = requirement.fetch(:metadata)
                                       .fetch(:property_source)

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              next unless req.dig(:metadata, :property_name) == property_name

              req.dig(:metadata, :property_source) == property_source
            end
          end
        end
      end

      def declarations_using_a_property
        @declarations_using_a_property ||=
          dependency.requirements
                    .select { |req| req.dig(:metadata, :property_name) }
      end

      def all_property_based_dependencies
        @all_property_based_dependencies ||=
          MavenOSV::FileParser.new(
            dependency_files: dependency_files,
            source: nil
          ).parse.select do |dep|
            dep.requirements.any? { |req| req.dig(:metadata, :property_name) }
          end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("maven_osv", Dependabot::MavenOSV::UpdateChecker)
