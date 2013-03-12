# encoding: utf-8

require 'hotcat/salsify_document_writer'
require 'hotcat/salsify_products_writer'
require 'hotcat/salsify_category_writer'

# Writes out the attributes document required by Salsify
class Hotcat::SalsifyAttributesWriter
  include Hotcat::SalsifyDocumentWriter


  class << self
    attr_reader :filename
  end
  @filename = "attributes.json.gz"


  def initialize(filename)
    @filename = filename
  end


  def write
    attributes = [
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

    # TODO not DRY see category_writer and product_writer
    # we do this here rather than simply outputting the json because the parent
    # module sets up the outline for the array to help out with bulk loading.
    output_file = open_output_file(@filename)
    attributes.each_with_index do |attribute, index|
      output_file << ",\n" if index > 0
      output_file << attribute.to_json.force_encoding('utf-8')
    end
    close_output_file(output_file)
  end

end