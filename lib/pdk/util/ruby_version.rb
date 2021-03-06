require 'pdk/util'

module PDK
  module Util
    class RubyVersion
      class << self
        extend Forwardable

        def_delegators :instance, :gem_path, :gem_paths_raw, :gem_home, :available_puppet_versions, :bin_path

        # TODO: resolve this
        # rubocop:disable Lint/DuplicateMethods
        attr_reader :instance

        def instance(version = nil)
          use(version) unless version.nil?

          if @instance.nil?
            @instance = {}
            @instance.default_proc = proc do |hash, key|
              hash[key] = new(key)
            end
          end
          @instance[active_ruby_version]
        end
        # rubocop:enable Lint/DuplicateMethods

        def active_ruby_version
          @active_ruby_version || default_ruby_version
        end

        def use(version)
          if versions.key?(version)
            @active_ruby_version = version
          else
            raise ArgumentError, _('Unknown Ruby version "%{ruby_version}"') % {
              ruby_version: version,
            }
          end
        end

        def scan_for_packaged_rubies
          ruby_basedir = File.join(PDK::Util.pdk_package_basedir, 'private', 'ruby', '*')
          Dir[ruby_basedir].sort.map { |ruby_dir|
            version = File.basename(ruby_dir)
            [version, version.split('.').take(2).concat(['0']).join('.')]
          }.reverse.to_h
        end

        def default_ruby_version
          @default_ruby_version ||= if PDK::Util.package_install?
                                      # Default to the ruby that supports the latest puppet gem. If you wish to default to a
                                      # specific Puppet Gem version use the following example;
                                      #
                                      # PDK::Util::PuppetVersion.find_gem_for('5.5.10')[:ruby_version]
                                      #
                                      PDK::Util::PuppetVersion.latest_available[:ruby_version]
                                    else
                                      # TODO: may not be a safe assumption that highest available version should be default
                                      # WARNING Do NOT use PDK::Util::PuppetVersion.*** methods as it can recurse into this
                                      # method and cause Stack Level Too Deep errors.
                                      latest_ruby_version
                                    end
        end

        def latest_ruby_version
          versions.keys.sort { |a, b| Gem::Version.new(b) <=> Gem::Version.new(a) }.first
        end

        def versions
          @versions ||= if PDK::Util.package_install?
                          scan_for_packaged_rubies
                        else
                          { RbConfig::CONFIG['RUBY_PROGRAM_VERSION'] => RbConfig::CONFIG['ruby_version'] }
                        end
        end
      end

      attr_reader :ruby_version

      def initialize(ruby_version = nil)
        @ruby_version = ruby_version || default_ruby_version
      end

      def bin_path
        if PDK::Util.package_install?
          File.join(PDK::Util.pdk_package_basedir, 'private', 'ruby', ruby_version, 'bin')
        else
          RbConfig::CONFIG['bindir']
        end
      end

      def gem_paths_raw
        if PDK::Util.package_install?
          # Subprocesses use their own set of gems which are managed by pdk or
          # installed with the package. We also include the separate gem path
          # where our packaged multi-puppet installations live.
          [
            File.join(PDK::Util.pdk_package_basedir, 'private', 'ruby', ruby_version, 'lib', 'ruby', 'gems', versions[ruby_version]),
            File.join(PDK::Util.package_cachedir, 'ruby', versions[ruby_version]),
            File.join(PDK::Util.pdk_package_basedir, 'private', 'puppet', 'ruby', versions[ruby_version]),
          ]
        else
          # This allows the subprocess to find the 'bundler' gem, which isn't
          # in GEM_HOME for gem installs.
          # TODO: There must be a better way to do this than shelling out to
          # gem... Perhaps can be replaced with "Gem.path"?
          [File.absolute_path(File.join(`gem which bundler`, '..', '..', '..', '..'))]
        end
      end

      def gem_path
        gem_paths_raw.join(File::PATH_SEPARATOR)
      end

      def gem_home
        # `bundle install --path` ignores all "system" installed gems and
        # causes unnecessary package installs. `bundle install` (without
        # --path) installs into GEM_HOME, which by default is non-user
        # writeable.
        # To still use the pre-installed packages, but allow folks to install
        # additional gems, we set GEM_HOME to the user's cachedir and put all
        # other cache locations onto GEM_PATH.
        # See https://stackoverflow.com/a/11277228 for background
        File.join(PDK::Util.cachedir, 'ruby', versions[ruby_version])
      end

      def available_puppet_versions
        return @available_puppet_versions unless @available_puppet_versions.nil?

        puppet_spec_files = Dir[File.join(gem_home, 'specifications', '**', 'puppet*.gemspec')]

        gem_path.split(File::PATH_SEPARATOR).each do |path|
          puppet_spec_files += Dir[File.join(path, 'specifications', '**', 'puppet*.gemspec')]
        end

        puppet_specs = []

        puppet_spec_files.each do |specfile|
          spec = Gem::Specification.load(specfile)
          puppet_specs << spec if spec.name == 'puppet'
        end

        @available_puppet_versions = puppet_specs.map(&:version).sort { |a, b| b <=> a }
      end

      private

      def default_ruby_version
        self.class.default_ruby_version
      end

      def versions
        self.class.versions
      end
    end
  end
end
