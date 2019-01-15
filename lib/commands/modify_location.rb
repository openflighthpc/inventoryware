
module Inventoryware
  module Commands
    class ModifyLocation < Command
      def run
        other_args = []
        nodes = Utils::resolve_node_options(@argv, @options, other_args)
        node_locations = Utils::select_nodes(nodes, @options)

        fields = {
          'site' => nil,
          'room' => nil,
          'rack' => nil,
          'unit' => nil,
          'chassis' => nil,
          'slot' => nil
        }

        fields.keys.each do |field|
          p "Enter a #{field} or press enter to skip"
          # TODO swap gets for use of highline gem?
          value = STDIN.gets.chomp
          fields[field] = value if value
        end

        node_locations.each do |location|
          node_data = Utils::read_node_or_create(location)
          fields.each do |key, value|
            unless value.empty?
              node_data['mutable'][key] = value
            end
          end
          Utils::output_node_yaml(node_data, location)
        end
      end
    end
  end
end
