# encoding: utf-8

require 'hotcat/salsify_document_writer'
require 'hotcat/salsify_category_writer'

# Writes out a Salsify category document.
class Hotcat::SalsifyProductsWriter
  include Hotcat::SalsifyDocumentWriter


  class << self
    attr_reader :default_product_id_property, :default_product_name_property
  end
  @default_product_id_property = "sku"
  @default_product_name_property = "ProductName"


  # The list of related products to make sure to download.
  attr_reader :related_product_ids_suppliers


  def initialize(source_directory,
                 files,
                 products_filename,
                 max_products,
                 max_related_products)

    source_directory << File.SEPARATOR unless source_directory.ends_with?(File::SEPARATOR)
    @source_directory = source_directory

    # Whitelist of files in the given directory. Elements in the array should be
    # complete paths to the whitelist of files.
    @files = files

    @products_filename = products_filename
    @max_products = max_products

    @max_related_products = max_related_products

    @product_ids_loaded = []
    @related_product_ids_suppliers = {}
  end


  # TODO: move to using a logger from puts
  def convert
    @products_file = open_output_file(@products_filename)

    successfully_converted = 0
    # sorted to hopefully use the same products every time to having to load new
    # accessory files each run.
    Dir.entries(@source_directory).sort.each_with_index do |filename|
      next if filename.start_with?(".")
      file = @source_directory + filename
      next unless @files.nil? || @files.include?(file)
      begin
        product = load_product(file)
      rescue Exception => e
        # don't let a single error derail the entire project...
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        puts "ERROR: Exception encountered when loading from #{filename}"
        puts e.inspect
        print e.backtrace.join("\n")
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        product = nil
      end
      unless product.nil? || product.keys.empty? || product[:properties].empty?
        @products_file << ", \n" unless successfully_converted == 0
        @product_ids_loaded.push(write_product(product))
        successfully_converted += 1
      else
        puts "WARNING: could not load product from file: #{filename}"
      end

      break if @max_products > 0 && successfully_converted >= @max_products
    end

    close_output_file(@products_file)

    # Probably a faster way to do this, but who cares?
    @product_ids_loaded.each { |id| @related_product_ids_suppliers.delete(id) }
    @product_ids_loaded
  end


  private


  # override to prevent writing the wrapping array bracket
  # TODO remove once Salsify can accept an array of product documents
  def start_file(file)
    # noop
  end

  # override to prevent writing the wrapping array bracket
  # TODO remove once Salsify can accept an array of product documents
  def end_file(file)
    # noop
  end


  def load_product(filename)
    product_document = Hotcat::ProductDocument.new
    parser = Nokogiri::XML::SAX::Parser.new(product_document)
    if filename.end_with?(".gz")
      parser.parse(Zlib::GzipReader.open(filename))
    else
      parser.parse(File.open(filename))
    end

    # ICEcat returned a document that itself has an error. Most likely that we
    # don't have the rights to download the given product.
    return nil if product_document.code == "-1"

    product_document.product
  end


  def write_product(product)
    product_json = Hash.new
    product[:properties].each_pair do |k,v|
      # this is to ensure that extra newlines are not present in the output
      k = k.strip if k.is_a?(String)
      product_json[k] = v.is_a?(String) ? v.strip : v
    end
    product_json[Hotcat::SalsifyCategoryWriter.default_root_category] = product[:category]

    unless product[:related_product_ids_suppliers].empty?
      accessories = []
      # sorting here to (hopefully) prevent having to download new documents
      # every single time.
      product[:related_product_ids_suppliers].keys.sort.each do |id|
        accessories.push({
                          Hotcat::SalsifyCategoryWriter.default_accessory_category => Hotcat::SalsifyCategoryWriter.default_accessory_relationship,
                          Hotcat::SalsifyProductsWriter.default_product_id_property => id.strip
                        })
        supplier = product[:related_product_ids_suppliers][id]
        @related_product_ids_suppliers[id] = supplier if @related_product_ids_suppliers[id].nil?

        break if @max_related_products > 0 && accessories.length >= @max_related_products
      end
      product_json[:accessories] = accessories
    end

    unless product[:image_url].nil?
      product_json[:digital_assets] = [
        {
          url: product[:image_url].strip,
          is_primary_image: true
        }
      ]
    end

    @products_file << product_json.to_json.force_encoding('utf-8')

    # return the ID for the product
    product[:properties][Hotcat::SalsifyProductsWriter.default_product_id_property]
  end

end
