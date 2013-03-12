# Loads Salsify products from the Salsify directory.
#
# This class should be overridden by a class implementing a specific document
# writing format.
class Hotcat::SalsifyProductsLoader

  class << self
    attr_reader :default_product_id_property, :default_product_name_property
  end
  @default_product_id_property = "sku"
  @default_product_name_property = "ProductName"


  # relaed_products_ids_suppliers: the list of related products to download.
  attr_reader :product_ids_loaded, :related_product_ids_suppliers


  def initialize(options)
    options = {
      max_products: 0,
      max_related_products: 0
    }.merge(options)

    # source directory from which to load ICEcat product data
    source_directory = options[:source_directory]
    source_directory << File.SEPARATOR unless source_directory.ends_with?(File::SEPARATOR)
    @source_directory = source_directory

    # Whitelist of files in the given directory. Elements in the array should be
    # complete paths to the whitelist of files. If not present all files in the
    # source directory will be loaded.
    @files = options[:files_whitelist]

    # Filename to write data out to.
    @products_filename = options[:output_file]

    # whitelist of category IDs. If not present all categories are acceptible.
    @category_whitelist = options[:category_whitelist]

    # maximum number of products to load
    @max_products = options[:max_products]

    # maximum number of related products per product to load
    @max_related_products = options[:max_related_products]

    # if present this will use upload images to AWS and get public URLs from
    # there
    @aws_uploader = options[:aws_uploader]

    # cache of all product IDs loaded
    @product_ids_loaded = []
    @related_product_ids_suppliers = {}

    options
  end


  def convert
   @products_output_file = open_output_file(output_filename)

    @successfully_converted = 0
    # sorted to use the same products every time to having to load new
    # accessory files each run.
    Dir.entries(@source_directory).sort.each_with_index do |filename|
      next if filename.start_with?(".")
      file = File.join(@source_directory, filename)
      next unless @files.blank? || @files.include?(file)

      begin
        product = load_product(file)
      rescue Exception => e
        # don't let a single error derail the entire project...
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        puts "ERROR: Exception encountered when loading from #{filename}"
        puts e.inspect
        print e.backtrace.join("\n")
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        product = nil
      end

      if process_product?(product)
        id = convert_product(product)
        @product_ids_loaded.push(id)
        @successfully_converted += 1
      else
        puts "WARNING: could not load product from file: #{filename}"
      end

      break if @max_products > 0 && @successfully_converted >= @max_products
    end

    close_output_file(@products_output_file)

    # Probably a faster way to do this, but who cares?
    @product_ids_loaded.each { |id| @related_product_ids_suppliers.delete(id) }
    @product_ids_loaded
  end


  private


  def open_output_file
    raise Hotcat::SalsifyWriterError, "Must override open_output_file in subclass"
  end


  def close_output_file
    raise Hotcat::SalsifyWriterError, "Must override close_output_file in subclass"
  end


  def output_filename
    @products_filename
  end


  def output_file
    @products_output_file
  end


  def successfully_converted
    @successfully_converted
  end


  # parses the given ICEcat product document and returns the product loaded.
  # returns nil if there is any error (such as a bogus document).
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


  def product_id_attribute
    Hotcat::SalsifyProductsLoader.default_product_id_property
  end


  def product_id(product)
    product[:properties][product_id_attribute]
  end


  # return whether to bother processing the product we just parsed
  def process_product?(product)
    return false if product.nil? || product.keys.empty? || product[:properties].empty?

    return @category_whitelist.blank? ||
           (product[:category].present? && @category_whitelist.include?(product[:category].to_s))
  end


  # returns list of accessory IDs
  def get_accessory_ids(product)
    return nil if product[:related_product_ids_suppliers].empty?

    accessory_ids = []

    # sorting here to prevent, as much as possible having to download new
    # documents every single time.
    product[:related_product_ids_suppliers].keys.sort.each do |id|
      accessory_ids.push(id)
      supplier = product[:related_product_ids_suppliers][id]
      @related_product_ids_suppliers[id] = supplier if @related_product_ids_suppliers[id].blank?

      break if @max_related_products > 0 && accessory_ids.length >= @max_related_products
    end

    accessory_ids
  end


  def get_image_url(product)
    return nil if product[:image_url].blank?
    url = product[:image_url].strip
    url = @aws_uploader.upload(product_id(product), url) if @aws_uploader.present?
    url
  end


  def convert_product(product)
    product[:accessory_ids] = get_accessory_ids(product)
    product[:image_url] = get_image_url(product)
    write_product(product)
    product_id(product)
  end


  def write_product(product)
    raise Hotcat::SalsifyWriterError, "Must override write_product in subclass"
  end

end