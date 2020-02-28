require "topological_inventory/satellite/logging"

module TopologicalInventory
  module Satellite
    module Operations
      class Processor
        include Logging

        def self.process!(message, receptor_client)
          new(message, receptor_client).process
        end

        def initialize(message, receptor_client)
          self.message = message
          self.model, self.method = message.message.split(".")

          self.params   = message.payload["params"]
          self.identity = message.payload["request_context"]
          self.receptor_client = receptor_client
        end

        def process
          logger.info(status_log_msg)

          impl = Operations.const_get(model).new(params, identity, receptor_client) if Operations.const_defined?(model)
          if impl&.respond_to?(method)
            result = impl.send(method)

            logger.info(status_log_msg("Complete"))
            result
          else
            logger.warn(status_log_msg("Not Implemented!"))
          end
        end

        private

        attr_accessor :message, :identity, :model, :method, :params, :receptor_client

        def status_log_msg(status = nil)
          "Processing #{model}##{method} [#{params}]...#{status}"
        end
      end
    end
  end
end
