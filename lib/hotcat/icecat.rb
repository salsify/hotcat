# ICEcat constants used by many ICEcat-related files.
module Hotcat
  class Icecat
    class << self
      attr_accessor :fallback_language_id,
                    :english_language_id,
                    :data_url,
                    :refs_url
    end

    # This is the language ID to fallback to if there is no English entry.
    @fallback_language_id = "1"

    # The ID for English.
    @english_language_id = "9"

    # Base URL for data queries
    @data_url = "data.icecat.biz"

    # Base ICEcat URL for reference documents, such as the supplier or category
    # lists.
    @refs_url = "http://data.icecat.biz/export/freexml/refs/"
  end
end