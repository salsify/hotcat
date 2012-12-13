module Hotcat
  # Raised if the configuration fails validation.
  class ConfigError < ArgumentError; end

  # Raised if there's a problem when writing a Salsify document.
  class SalsifyWriterError < RuntimeError; end
end