# typed: true
# frozen_string_literal: true

module Dependabot
  module Bun
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class ConflictingDependencyResolver
        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials = credentials
        end

        # Finds any dependencies in the `yarn.lock` or `package-lock.json` that
        # have a subdependency on the given dependency that does not satisfly
        # the target_version.
        #
        # @param dependency [Dependabot::Dependency] the dependency to check
        # @param target_version [String] the version to check
        # @return [Array<Hash{String => String}]
        #   * name [String] the blocking dependencies name
        #   * version [String] the version of the blocking dependency
        #   * requirement [String] the requirement on the target_dependency
        def conflicting_dependencies(dependency:, target_version:)
          SharedHelpers.in_a_temporary_directory do
            dependency_files_builder = DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            )
            dependency_files_builder.write_temporary_dependency_files

            # TODO: Look into using npm/arborist for parsing yarn lockfiles (there's currently partial yarn support)
            #
            # Prefer the npm conflicting dependency parser if there's both a npm lockfile and a yarn.lock file as the
            # npm parser handles edge cases where the package.json is out of sync with the lockfile, something the yarn
            # parser doesn't deal with at the moment.
            if dependency_files_builder.lockfiles.any?
              SharedHelpers.run_helper_subprocess(
                command: Javascript::NativeHelpers.helper_path,
                function: "npm:findConflictingDependencies",
                args: [Dir.pwd, dependency.name, target_version.to_s]
              )
            else
              SharedHelpers.run_helper_subprocess(
                command: Javascript::NativeHelpers.helper_path,
                function: "yarn:findConflictingDependencies",
                args: [Dir.pwd, dependency.name, target_version.to_s]
              )
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed
          []
        end

        private

        attr_reader :dependency_files
        attr_reader :credentials
      end
    end
  end
end
