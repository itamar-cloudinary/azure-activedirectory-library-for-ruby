#-------------------------------------------------------------------------------
# # Copyright (c) Microsoft Open Technologies, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
# PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache License, Version 2.0 for the specific language
# governing permissions and limitations under the License.
#-------------------------------------------------------------------------------

require_relative './logging'
require_relative './xml_namespaces'

require 'nokogiri'
require 'uri'

module ADAL
  # Relevant fields from a Mex response.
  class MexResponse
    include XmlNamespaces

    class << self
      include Logging
    end

    class MexError < StandardError; end

    POLICY_ID_XPATH =
      '//wsdl:definitions/wsp:Policy[./wsp:ExactlyOne/wsp:All/sp:SignedSuppor' \
      'tingTokens/wsp:Policy/sp:UsernameToken/wsp:Policy/sp:WssUsernameToken1' \
      '0]/@u:Id|//wsdl:definitions/wsp:Policy[./wsp:ExactlyOne/wsp:All/ssp:Si' \
      'gnedEncryptedSupportingTokens/wsp:Policy/ssp:UsernameToken/wsp:Policy/' \
      'ssp:WssUsernameToken10]/@u:Id'
    BINDING_XPATH = '//wsdl:definitions/wsdl:binding[./wsp:PolicyReference]'
    PORT_XPATH = '//wsdl:definitions/wsdl:service/wsdl:port'
    ADDRESS_XPATH = './soap12:address/@location'

    ##
    # Parses the XML string response from the Metadata Exchange endpoint into
    # a MexResponse object.
    #
    # @param String response
    # @return MexResponse
    def self.parse(response)
      xml = Nokogiri::XML(response)
      policy_ids = parse_policy_ids(xml)
      bindings = parse_bindings(xml, policy_ids)
      endpoint, binding = parse_endpoint_and_binding(xml, bindings)
      MexResponse.new(endpoint, binding)
    end

    # @param Nokogiri::XML::Document xml
    # @param Array[String] policy_ids
    # @return Array[String]
    private_class_method def self.parse_bindings(xml, policy_ids)
      matching_bindings = xml.xpath(BINDING_XPATH, NAMESPACES).map do |node|
        reference_uri = node.xpath('./wsp:PolicyReference/@URI', NAMESPACES)
        node.xpath('./@name').to_s if policy_ids.include? reference_uri.to_s
      end.compact
      fail MexError, 'No matching bindings found.' if matching_bindings.empty?
      matching_bindings
    end

    # @param Nokogiri::XML::Document xml
    # @param Array[String] bindings
    # @return Array[[String, String]]
    private_class_method def self.parse_all_endpoints(xml, bindings)
      endpoints = xml.xpath(PORT_XPATH, NAMESPACES).map do |node|
        binding = node.attr('binding').split(':').last
        if bindings.include? binding
          [node.xpath(ADDRESS_XPATH, NAMESPACES).to_s, binding]
        end
      end.compact
      endpoints
    end

    # @param Nokogiri::XML::Document xml
    # @param Array[String] bindings
    # @return [String, String]
    private_class_method def self.parse_endpoint_and_binding(xml, bindings)
      endpoints = parse_all_endpoints(xml, bindings)
      case endpoints.size
      when 0
        fail MexError, 'No valid WS-Trust endpoints found.'
      when 1
      else
        logger.warn('Multiple WS-Trust endpoints were found in the mex ' \
                    'response. Only one was used.')
      end
      endpoints.first
    end

    # @param Nokogiri::XML::Document xml
    # @return Array[String]
    private_class_method def self.parse_policy_ids(xml)
      policy_ids = xml.xpath(POLICY_ID_XPATH, NAMESPACES)
                   .map { |attr| "\##{attr.value}" }
      fail MexError, 'No username token policy nodes.' if policy_ids.empty?
      policy_ids
    end

    attr_reader :action
    attr_reader :wstrust_url

    ##
    # Constructs a new MexResponse.
    #
    # @param String|URI wstrust_url
    # @param String action
    def initialize(wstrust_url, binding)
      @action = BINDING_TO_ACTION[binding]
      @wstrust_url = URI.parse(wstrust_url.to_s)
      return if @wstrust_url.instance_of? URI::HTTPS
      fail ArgumentError, 'Mex is only done over HTTPS.'
    end
  end
end
