
module Inventoryware
  module Commands
    class Modify < Command
      def run
        other_args = ["modification"]
        nodes = Utils::resolve_node_options(@argv, @options, other_args)

        #TODO DRY up? modification is defined twice
        modification = @argv[0]
        unless modification.match(/=/)
          $stderr.puts "Invalid modification - must contain an '='"
          exit
        end
        field, value = modification.split('=')

        node_locations = Utils::select_nodes(nodes, @options)

        node_locations.each do |location|
          node_data = Utils.read_node_yaml(location).values[0]
          if value
            node_data['mutable'][field] = value
          else
            node_data['mutable'].delete(field)
          end
          Utils::output_node_yaml(node_data, location)
        end
      end
    end
  end
end
