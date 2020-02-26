require "topological_inventory/satellite/connection"
require "topological_inventory/satellite/logging"
require "topological_inventory/providers/common/operations/source"

module TopologicalInventory
  module Satellite
    module Operations
      class Source < TopologicalInventory::Providers::Common::Operations::Source
        include Logging

        ERROR_MESSAGES = {
          :endpoint_not_found           => "Endpoint not found in Sources API",
          :receptor_network_unreachable => "Receptor network unreachable",
          :receptor_node_disconnected   => "Receptor node is disconnected",
          :receptor_node_not_defined    => "Receptor node not defined in Sources API",
          :receptor_not_responding      => "Receptor is not responding",
          :receptor_response_error      => "Receptor controller response error"
        }.freeze

        attr_accessor :source_id, :source_uid, :source_ref

        def initialize(params = {}, request_context = nil, receptor_client = nil)
          super(params, request_context)
          self.connection      = TopologicalInventory::Satellite::Connection.connection(params["external_tenant"], receptor_client)
          self.source_uid      = params['source_uid']
          self.source_ref      = params['source_ref']
        end

        # Entrypoint for "Source:availability_check" operation
        #
        # It updates Source only when unavailable, otherwise it waits
        # for asynchronous #availability_check_[response|timeout]
        def availability_check
          return if params_missing?

          return if checked_recently?

          status, error_message = connection_status
          # Because the response is asynchronous, it can update only in case of error
          unless available?(status)
            update_source_and_endpoint(STATUS_UNAVAILABLE, error_message)
          end
        end

        # Response callback from receptor client
        #
        # Health check returns maximally one message of type "response"
        #
        # @param _msg_id [String] UUID of request's id
        # @param response [Hash]
        def availability_check_response(_msg_id, response)
          connected = response['result'] == 'ok' && response['fifi_status']
          status = connected ? STATUS_AVAILABLE : STATUS_UNAVAILABLE

          # unless available?(status)
          #   logger.info("Source #{source_id} is unavailable. Result: #{response['result']}, FIFI status: #{response['fifi_status'] ? 'T' : 'F'}, Reason: #{response['message']}")
          # end
          logger.info("Source#availability_check for source #{source_id} completed. Status: #{status}, Result: #{response['result']}, FIFI status: #{response['fifi_status'] ? 'T' : 'F'}, Reason: #{response['message']}")
          update_source_and_subresources(status, response['message'])
        end

        def availability_check_error(msg_id, error_code)
          msg = "#{ERROR_MESSAGES[:receptor_response_error]}: #{error_code}"
          logger.error("Source#availability_check for source #{source_id}#{msg} | (message_id: #{msg_id})")
          update_source_and_subresources(STATUS_UNAVAILABLE, msg)
        end

        # Timeout callback from receptor client
        #
        # Kafka message wan't delivered for unknown reason
        #
        # @param msg_id [String] UUID of request's id
        def availability_check_timeout(msg_id)
          logger.error("Source#availability_check - Receptor doesn't respond for Source (ID #{source_id}) | (message id: #{msg_id})")
          update_source_and_subresources(STATUS_UNAVAILABLE, ERROR_MESSAGES[:receptor_not_responding])
        end

        private

        attr_accessor :connection, :params, :request_context

        def available?(status)
          status.to_s == STATUS_AVAILABLE
        end

        def required_params
          %w[source_id source_ref]
        end

        def connection_check
          status, msg = STATUS_UNAVAILABLE, nil

          if available?(receptor_network_status(endpoint.receptor_node))
            if send_availability_check(endpoint.receptor_node)
              status = STATUS_AVAILABLE
            else
              msg = ERROR_MESSAGES[:receptor_network_unreachable]
            end
          else
            msg = ERROR_MESSAGES[:receptor_node_disconnected]
          end

          [status, msg]
        rescue => e
          logger.error("Source#availability_check - Failed to connect to Source id:#{source_id} - #{e.message}. #{e.backtrace.join('\n')}")
          [STATUS_UNAVAILABLE, e.message]
        end

        def receptor_network_status(receptor_node_id)
          connection.status(receptor_node_id) == "connected" ? STATUS_AVAILABLE : STATUS_UNAVAILABLE
        end

        # @return [String|nil] UUID - message ID for callbacks
        def send_availability_check(receptor_node_id)
          connection.send_availability_check(source_ref, receptor_node_id, self)
        end
      end
    end
  end
end
