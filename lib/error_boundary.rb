# typed: true

require 'statsig_errors'
require 'sorbet-runtime'

$endpoint = 'https://statsigapi.net/v1/sdk_exception'

module Statsig
  class ErrorBoundary
    extend T::Sig

    sig { params(sdk_key: String).void }
    def initialize(sdk_key)
      @sdk_key = sdk_key
      @seen = Set.new
    end

    def capture(task:, recover: -> {})
      begin
        res = task.call
      rescue StandardError => e
        if e.is_a?(Statsig::UninitializedError) || e.is_a?(Statsig::ValueError)
          raise e
        end

        puts '[Statsig]: An unexpected exception occurred.'
        log_exception(e)
        res = recover.call
      end
      return res
    end

    private

    def log_exception(exception)
      begin
        name = exception.class.name
        if @seen.include?(name)
          return
        end

        @seen << name
        meta = Statsig.get_statsig_metadata
        http = HTTP.headers(
          {
            'STATSIG-API-KEY' => @sdk_key,
            'STATSIG-SDK-TYPE' => meta['sdkType'],
            'STATSIG-SDK-VERSION' => meta['sdkVersion'],
            'Content-Type' => 'application/json; charset=UTF-8'
          }).accept(:json)
        body = {
          'exception' => name,
          'info' => {
            'trace' => exception.backtrace.to_s,
            'message' => exception.message
          }.to_s,
          'statsigMetadata' => meta
        }
        http.post($endpoint, body: JSON.generate(body))
      rescue
        return
      end
    end
  end
end