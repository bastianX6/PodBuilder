require 'pod_builder/cocoapods/specification'

module PodBuilder
  class PodfileItem
    # @return [String] The git repo
    #
    attr_reader :repo

    # @return [String] The git branch
    #
    attr_reader :branch

    # @return [String] Matches @name unless for subspecs were it stores the name of the root pod
    #
    attr_reader :root_name

    # @return [String] The name of the pod, which might be the subspec name if appicable
    #
    attr_reader :name
    
    # @return [String] The pinned tag of the pod, if any
    #
    attr_reader :tag

    # @return [String] The pinned version of the pod, if any
    #
    attr_reader :version

    # @return Array<[String]> The available versions of the pod
    #
    attr_reader :available_versions

    # @return [String] Local path, if any
    #
    attr_accessor :path

    # @return [String] The pinned commit of the pod, if any
    #
    attr_reader :commit
    
    # @return [String] The module name
    #
    attr_reader :module_name
    
    # @return [String] The swift version if applicable
    #
    attr_reader :swift_version
    
    # @return [Array<String>] The pod's dependency names, if any. Use dependencies() to get the [Array<PodfileItem>]
    #
    attr_reader :dependency_names
    
    # @return [Bool] True if the pod is shipped as a static framework
    #
    attr_reader :is_static
    
    # @return [Array<Hash>] The pod's xcconfig configuration
    #
    attr_reader :xcconfig

    # @return [Bool] Is external pod
    #
    attr_accessor :is_external

    # @return [String] The pod's build configuration
    #
    attr_accessor :build_configuration

    # @return [String] The pod's vendored items (frameworks and libraries)
    #
    attr_accessor :vendored_items

    # @return [String] Framweworks the pod needs to link to
    #
    attr_accessor :frameworks

    # @return [String] Weak framweworks the pod needs to link to
    #
    attr_accessor :weak_frameworks

    # @return [String] Libraries the pod needs to link to
    #
    attr_accessor :libraries

    # @return [Bool] Returns true if the source_files key is present
    #
    attr_accessor :has_source_files_key

    # Initialize a new instance
    #
    # @param [Specification] spec
    #
    # @param [Hash] checkout_options
    #
    def initialize(spec, all_specs, checkout_options)
      if overrides = Configuration.spec_overrides[spec.name]
        overrides.each do |k, v|
          spec.root.attributes_hash[k] = v
          if checkout_options.has_key?(spec.name)
            checkout_options[spec.name][k] = v
          end
        end
      end

      @name = spec.name
      @root_name = spec.name.split("/").first

      checkout_options_keys = [@name, @root_name]

      if opts_key = checkout_options_keys.detect { |x| checkout_options.has_key?(x) }
        @repo = checkout_options[opts_key][:git]
        @tag = checkout_options[opts_key][:tag]
        @commit = checkout_options[opts_key][:commit]
        @path = checkout_options[opts_key][:path]
        @branch = checkout_options[opts_key][:branch]
        @is_external = true
      else
        @repo = spec.root.source[:git]
        @tag = spec.root.source[:tag]
        @commit = spec.root.source[:commit]
        @is_external = false
      end    

      @vendored_items = recursive_vendored_items(spec)

      @frameworks = []
      @frameworks += extract_array(spec, "framework")
      @frameworks += extract_array(spec, "frameworks")
      @frameworks += extract_array(spec.root, "framework")
      @frameworks += extract_array(spec.root, "frameworks")

      @weak_frameworks = []
      @weak_frameworks += extract_array(spec, "weak_frameworks")
      @weak_frameworks += extract_array(spec, "weak_frameworks")
      @weak_frameworks += extract_array(spec.root, "weak_frameworks")
      @weak_frameworks += extract_array(spec.root, "weak_frameworks")

      @libraries = []
      @libraries += extract_array(spec, "library")
      @libraries += extract_array(spec, "libraries")
      @libraries += extract_array(spec.root, "library")
      @libraries += extract_array(spec.root, "libraries")

      @version = spec.root.version.version
      @available_versions = spec.respond_to?(:spec_source) ? spec.spec_source.versions(@root_name)&.map(&:to_s) : [@version]
      
      @swift_version = spec.root.swift_version&.to_s
      @module_name = spec.root.module_name

      @dependency_names = spec.recursive_dep_names(all_specs)

      @is_static = spec.root.attributes_hash["static_framework"] || false
      @xcconfig = spec.root.attributes_hash["xcconfig"] || {}

      @has_source_files_key = spec.root.attributes_hash.has_key?("source_files") || spec.attributes_hash.has_key?("source_files")
      
      @build_configuration = spec.root.attributes_hash.dig("pod_target_xcconfig", "prebuild_configuration") || "release"
      @build_configuration.downcase!
    end

    def pod_specification(all_poditems, parent_spec = nil)
      spec_raw = {}

      spec_raw["name"] = @name
      spec_raw["module_name"] = @module_name

      spec_raw["source"] = {}
      if repo = @repo
        spec_raw["source"]["git"] = repo
      end
      if tag = @tag
        spec_raw["source"]["tag"] = tag
      end
      if commit = @commit
        spec_raw["source"]["commit"] = commit
      end

      spec_raw["version"] = @version
      if swift_version = @swift_version
        spec_raw["swift_version"] = swift_version
      end

      spec_raw["static_framework"] = is_static

      spec_raw["frameworks"] = @frameworks
      spec_raw["libraries"] = @libraries

      spec_raw["xcconfig"] = @xcconfig

      spec_raw["dependencies"] = @dependency_names.map { |x| [x, []] }.to_h

      spec = Pod::Specification.from_hash(spec_raw, parent_spec)   
      all_subspec_items = all_poditems.select { |x| x.is_subspec && x.root_name == @name }
      spec.subspecs = all_subspec_items.map { |x| x.pod_specification(all_poditems, spec) }

      return spec
    end
    
    def inspect
      return "#{@name} repo=#{@repo} pinned=#{@tag || @commit} is_static=#{@is_static} deps=#{@dependencies || "[]"}"
    end

    def to_s
      return @name
    end

    def dependencies(available_pods)
      return available_pods.select { |x| @dependency_names.include?(x.name) }
    end

    # @return [Bool] True if it's a pod that doesn't provide source code (is already shipped as a prebuilt pod)
    #    
    def is_prebuilt
      # We treat pods to skip like prebuilt ones
      if Configuration.skip_pods.include?(@root_name) || Configuration.skip_pods.include?(@name)
        return true
      end

      # checking if there's a vendored_item matching the module name is a pretty good guess for a prebuilt pod.
      # Still suboptimal, maybe it should be more appropriate to use FileAccessor and check that no source code is provided (no *.{m,mm,c,cpp,swift, etc})
      if vendored_items.map { |x| File.basename(x) }.include?("#{@module_name}.framework")
        return true
      else
        return !@has_source_files_key && @vendored_items.count > 0
      end
    end

    # @return [Bool] True if it's a subspec
    #
    def is_subspec
      @root_name != @name
    end

    # @return [String] The podfile entry
    #
    def entry(include_version = true, include_pb_entry = true)
      e = "pod '#{@name}'"

      unless include_version
        return e
      end

      if is_external
        if @path
          e += ", :path => '#{@path}'"  
        else
          if @repo
            e += ", :git => '#{@repo}'"  
          end
          if @tag
            e += ", :tag => '#{@tag}'"
          end
          if @commit
            e += ", :commit => '#{@commit}'"  
          end
          if @branch
            e += ", :branch => '#{@branch}'"  
          end
        end
      else
        e += ", '=#{@version}'"  
      end

      if include_pb_entry
        e += " # pb<#{name}>"
      end

      return e
    end

    def podspec_name
      return name.gsub("/", "_")
    end

    def prebuilt_rel_path
      if is_subspec && Configuration.subspecs_to_split.include?(name)
        return "#{name}/#{module_name}.framework"
      else
        return "#{module_name}.framework"
      end
    end

    def prebuilt_entry(include_pb_entry = true)
      relative_path = Pathname.new(Configuration.base_path).relative_path_from(Pathname.new(PodBuilder::project_path)).to_s
      if Configuration.subspecs_to_split.include?(name)
        entry = "pod 'PodBuilder/#{podspec_name}', :path => '#{relative_path}'"
      else
        entry = "pod 'PodBuilder/#{root_name}', :path => '#{relative_path}'"
      end

      if include_pb_entry
        entry += " # pb<#{name}>"
      end

      return entry
    end

    def has_subspec(named)
      unless !is_subspec
        return false
      end

      return named.split("/").first == name
    end

    def has_common_spec(named)
      return root_name == named.split("/").first
    end

    def git_hard_checkout
      prefix = "git fetch --all --tags --prune; git reset --hard"
      if @tag
        return "#{prefix} tags/#{@tag}"
      end
      if @commit
        return "#{prefix} #{@commit}"
      end
      if @branch
        return "#{prefix} origin/#{@branch}"
      end

      return nil
    end

    private

    def recursive_vendored_items(spec)
      items = []

      items += [spec.root.attributes_hash["vendored_frameworks"]]
      items += [spec.root.attributes_hash["vendored_framework"]]
      items += [spec.root.attributes_hash["vendored_libraries"]]
      items += [spec.root.attributes_hash["vendored_library"]]

      items += [spec.attributes_hash["vendored_frameworks"]]
      items += [spec.attributes_hash["vendored_framework"]]
      items += [spec.attributes_hash["vendored_libraries"]]
      items += [spec.attributes_hash["vendored_library"]]

      supported_platforms = spec.available_platforms.flatten.map(&:name).map(&:to_s)

      items += supported_platforms.map { |x| spec.root.attributes_hash.fetch(x, {})["vendored_frameworks"] }
      items += supported_platforms.map { |x| spec.root.attributes_hash.fetch(x, {})["vendored_framework"] }
      items += supported_platforms.map { |x| spec.root.attributes_hash.fetch(x, {})["vendored_libraries"] }
      items += supported_platforms.map { |x| spec.root.attributes_hash.fetch(x, {})["vendored_library"] }

      items += supported_platforms.map { |x| spec.attributes_hash.fetch(x, {})["vendored_frameworks"] }
      items += supported_platforms.map { |x| spec.attributes_hash.fetch(x, {})["vendored_framework"] }
      items += supported_platforms.map { |x| spec.attributes_hash.fetch(x, {})["vendored_libraries"] }
      items += supported_platforms.map { |x| spec.attributes_hash.fetch(x, {})["vendored_library"] }

      items = items.flatten.compact

      return items.flatten
    end

    def extract_array(spec, key)
      element = spec.attributes_hash.fetch(key, [])
      if element.instance_of? String
        element = [element]
      end

      return element
    end
  end
end
