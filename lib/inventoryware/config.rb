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

require 'inventoryware/utils'

module Inventoryware
  class Config
    class << self
      def instance
        @instance ||= Config.new
      end

      def method_missing(s, *a, &b)
        if instance.respond_to?(s)
          instance.send(s, *a, &b)
        else
          super
        end
      end

      def respond_to_missing?(s)
        instance.respond_to?(s)
      end
    end

    attr_reader :yaml_dir, :templates_dir, :helpers_dir, :req_files,
                :all_files, :templates_config_path, :plugins_dir, :req_keys

    def initialize
      @templates_config_path = File.join(root_dir, 'etc/templates.yml')

      @yaml_dir = File.join(storage_dir, active_cluster)
      @templates_dir = File.join(root_dir, 'templates')
      @helpers_dir = File.join(root_dir, 'helpers')
      @plugins_dir = File.join(root_dir, 'plugins')

      @req_files = ["lshw-xml", "lsblk-a-P"]
      @all_files = @req_files + ['groups']

      @req_keys = ['name', 'schema', 'mutable', 'type']
    end

    # @deprecated There is only ever going to be a single cluster
    # Returns 'default' for temporary fix
    def active_cluster
      'default'
    end

    # @return [String] The path to the source code root directory
    def root_dir
      @root_dir ||= File.expand_path('../..', __dir__)
    end

    # TODO: Implement with XDG
    # @return [String] The directory path where data can be stored
    def storage_dir
      @storage_dir ||= File.join(root_dir, 'var/store')
    end

    # @return [String] The path to the "binary" used by the generate command
    def generate_binary_path
      @generate_binary_path ||= File.join(storage_dir, 'bin/generate')
    end
  end
end
