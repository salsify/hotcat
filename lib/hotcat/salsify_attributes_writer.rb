# encoding: utf-8

require 'hotcat/salsify_document_writer'
require 'hotcat/salsify_products_writer'
require 'hotcat/salsify_category_writer'

# Writes out the attributes document required by Salsify
#
# FIXME digital asset roles. Other roles?
class Hotcat::SalsifyAttributesWriter
  include Hotcat::SalsifyDocumentWriter


  class << self
    attr_reader :filename
  end
  @filename = "icecat-attributes.json.gz"


  def initialize(filename)
    @filename = filename
  end


  def write
    attributes_file = open_output_file(@filename)

    attributes = {
      attributes: [
        {
          id: Hotcat::SalsifyProductsWriter.default_product_id_property,
          roles: {
            products: ["id"],
            accessories: ["target_product_id"]
          }
        },
        {
          id: Hotcat::SalsifyProductsWriter.default_product_name_property,
          roles: { products: ["name"] }
        },
        {
          id: Hotcat::SalsifyCategoryWriter.default_accessory_category,
          roles: { global: ["accessory_label"] }
        }
      ]
    }
    attributes_file << attributes.to_json.force_encoding('utf-8')

    close_output_file(attributes_file)
  end

end