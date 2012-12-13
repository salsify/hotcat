# encoding: utf-8

require 'hotcat/error'
require 'hotcat/salsify_document_writer'

# Writes out a Salsify category document.
class Hotcat::SalsifyProductsWriter
  include Hotcat::SalsifyDocumentWriter

  # The list of related products to make sure to download.
  attr_reader :related_product_ids_suppliers

  def initialize(source_directory, files = nil, products_filename, relations_filename, max_related_products = 0)
    source_directory << File.SEPARATOR unless source_directory.ends_with?(File::SEPARATOR)
    @source_directory = source_directory

    # Whitelist of files in the given directory.
    @files = files

    @products_filename = products_filename
    @max_related_products = max_related_products
    @relations_filename = relations_filename

    @related_product_ids_suppliers = {}
  end

  # TODO: convert to using a logger
  def convert
    @products_file = open_output_file(@products_filename)
    @products_file << "<products>\n"

    unless @max_related_products == 0
      @relations_file = open_output_file(@relations_filename)
      @relations_file << "<product_relations>\n"
    end

    Dir.entries(@source_directory).each_with_index do |filename|
      next if filename.start_with?(".")
      next unless @files.nil? || files.include?(filename)

      begin
        product = load_product(@source_directory + filename)
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
        write_product(product)
        write_relations(product)
      else
        puts "WARNING: could not load product from file: #{filename}"
      end
    end

    @products_file << "</products>\n"
    close_output_file(@products_file)

    unless @max_related_products == 0
      @relations_file << "</product_relations>\n"
      close_output_file(@relations_file)
    end
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
    product_xml = Ox::Element.new('product')
    product[:properties].each_pair do |k,v|
      if k == "id"
        product_xml['id'] = v
      else
        product_xml << build_property_xml(k,v)
      end
    end
    
    product_xml << build_product_category_xml(product[:category]) if product[:category]
    product_xml << build_image_xml(product[:image_url]) if product[:image_url]

    @products_file << Ox.dump(product_xml).force_encoding('utf-8')
  end

  def write_relations(product)
    relations_xml = Ox::Element.new('relations')
    relations_xml['product_id'] = r[:properties]["id"]
    relations_xml << build_property_xml('name', "Related Product")

    related_products_loaded = 0
    product[:related_product_ids_suppliers].each_pair do |id,supplier|
      related_product_xml = Ox::Element.new('related_product')
      related_product_xml['product_id'] = id
      related_product_xml['status'] = 'active'
      relations_xml << related_product_xml

      @related_product_ids_suppliers[id] = supplier if @related_product_ids_suppliers[id].nil?

      related_products_loaded += 1
      break if @max_related_products > 0 && related_products_loaded >= @max_related_products
    end
    @relations_file << Ox.dump(relations_xml).force_encoding('utf-8')
  end

end