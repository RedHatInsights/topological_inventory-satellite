module TopologicalInventory
  module Satellite
    class Connection
      class << self
        def connection(account_number, receptor_client)
          new(account_number, receptor_client)
        end
      end

      def initialize(account_number, receptor_client)
        self.account_number = account_number
        self.receptor_client = receptor_client

        receptor_client.identity_header = identity_header
      end

      # org_id with any number is required by receptor_client controller
      def identity_header(account = account_number)
        @identity ||= {
          "x-rh-identity" => Base64.strict_encode64(
            {"identity" => {"account_number" => account, "user" => { "is_org_admin" => true }, "internal" => {"org_id" => '000001'}}}.to_json
          )
        }
      end

      def status(receptor_node_id)
        response = receptor_client.connection_status(account_number, receptor_node_id)
        response['status']
      end

      # @param :type [Symbol] :non_blocking | :blocking
      #
      # @return [String] UUID - message ID for callbacks
      def send_availability_check(source_uid, receptor_node_id, receiver)
        directive = receptor_client.directive(account_number,
                                              receptor_node_id,
                                              :directive => "receptor_satellite:health_check",
                                              :payload   => {'satellite_instance_id' => source_uid.to_s}.to_json,
                                              :type      => :non_blocking)

        directive
          .on_success do |msg_id, response|
            receiver.availability_check_response(msg_id, response)
          end
          .on_error do |msg_id, code, response|
            receiver.availability_check_error(msg_id, code, response)
          end
          .on_timeout do |msg_id|
            receiver.availability_check_timeout(msg_id)
          end
          .on_eof do |msg_id|
            logger.debug("EOF received: #{msg_id}")
          end

        directive.call
      end

      private

      attr_accessor :account_number, :receptor_client
    end
  end
end
