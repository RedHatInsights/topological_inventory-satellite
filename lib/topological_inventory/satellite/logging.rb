require "topological_inventory/providers/common/logging"

module TopologicalInventory
  module Satellite
    class << self
      attr_writer :logger
    end

    def self.logger
      @logger ||= TopologicalInventory::Providers::Common::Logger.new
    end

    module Logging
      def logger
        TopologicalInventory::Satellite.logger
      end
    end
  end
end
