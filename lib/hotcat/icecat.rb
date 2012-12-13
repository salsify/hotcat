# ICEcat constants used by many ICEcat-related files.
module Hotcat
  class Icecat
    class << self
      attr_accessor :fallback_language_id,
                    :english_language_id,
                    :refs_url,
                    :indexes_url,
                    :data_url,
                    :image_properties
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

    # The base URL from which to fetch the full and daily indices.
    @indexes_url = "http://data.Icecat.biz/export/freexml/EN/"

    @image_properties = [
                          'Low Resolution Picture Width',
                          'Low Resolution Picture Height',
                          'Low Resolution Picture URL',

                          'High Resolution Picture Width',
                          'High Resolution Picture Height',
                          'High Resolution Picture URL',

                          'Thumbnail URL',
                        ]
  end
end