# typed: true
module Statsig
  module Interfaces
    class IDataStore
      CONFIG_SPECS_KEY = "statsig.cache"

      def init
      end

      def get(key)
        nil
      end

      def set(key, value)
      end

      def shutdown
      end

      ##
      # Determines whether the SDK should poll for updates from
      # the data adapter for the given key
      #
      # @param key Key of stored item to poll from data adapter
      def should_be_used_for_polling(key)
      end
    end
  end
end