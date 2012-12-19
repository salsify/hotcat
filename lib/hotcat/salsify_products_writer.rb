# encoding: utf-8

require 'hotcat/salsify_document_writer'

# Writes out a Salsify category document.
class Hotcat::SalsifyProductsWriter
  include Hotcat::SalsifyDocumentWriter

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

    @related_product_ids_suppliers = {}
  end

  # TODO: move to using a logger from puts
  def convert
    @products_file = open_output_file(@products_filename)

    # need to make sure that the roles are being written appropriately
    attributes = {
      attributes: [
        {
          id: "id",
          roles: [ { products: ["id"] } ]
        }
      ]
    }
    @products_file << attributes.to_json << ", "

    @products_file << "{ \"products\": [ "

    successfully_converted = 0
    Dir.entries(@source_directory).each_with_index do |filename|
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
        @products_file << ", " unless successfully_converted == 0
        write_product(product)
        successfully_converted += 1
      else
        puts "WARNING: could not load product from file: #{filename}"
      end

      break if @max_products > 0 && successfully_converted >= @max_products
    end

    @products_file << " ] }"
    close_output_file(@products_file)
  end

  private

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
    product_json = product[:properties].dup
    product_json[Hotcat::SalsifyCategoryWriter.default_root_category] = product[:category]

    unless product[:related_product_ids_suppliers].empty?
      accessories = []
      product[:related_product_ids_suppliers].each_pair do |id,supplier|
        accessories.push({
                          "Accessory Category" => "Related Product",
                          target_product_id: id
                        })
        @related_product_ids_suppliers[id] = supplier if @related_product_ids_suppliers[id].nil?

        break if @max_related_products > 0 && accessories.length >= @max_related_products
      end
      product_json[:accessories] = accessories
    end

    unless product[:image_url].nil?
      product_json[:digital_assets] = [
        {
          url: product[:image_url],
          is_primary_image: true
        }
      ]
    end

    @products_file << product_json.to_json.force_encoding('utf-8')
  end

end