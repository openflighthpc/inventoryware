# =============================================================================
# Copyright (C) 2019-present Alces Flight Ltd.
#
# This file is part of Flight Inventory.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Inventory is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Inventory. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Inventory, please visit:
# https://github.com/openflighthpc/flight-inventory
# ==============================================================================
require 'inventoryware/exceptions'
require 'inventoryware/utils'

module Inventoryware
  class Node
    class << self
      # retrieves all .yaml files in the storage dir
      def find_all_nodes()
        node_paths = Dir.glob(File.join(Config.yaml_dir, '*.yaml'))
        if node_paths.empty?
          $stderr.puts "No asset data found "\
            "in #{File.expand_path(Config.yaml_dir)}"
        end
        nodes = node_paths.map { |p| Node.new(p) }
        nodes.each { |n| n.check_schema }
        return nodes
      end

      # retreives all nodes in the given groups
      # note: if speed becomes an issue this should be reverted back to the old
      # method of converting the yaml to a string and searching with regex
      def find_nodes_in_groups(target_groups, node_list = find_all_nodes())
        target_groups = *target_groups unless target_groups.is_a?(Array)
        nodes = []
        node_list.each do |node|
          unless (node.all_groups & target_groups).empty?
            nodes.append(node)
          end
        end
        if nodes.empty?
          $stderr.puts "No assets found in #{target_groups.join(' or ')}."
        end
        return nodes
      end

      # retreives all nodes with the given type
      # This cannot easily be done by converting the yaml to a string and
      # searching with regex as the `lshw` hash has keys called 'type'
      def find_nodes_with_types(target_types, node_list = find_all_nodes())
        target_types = *target_types unless target_types.is_a?(Array)
        target_types.map! { |t| t.downcase }
        nodes = []
        node_list.each do |node|
          if target_types.include?(node.type.downcase)
            nodes.append(node)
          end
        end
        if nodes.empty?
          $stderr.puts "No assets found with type #{target_types.join(' or ')}."
        end
        return nodes
      end

      # retreives the .yaml file for each of the given nodes
      # expands node ranges if they exist
      # if return missing is passed, returns paths to the .yamls of non-existent
      #   nodes
      def find_single_nodes(node_str, return_missing = false)
        node_names = expand_asterisks(NodeattrUtils::NodeParser.expand(node_str))
        $stderr.puts "No assets found for '#{node_str}'" if node_names.empty?

        type = nil
        nodes = []
        node_names.each do |node_name|
          node_yaml = "#{node_name}.yaml"
          node_yaml_location = File.join(Config.yaml_dir, node_yaml)
          unless Utils.check_file_readable?(node_yaml_location)
            $stderr.puts "File #{node_yaml} not found within "\
              "#{File.expand_path(Config.yaml_dir)}"
            if return_missing
              $stderr.puts "Creating..."
              type = type || Utils.get_new_asset_type
            else
              $stderr.puts "Skipping."
              next
            end
          end
          node = Node.new(node_yaml_location)
          node.create_if_non_existent(type)
          nodes.append(node)
        end
        return nodes
      end

      def expand_asterisks(nodes)
        new_nodes = []
        nodes.each do |node|
          if node.match(/\*/)
            node_names = Dir.glob(File.join(Config.yaml_dir, node)).map { |file|
              File.basename(file, '.yaml')
            }
            new_nodes.push(*node_names)
          end
        end
        nodes.delete_if { |node| node.match(/\*/) }
        nodes.push(*new_nodes)
        return nodes
      end

      def make_unique(nodes)
        nodes.uniq { |n| [n.path] }
      end
    end

    def initialize(path)
      @path = path
      @name = File.basename(path, File.extname(path))
    end

    def data
      @data ||= open
    end

    def type
      type = if @data
               @data['type']
             else
               quick_search_file('type')
             end
      type = 'server' unless type
      return type
    end

    def schema
      schema = if @data
                 @data['schema']
               else
                 quick_search_file('schema')
               end
      schema = 0 unless schema
      return schema
    end


    def primary_group
      return @data.dig('mutable','primary_group') if @data

      # Note the two spaces
      return quick_search_file('  primary_group') || 'orphan'
    end

    def secondary_groups
      groups = if @data
                 @data.dig('mutable','secondary_groups')
               else
                 # Note the two spaces
                 groups = quick_search_file('  secondary_groups')
               end
      groups.nil? ? [] : groups.split(',')
    end

    # Time saving method - functionally executes `primary_group` and
    # `secondary_groups` in sequence, while only iterating over the file once
    def all_groups
      return secondary_groups << primary_group if @data
      found = ['orphan']
      quick_search_file do |line|
        if pri_m = line.match(/^  primary_group: (.*)$/)
          found[0] = pri_m[1]
        elsif sec_m = line.match(/^  secondary_groups: (.*)$/)
          found = found + sec_m[1].split(',')
        end
      end
      return found
    end

    def data=(value)
      @data = value
    end

    def open
      node_data = Utils.load_yaml(@path)
      # condition for if the .yaml is empty
      unless node_data
        raise ParseError, <<-ERROR.chomp
Yaml in #{@path} is empty - aborting
        ERROR
      end
      @data = node_data
      return @data
    end

    def save
      # this `.data` call is necessary to prevent attempting to write nothing
      # to the file
      self.data
      unless Utils.check_file_writable?(@path)
        raise FileSysError, <<-ERROR.chomp
Output file #{@path} not accessible - aborting
        ERROR
      end

      output_yaml = order_hash(data).to_yaml
      File.open(@path, 'w') { |file| file.write(output_yaml) }
    end

    # Moves the asset file. This was created to assist with moving existing assets
    # to the new format that supports clusters. Use with caution as this has a
    # fairly significant impact on system functionality.
    def move(new_path)
      original_path = self.path

      set_path(new_path)
      FileUtils.mv(original_path, new_path)
    end

    def create_if_non_existent(type = '')
      unless Utils.check_file_readable?(@path)
        @data = {
          'name' => @name,
          'mutable' => {},
          'type' => type,
          'schema' => SCHEMA_NUM,
        }
        save
      end
    end

    def check_schema
      unless schema.to_f >= REQ_SCHEMA_NUM
        raise FileSysError, <<-ERROR.chomp
Asset '#{name}' has data in the wrong schema
Please update it before continuing
See migrate_data.rb in the scripts directory
(Has #{schema}; minimum required is #{REQ_SCHEMA_NUM})
        ERROR
      end
    end

    attr_reader :path, :name

    private
    def quick_search_file(target_str_prefix = nil)
      # hack-y method to save time - rather than load the node's data into mem
      #   as a hash if the data isn't going to be used for anything, just grep.
      #   This time saving adds up if listing 100s of nodes
      return_value = nil
      IO.foreach(@path) do |line|
        if block_given?
          return_value = yield(line)
        elsif m = line.match(/^#{target_str_prefix}: (.*)$/)
          return_value = m[1]
        end
        break if return_value
      end
      return return_value
    end

    # Another hack-y method to keep short values near the top of the hash
    # This is to speed up quick_search_file above (a move to using a db may be
    # in order shortly)
    def order_hash(hash)
      Hash[hash.sort_by { |k, _| Config.req_keys.include?(k) ? 0 : 1 }]
    end

    # Like with the move method this might not see any practical use outside
    # of moving existing assets to the format supporting clusters
    def set_path(path)
      @path = path
    end
  end
end
