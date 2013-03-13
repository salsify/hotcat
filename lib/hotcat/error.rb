module Hotcat
  # Raised if the configuration fails validation.
  class ConfigError < ArgumentError; end

  # Raised if there is a problem invoving the cache.
  class CacheError < RuntimeError; end

  # Raised if there's a problem when writing a Salsify document.
  class SalsifyWriterError < RuntimeError; end
end