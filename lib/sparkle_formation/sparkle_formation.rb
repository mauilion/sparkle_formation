#
# Author:: Chris Roberts <chris@hw-ops.com>
# Copyright:: 2013, Heavy Water Operations, LLC
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'sparkle_formation'

SparkleFormation::SparkleStruct.camel_keys = true

# Formation container
class SparkleFormation

  include SparkleFormation::Utils::AnimalStrings
  # @!parse include SparkleFormation::Utils::AnimalStrings
  extend SparkleFormation::Utils::AnimalStrings
  # @!parse extend SparkleFormation::Utils::AnimalStrings

  # @return [Array<String>] directory names to ignore
  IGNORE_DIRECTORIES = [
    'components',
    'dynamics',
    'registry'
  ]

  class << self

    # @return [Hashish] loaded dynamics
    def dynamics
      @dynamics ||= SparkleStruct.hashish.new
    end

    # @return [Hashish] custom paths
    def custom_paths
      @_paths ||= SparkleStruct.hashish.new
      @_paths
    end

    # Get/set path to sparkle directory
    #
    # @param path [String] path to directory
    # @return [String] path to directory
    def sparkle_path=(path=nil)
      if(path)
        custom_paths[:sparkle_path] = path
        custom_paths[:components_directory] ||= File.join(path, 'components')
        custom_paths[:dynamics_directory] ||= File.join(path, 'dynamics')
        custom_paths[:registry_directory] ||= File.join(path, 'registry')
      end
      custom_paths[:sparkle_path]
    end
    alias_method(:sparkle_path, :sparkle_path=)

    # Get/set path to component files
    #
    # @param path [String] path to component files
    # @return [String] path to component files
    def components_path=(path=nil)
      if(path)
        custom_paths[:components_directory] = path
      end
      custom_paths[:components_directory]
    end
    alias_method(:components_path, :components_path=)

    # Get/set path to dynamic files
    #
    # @param path [String] path to dynamic files
    # @return [String] path to dynamic files
    def dynamics_path=(path=nil)
      if(path)
        custom_paths[:dynamics_directory] = path
      end
      custom_paths[:dynamics_directory]
    end
    alias_method(:dynamics_path, :dynamics_path=)

    # Get/set path to registry files
    #
    # @param path [String] path to registry files
    # @return [String] path to registry files
    def registry_path=(path=nil)
      if(path)
        custom_paths[:registry_directory] = path
      end
      custom_paths[:registry_directory]
    end
    alias_method(:registry_path, :registry_path=)

    # Compile file
    #
    # @param path [String] path to file
    # @param args [Object] use :sparkle to return struct. provide Hash
    #   to pass through when compiling ({:state => {}})
    # @return [Hashish, SparkleStruct]
    def compile(path, *args)
      formation = self.instance_eval(IO.read(path), path, 1)
      if(args.delete(:sparkle))
        formation
      else
        comp_arg = args.detect{|i| i.is_a?(Hash) }
        (comp_arg ? formation.compile(comp_arg) : formation.compile)._dump
      end
    end

    # Execute given block within struct context
    #
    # @param base [SparkleStruct] context for block
    # @yield block to execute
    # @return [SparkleStruct] provided base or new struct
    def build(base=nil, &block)
      struct = base || SparkleStruct.new
      struct.instance_exec(&block)
      @_struct = struct
    end

    # Load component
    #
    # @param path [String] path to component
    # @return [SparkleStruct] resulting struct
    def load_component(path)
      self.instance_eval(IO.read(path), path, 1)
      @_struct
    end

    # Load all dynamics within a directory
    #
    # @param directory [String]
    # @return [TrueClass]
    def load_dynamics!(directory)
      @loaded_dynamics ||= []
      Dir.glob(File.join(directory, '*.rb')).each do |dyn|
        dyn = File.expand_path(dyn)
        next if @loaded_dynamics.include?(dyn)
        self.instance_eval(IO.read(dyn), dyn, 1)
        @loaded_dynamics << dyn
      end
      @loaded_dynamics.uniq!
      true
    end

    # Load all registry entries within a directory
    #
    # @param directory [String]
    # @return [TrueClass]
    def load_registry!(directory)
      Dir.glob(File.join(directory, '*.rb')).each do |reg|
        reg = File.expand_path(reg)
        require reg
      end
      true
    end

    # Define and register new dynamic
    #
    # @param name [String, Symbol] name of dynamic
    # @param args [Hash] dynamic metadata
    # @option args [Hash] :parameters description of _config parameters
    # @example
    #   metadata describes dynamic parameters for _config hash:
    #   :item_name => {:description => 'Defines item name', :type => 'String'}
    # @yield dynamic block
    # @return [TrueClass]
    def dynamic(name, args={}, &block)
      @dynamics ||= SparkleStruct.hashish.new
      dynamics[name] = SparkleStruct.hashish[
        :block, block, :args, SparkleStruct.hashish[args.map(&:to_a)]
      ]
      true
    end

    # Metadata for dynamic
    #
    # @param name [String, Symbol] dynamic name
    # @return [Hashish] metadata information
    def dynamic_info(name)
      if(dynamics[name])
        dynamics[name][:args] ||= SparkleStruct.hashish.new
      else
        raise KeyError.new("No dynamic registered with provided name (#{name})")
      end
    end
    alias_method :dynamic_information, :dynamic_info

    # Insert a dynamic into a context
    #
    # @param dynamic_name [String, Symbol] dynamic name
    # @param struct [SparkleStruct] context for insertion
    # @param args [Object] parameters for dynamic
    # @return [SparkleStruct]
    def insert(dynamic_name, struct, *args, &block)
      result = false
      if(@dynamics && @dynamics[dynamic_name])
        result = struct.instance_exec(*args, &@dynamics[dynamic_name][:block])
        if(block_given?)
          result.instance_exec(&block)
        end
        result = struct
      else
        result = builtin_insert(dynamic_name, struct, *args, &block)
      end
      unless(result)
        raise "Failed to locate requested dynamic block for insertion: #{dynamic_name} (valid: #{(@dynamics || {}).keys.sort.join(', ')})"
      end
      result
    end

    # Nest a template into a context
    #
    # @param template [String, Symbol] template to nest
    # @param struct [SparkleStruct] context for nesting
    # @param args [String, Symbol] stringified and underscore joined for name
    # @return [SparkleStruct]
    # @note if symbol is provided for template, double underscores
    #   will be used for directory separator and dashes will match underscores
    def nest(template, struct, *args, &block)
      spath = SparkleFormation.new('stub').sparkle_path
      resource_name = [template.to_s.gsub(/(\/|__|-)/, '_'), *args].compact.join('_').to_sym
      path = template.is_a?(Symbol) ? template.to_s.gsub('__', '/') : template.to_s
      file = Dir.glob(File.join(spath, '**', '**', '*.rb')).detect do |local_path|
        strip_path = local_path.sub(spath, '').sub(/^\//, '').tr('-', '_').sub('.rb', '')
        strip_path == path
      end
      unless(file)
        raise ArgumentError.new("Failed to locate nested stack file! (#{template.inspect} -> #{path.inspect})")
      end
      instance = self.instance_eval(IO.read(file), file, 1)
      struct.resources.set!(resource_name) do
        type 'AWS::CloudFormation::Stack'
      end
      struct.resources.__send__(resource_name).properties.stack instance.compile
      if(block_given?)
        struct.resources.__send__(resource_name).instance_exec(&block)
      end
      struct.resources.__send__(resource_name)
    end

    # Insert a builtin dynamic into a context
    #
    # @param dynamic_name [String, Symbol] dynamic name
    # @param struct [SparkleStruct] context for insertion
    # @param args [Object] parameters for dynamic
    # @return [SparkleStruct]
    def builtin_insert(dynamic_name, struct, *args, &block)
      if(defined?(SfnAws) && lookup_key = SfnAws.registry_key(dynamic_name))
        _name, _config = *args
        _config ||= {}
        return unless _name
        resource_name = "#{_name}_#{_config.delete(:resource_name_suffix) || dynamic_name}".to_sym
        new_resource = struct.resources.__send__(resource_name)
        new_resource.type lookup_key
        properties = new_resource.properties
        SfnAws.resource(dynamic_name, :properties).each do |prop_name|
          value = [prop_name, snake(prop_name)].map do |key|
            _config[key] || _config[key.to_sym]
          end.compact.first
          if(value)
            if(value.is_a?(Proc))
              properties.__send__(prop_name).instance_exec(&value)
            else
              properties.__send__(prop_name, value)
            end
          end
        end
        new_resource.instance_exec(&block) if block
        new_resource
      end
    end

    # Convert hash to SparkleStruct instance
    #
    # @param hash [Hashish]
    # @return [SparkleStruct]
    # @note will do best effort on camel key auto discovery
    def from_hash(hash)
      struct = SparkleStruct.new
      struct._camel_keys_set(:auto_discovery)
      struct._load(hash)
      struct._camel_keys_set(nil)
      struct
    end
  end

  # @return [Symbol] name of formation
  attr_reader :name
  # @return [String] base path
  attr_reader :sparkle_path
  # @return [String] components path
  attr_reader :components_directory
  # @return [String] dynamics path
  attr_reader :dynamics_directory
  # @return [String] registry path
  attr_reader :registry_directory
  # @return [Array] components to load
  attr_reader :components
  # @return [Array] order of loading
  attr_reader :load_order
  # @return [Hash] parameters for stack generation
  attr_reader :parameters

  # Create new instance
  #
  # @param name [String, Symbol] name of formation
  # @param options [Hash] options
  # @option options [String] :sparkle_path custom base path
  # @option options [String] :components_directory custom components path
  # @option options [String] :dynamics_directory custom dynamics path
  # @option options [String] :registry_directory custom registry path
  # @option options [Hash] :parameters parameters for stack generation
  # @option options [Truthy, Falsey] :disable_aws_builtins do not load builtins
  # @yield base context
  def initialize(name, options={}, &block)
    @name = name.to_sym
    @sparkle_path = options[:sparkle_path] ||
      self.class.custom_paths[:sparkle_path] ||
      File.join(Dir.pwd, 'cloudformation')
    @components_directory = options[:components_directory] ||
      self.class.custom_paths[:components_directory] ||
      File.join(sparkle_path, 'components')
    @dynamics_directory = options[:dynamics_directory] ||
      self.class.custom_paths[:dynamics_directory] ||
      File.join(sparkle_path, 'dynamics')
    @registry_directory = options[:registry_directory] ||
      self.class.custom_paths[:registry_directory] ||
      File.join(sparkle_path, 'registry')
    self.class.load_dynamics!(@dynamics_directory)
    self.class.load_registry!(@registry_directory)
    unless(options[:disable_aws_builtins])
      require 'sparkle_formation/aws'
      SfnAws.load!
    end
    @parameters = set_generation_parameters!(options.fetch(:parameters, {}))
    @components = SparkleStruct.hashish.new
    @load_order = []
    @overrides = []
    if(block)
      load_block(block)
    end
    @compiled = nil
  end

  ALLOWED_GENERATION_PARAMETERS = ['type', 'default']
  VALID_GENERATION_PARAMETER_TYPES = ['String', 'Number']

  # Validation parameters used for template generation to ensure they
  # are in the expected format
  #
  # @param params [Hash] parameter set
  # @return [Hash] parameter set
  # @raises [ArgumentError]
  def set_generation_parameters!(params)
    params.each do |name, value|
      unless(value.is_a?(Hash))
        raise TypeError.new("Expecting `Hash` type. Received `#{value.class}`")
      end
      if(key = value.keys.detect{|k| !ALLOWED_GENERATION_PARAMETERS.include?(k.to_s) })
        raise ArgumentError.new("Invalid generation parameter key provided `#{key}`")
      end
    end
    params
  end

  # Add block to load order
  #
  # @param block [Proc]
  # @return [TrueClass]
  def block(block)
    @components[:__base__] = self.class.build(&block)
    @load_order << :__base__
    true
  end
  alias_method :load_block, :block

  # Load components into instance
  #
  # @param args [String, Symbol] Symbol component names or String paths
  # @return [self]
  def load(*args)
    args.each do |thing|
      if(thing.is_a?(Symbol))
        path = File.join(components_directory, "#{thing}.rb")
      else
        path = thing
      end
      key = File.basename(path).sub('.rb', '')
      components[key] = self.class.load_component(path)
      @load_order << key
    end
    self
  end

  # Registers block into overrides
  #
  # @param args [Hash] optional arguments to provide state
  # @yield override block
  def overrides(args={}, &block)
    @overrides << {:args => args, :block => block}
    self
  end

  # Compile the formation
  #
  # @param args [Hash]
  # @option args [Hash] :state local state parameters
  # @return [SparkleStruct]
  def compile(args={})
    unless(@compiled)
      compiled = SparkleStruct.new
      compiled._self(self)
      if(args[:state])
        compiled.set_state!(args[:state])
      end
      @load_order.each do |key|
        compiled._merge!(components[key])
      end
      @overrides.each do |override|
        if(override[:args] && !override[:args].empty?)
          compiled._set_state(override[:args])
        end
        self.class.build(compiled, &override[:block])
      end
      @compiled = compiled
    end
    @compiled
  end

  # Clear compiled stack if cached and perform compilation again
  #
  # @return [SparkleStruct]
  def recompile
    @compiled = nil
    compile
  end

  # @return [TrueClass, FalseClass] includes nested stacks
  def nested?
    !!compile.dump!['Resources'].detect do |r_name, resource|
      resource['Type'] == 'AWS::CloudFormation::Stack'
    end
  end

  # @return [TrueClass, FalseClass] includes _only_ nested stacks
  def isolated_nests?
    hash = compile.dump!
    hash.fetch('Resources', {}).all? do |name, resource|
      resource['Type'] == 'AWS::CloudFormation::Stack'
    end
  end

  # Apply stack nesting logic. Will extract unique parameters from
  # nested stacks, update refs to use sibling stack outputs where
  # required and extract nested stack templates for remote persistence
  #
  # @yieldparam template_name [String] nested stack resource name
  # @yieldparam template [Hash] nested stack template
  # @yieldreturn [String] remote URL
  # @return [Hash] dumped template hash
  def apply_nesting(*args)
    hash = compile.dump!
    stacks = Hash[
      hash['Resources'].find_all do |r_name, resource|
        [r_name, MultiJson.load(MultiJson.dump(resource))]
      end
    ]
    parameters = hash.fetch('Parameters', {})
    output_map = {}
    stacks.each do |stack_name, stack_resource|
      remap_nested_parameters(hash, parameters, stack_name, stack_resource, output_map)
    end
    hash['Parameters'] = parameters
    hash['Resources'].each do |resource_name, resource|
      if(resource['Type'] == 'AWS::CloudFormation::Stack')
        stack = resource['Properties'].delete('Stack')
        resource['Properties']['TemplateURL'] = yield(resource_name, stack)
      end
    end
    if(args.include?(:collect_outputs))
      outputs_hash = Hash[
        output_map do |name, value|
          [name, {'Value' => {'Fn::GetAtt' => value}}]
        end
      ]
      if(hash['Outputs'])
        hash['Outputs'].merge!(outputs_hash)
      else
        hash['Outputs'] = outputs_hash
      end
    end
    hash
  end

  # Extract parameters from nested stacks. Check for previous nested
  # stack outputs that match parameter. If match, set parameter to use
  # output. If no match, check container stack parameters for match.
  # If match, set to use ref. If no match, add parameter to container
  # stack parameters and set to use ref.
  #
  # @param template [Hash] template being processed
  # @param parameters [Hash] top level parameter set being built
  # @param stack_name [String] name of stack resource
  # @param stack_resource [Hash] duplicate of stack resource contents
  # @param output_map [Hash] mapping of output names to required stack output access
  # @return [TrueClass]
  # @note if parameter has includes `StackUnique` a new parameter will
  #   be added to container stack and it will not use outputs
  def remap_nested_parameters(template, parameters, stack_name, stack_resource, output_map)
    stack_parameters = stack_resource['Properties']['Stack']['Parameters']
    if(stack_parameters)
      template['Resources'][stack_name]['Properties']['Parameters'] ||= {}
      stack_parameters.each do |pname, pval|
        if(pval['StackUnique'])
          check_name = [stack_name, pname].join
        else
          check_name = pname
        end
        if(parameters.keys.include?(check_name))
          if(parameters[check_name]['Type'] == 'CommaDelimitedList')
            new_val = {'Fn::Join' => [',', {'Ref' => check_name}]}
          else
            new_val = {'Ref' => check_name}
          end
          template['Resources'][stack_name]['Properties']['Parameters'][pname] = new_val
        elsif(output_map[check_name])
          template['Resources'][stack_name]['Properties']['Parameters'][pname] = {
            'Fn::GetAtt' => output_map[check_name]
          }
        else
          if(pval['Type'] == 'CommaDelimitedList')
            new_val = {'Fn::Join' => [',', {'Ref' => check_name}]}
          else
            new_val = {'Ref' => check_name}
          end
          template['Resources'][stack_name]['Properties']['Parameters'][pname] = new_val
          parameters[check_name] = pval
        end
      end
    end
    if(stack_resource['Properties']['Stack']['Outputs'])
      stack_resource['Properties']['Stack']['Outputs'].keys.each do |oname|
        output_map[oname] = [stack_name, "Outputs.#{oname}"]
      end
    end
    true
  end

  # @return [Hash] dumped hash
  def dump
    MultiJson.load(self.to_json)
  end

  # @return [String] dumped hash JSON
  def to_json
    MultiJson.dump(compile.dump!)
  end

end
