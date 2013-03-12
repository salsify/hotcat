# encoding: utf-8

require 'set'

require 'hotcat/salsify_document_writer'
require 'hotcat/salsify_products_loader'
require 'hotcat/salsify_category_writer'


# Writes out a Salsify category document.
class Hotcat::SalsifyProductsWriter < Hotcat::SalsifyProductsLoader
  include Hotcat::SalsifyDocumentWriter


  attr_reader :attributes


  def initialize(options)
    super(options)

    # contains the list of all attribute IDs seen during import
    @attributes = Set.new
  end


  private


  # override to prevent writing the wrapping array bracket
  def start_file(file)
    # noop
  end

  # override to prevent writing the wrapping array bracket
  def end_file(file)
    # noop
  end


  def write_product(product)
    file = output_file
    file << ", \n" unless successfully_converted == 0

    product_json = Hash.new
    product[:properties].each_pair do |k,v|
      # this is to ensure that extra newlines are not present in the output
      k = k.strip if k.is_a?(String)
      @attributes.add(k.to_s)
      product_json[k] = v.is_a?(String) ? v.strip : v
    end
    product_json[Hotcat::SalsifyCategoryWriter.default_root_category] = product[:category]

    unless product[:accessory_ids].blank?
      product_json[:accessories] = product[:accessory_ids].map do |id|
        {
          Hotcat::SalsifyCategoryWriter.default_accessory_category => Hotcat::SalsifyCategoryWriter.default_accessory_relationship,
          Hotcat::SalsifyProductsLoader.default_product_id_property => id
        }
      end
    end

    unless product[:image_url].blank?
      product_json[:digital_assets] = [
        {
          url: product[:image_url],
          is_primary_image: true
        }
      ]
    end

    file << product_json.to_json.force_encoding('utf-8')
  end

end
