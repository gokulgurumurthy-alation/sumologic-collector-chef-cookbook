# frozen_string_literal: true

require 'net/https'
require 'json'

class Sumologic
  class ApiError < RuntimeError; end

  def self.collector_exists?(node_name, api_accessid, api_accesskey, api_timeout = nil)
    collector = Sumologic::Collector.new(
      name: node_name,
      api_accessid: api_accessid,
      api_accesskey: api_accesskey,
      api_timeout: api_timeout
    )
    collector.exist?
  end

  # we should make this more effecient but lets get CI passing again so we can recieve contributions
  class Collector # rubocop:disable Metrics/ClassLength
    attr_reader :name, :api_accessid, :api_accesskey, :api_timeout

    def initialize(opts = {})
      @name = opts[:name]
      @api_accessid = opts[:api_accessid]
      @api_accesskey = opts[:api_accesskey]
      @api_timeout = opts[:api_timeout] || 60
    end

    def api_endpoint
      'https://api.us2.sumologic.com/api/v1'
    end

    def sources
      @sources ||= fetch_source_data
    end

    def metadata
      collectors['collectors'].find { |c| c['name'] == name }
    end

    def exist?
      if metadata?
        metadata
      else
        !metadata
      end
    end

    def api_request(options = {})
      parse_json = options.key?(:parse_json) ? options[:parse_json] : true
      response = if !api_timeout.nil?
                   api_request_timeout(options)
                 else
                   api_request_http_call(options)
                 end

      if parse_json
        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          Chef::Log.warn('Sumlogic sent something that does not appear to be JSON, here it is...')
          Chef::Log.warn("status code: #{response.code}")
          Chef::Log.warn(response.body)
          raise e
        end
      else
        response
      end
    end

    def refresh!
      @collectors ||= list_collectors
      @sources = fetch_source_data
      nil
    end

    def list_collectors
      uri = URI.parse(api_endpoint + '/collectors')
      request = Net::HTTP::Get.new(uri.request_uri)
      api_request(uri: uri, request: request)
    end

    def collectors
      @collectors ||= list_collectors
    end

    def id
      metadata['id']
    end

    def fetch_source_data
      u = URI.parse(api_endpoint + "/collectors/#{id}/sources")
      request = Net::HTTP::Get.new(u.request_uri)
      details = api_request(uri: u, request: request)
      details['sources']
    end

    def source_exist?(source_name)
      sources.any? { |c| c['name'] == source_name }
    end

    def source(source_name)
      sources.find { |c| c['name'] == source_name }
    end

    def add_source!(source_data)
      u = URI.parse(api_endpoint + "/collectors/#{id}/sources")
      request = Net::HTTP::Post.new(u.request_uri)
      request.body = JSON.dump(source: source_data)
      request.content_type = 'application/json'
      response = api_request(uri: u, request: request, parse_json: false)
      response
    end

    def delete_source!(source_id)
      u = URI.parse(api_endpoint + "/collectors/#{source_id}")
      request = Net::HTTP::Delete.new(u.request_uri)
      response = api_request(uri: u, request: request, parse_json: false)
      response
    end

    def update_source!(source_id, source_data)
      u = URI.parse(api_endpoint + "/collectors/#{id}/sources/#{source_id}")
      request = Net::HTTP::Put.new(u.request_uri)
      request.body = JSON.dump(source: source_data.merge(id: source_id))
      request.content_type = 'application/json'
      request['If-Match'] = get_etag(source_id)
      response = api_request(uri: u, request: request, parse_json: false)
      response
    end

    def get_etag(source_id)
      u = URI.parse(api_endpoint + "/collectors/#{id}/sources/#{source_id}")
      request = Net::HTTP::Get.new(u.request_uri)
      response = api_request(uri: u, request: request, parse_json: false)
      response['etag']
    end

    def search(query)
      u = URI.parse(api_endpoint + "/logs/search?q=#{query}")
      request = Net:: HTTP::Get.new(u.request_uri)
      response = api_request(uri: u, request: request)
      response
    end

    private

    def api_request_http_call(options = {})
      uri = options[:uri]
      puts 'url is '
      puts uri
      request = options[:request]
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request.basic_auth(api_username, api_password)
      response = http.request(request)
      raise ApiError, "Unable to get source list #{response.inspect}" unless response.is_a?(Net::HTTPSuccess)
      response
    end

    def api_request_timeout(options = {})
      response = nil
      Timeout.timeout(options[:api_timeout]) do
        sleep_to = 0
        begin
          response = api_request_http_call(options)
        rescue Errno::ETIMEDOUT
          Chef::Log.warn("Sumologic api timedout... retrying in #{sleep_to}s")
          sleep sleep_to
          sleep_to += 10
          retry
        end
      end
      response
    end
  end
end
