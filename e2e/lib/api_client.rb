# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module TurniereE2E
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(message, status:, body:)
      super(message)
      @status = status
      @body = body
    end
  end

  class ApiClient
    attr_reader :base_url

    def initialize(base_url:)
      @base_url = base_url.delete_suffix('/')
      @auth_headers = {}
      @login_credentials = nil
    end

    def register!(email:, password:, username:)
      response = request(
        :post,
        '/users',
        body: {
          email:,
          password:,
          password_confirmation: password,
          username:
        }
      )
      store_auth_headers!(response)
      response.fetch(:json)
    end

    def login!(email:, password:)
      @login_credentials = { email:, password: }
      @auth_headers = {}
      response = request(
        :post,
        '/users/sign_in',
        body: {
          email:,
          password:
        }
      )
      store_auth_headers!(response)
      response
    end

    def authenticated?
      !@auth_headers.empty?
    end

    def get(path, params: nil, headers: {})
      request(:get, path, params:, headers:)
    end

    def post(path, body: nil, params: nil, headers: {})
      request(:post, path, body:, params:, headers:)
    end

    def patch(path, body: nil, params: nil, headers: {})
      request(:patch, path, body:, params:, headers:)
    end

    def delete(path, params: nil, headers: {})
      request(:delete, path, params:, headers:)
    end

    private

    def request(method, path, body: nil, params: nil, headers: {}, retry_on_unauthorized: true, refresh_session: true)
      login!(**@login_credentials) if refresh_session && should_refresh_session?(method, path)

      uri = URI.parse("#{base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params&.any?

      request_class = case method
                      when :get then Net::HTTP::Get
                      when :post then Net::HTTP::Post
                      when :patch then Net::HTTP::Patch
                      when :delete then Net::HTTP::Delete
                      else
                        raise ArgumentError, "unsupported method #{method}"
                      end

      request = request_class.new(uri)
      merged_headers(headers).each { |key, value| request[key] = value }
      request.body = JSON.dump(body) if body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      parsed_json = parse_json_body(response.body)
      result = {
        status: response.code.to_i,
        json: parsed_json,
        headers: response.each_header.to_h
      }
      store_auth_headers!(result)
      if retry_on_unauthorized && result[:status] == 401 && can_reauthenticate?(path)
        login!(**@login_credentials)
        return request(method, path, body:, params:, headers:, retry_on_unauthorized: false,
                                     refresh_session: false)
      end
      result
    end

    def merged_headers(headers)
      {
        'accept' => 'application/json',
        'content-type' => 'application/json'
      }.merge(@auth_headers).merge(headers.transform_keys(&:downcase))
    end

    def parse_json_body(body)
      return {} if body.nil? || body.strip.empty?

      JSON.parse(body, symbolize_names: true)
    rescue JSON::ParserError
      { raw_body: body }
    end

    def store_auth_headers!(response)
      %w[access-token client uid expiry token-type authorization].each_with_object({}) do |key, auth_headers|
        value = response[:headers][key]
        auth_headers[key] = value if response[:headers].key?(key) && !value.to_s.empty?
      end.tap do |headers|
        @auth_headers = @auth_headers.merge(headers) unless headers.empty?
      end
    end

    def can_reauthenticate?(path)
      !@login_credentials.nil? && path != '/users/sign_in'
    end

    def should_refresh_session?(method, path)
      !@login_credentials.nil? && method != :get && path != '/users/sign_in'
    end
  end
end
