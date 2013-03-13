require 'set'
require 'find'

require 'hotcat/cache_manager'

# Loads Salsify products from the Salsify directory.
#
# The basic idea is that it will look at all product XML files in the Hotcat
# cache directory and attempt to load them. Files or products may be skipped
# by specification (by providing black/whitelists of IDs or files, or by
# restricting the category of files to be loaded).
#
# This class should be overridden by a class implementing a specific document
# writing format.
class Hotcat::SalsifyProductsLoader

  class << self
    attr_reader :default_product_id_property, :default_product_name_property
  end
  @default_product_id_property = "sku"
  @default_product_name_property = "Name"


  # list of all files that were involved successfully in this load
  attr_reader :product_files_succeeded

  # list of product files that contained incorrect product data (usually because
  # the file is an XML document saying that we don't have permission to see the
  # product).
  attr_reader :product_files_failed

  # the list of related products for the products that were successfully loaded.
  # as implied, it is a hash mapping a related product ID to it suppliers
  attr_reader :related_product_ids_suppliers

  # set of product ids that has been successfully loaded
  attr_reader :product_ids_loaded

  # category IDs seen during this load
  attr_reader :category_ids_loaded

  # maps product id to category id for all loaded products
  attr_reader :product_category_mapping

  # list of all attributes that were loaded as part of this run
  attr_reader :attribute_ids_loaded


  def initialize(options)
    options = {
      skip_output: false,
      skip_digital_assets: false,
      max_products: 0,
      max_related_products: 0,
      product_category_mapping: Hash.new
    }.merge(options)

    # whether or not to skip the actual writing step. if true, this will do all
    # the parsing, etc. but won't load anything.
    @skip_output = options[:skip_output]

    # whether to skip digital asset loading
    @skip_digital_assets = options[:skip_digital_assets]

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

    # list of files to skip
    @product_files_blacklist = options[:product_files_blacklist]

    # if the ID is not in this list, it will not get loaded
    @product_id_whitelist = options[:product_id_whitelist]

    @product_files_succeeded = Set.new
    @product_files_failed = Set.new
    @related_product_ids_suppliers = Hash.new
    @product_ids_loaded = Set.new
    @category_ids_loaded = Set.new
    @product_category_mapping = options[:product_category_mapping]
    @attribute_ids_loaded = Set.new

    @cache = Hotcat::CacheManager.instance

    options
  end


  def convert
    if @category_whitelist.present?
      directories = @category_whitelist.map do |category_id|
        @cache.product_files_directory_for_category(category_id)
      end
    else
      directories = [@cache.product_files_directory]
    end

    files_to_process = []
    Find.find(*directories) do |file|
      next if File.directory?(filename)
      next unless @files.blank? || @files.include?(file)
      next if @product_files_blacklist.present? && @product_files_blacklist.include?(file)
      files_to_process.push(file)
    end

    @products_output_file = open_output_file(output_filename) unless skip_output
    @successfully_converted = 0

    # sorted to use the same products every time to having to load new
    # accessory files each run.
    files_to_process.sort.each do |file|
      begin
        product = Hotcat::SalsifyProductsLoader.load_product(file)
        if product.nil?
          @product_files_failed.add(file)
          next
        end
        next if !process_product?(product)
        @product_files_succeeded.add(file)
      rescue Exception => e
        # don't let a single error derail the entire conversion, which could be
        # several hours.
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        puts "ERROR: Exception encountered when loading from #{filename}"
        puts e.inspect
        print e.backtrace.join("\n")
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        next
      end

      id = convert_product(product)
      @product_ids_loaded.add(id)
      if product[:category].present?
        @category_ids_loaded.add(product[:category])
        @product_category_mapping[id] = product[:category]
      end
      @successfully_converted += 1

      # cute progress meter to let you know what's happening
      print "." if @successfully_converted % 10 == 0
     if @successfully_converted % 100 == 0
        print  " #{@successfully_converted} successfully converted so far."
        puts   " #{@product_files_failed.length} bogus files passed."
      end

      break if @max_products > 0 && @successfully_converted >= @max_products
    end

    close_output_file(@products_output_file) unless skip_output

    # we may have already loaded some of the products from the accessor list, in
    # which case we do not have to list them for future processing.
    @related_product_ids_suppliers.delete_if do |id,supplier|
      @product_ids_loaded.include?(id)
    end
    @product_ids_loaded
  end


  # parses the given ICEcat product document and returns the product loaded.
  # returns nil if there is any error (such as a bogus document).
  def self.load_product(filename)
    product_document = Hotcat::ProductDocument.new
    parser = Nokogiri::XML::SAX::Parser.new(product_document)
    if filename.end_with?(".gz")
      parser.parse(Zlib::GzipReader.open(filename))
    else
      parser.parse(File.open(filename))
    end

    # ICEcat returned a document that itself has an error. Most likely that we
    # don't have the rights to download the given product.
    product = product_document.product if product_document.code != "-1"

    if product.blank? || product.keys.empty? || product[:properties].empty?
      nil
    else
      product
    end
  end


  private


  def skip_output
    @skip_output
  end


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


  def product_id_attribute
    Hotcat::SalsifyProductsLoader.default_product_id_property
  end


  def product_id(product)
    product[:properties][product_id_attribute]
  end


  # return whether to bother processing the product we just parsed
  def process_product?(product)
    id = product_id(product)
    return false if id.blank? ||
                    @product_ids_loaded.include?(id)

    return false if @product_id_whitelist.present? && !@product_id_whitelist.include?(id)

    return @category_whitelist.blank? ||
           (product[:category].present? && @category_whitelist.include?(product[:category].to_s))
  end


  # returns list of accessory IDs
  def get_accessory_ids(product)
    return nil if @max_related_products == 0 ||
                  product[:related_product_ids_suppliers].empty?

    accessory_ids = Set.new

    # sorting here to prevent, as much as possible having to download new
    # documents every single time.
    product[:related_product_ids_suppliers].keys.sort.each do |id|
      next if @product_id_whitelist.present? && !@product_id_whitelist.include?(id)

      accessory_ids.add(id)
      supplier = product[:related_product_ids_suppliers][id]
      @related_product_ids_suppliers[id] = supplier if @related_product_ids_suppliers[id].blank?

      break if @max_related_products > 0 && accessory_ids.length >= @max_related_products
    end

    accessory_ids
  end


  def get_image_url(product)
    return nil if @skip_digital_assets || product[:image_url].blank?
    url = product[:image_url].strip
    url = @aws_uploader.upload(product_id(product), url) if @aws_uploader.present?
    url
  end


  def convert_product(product)
    product[:accessory_ids] = get_accessory_ids(product)
    product[:image_url] = get_image_url(product)

    product[:properties].keys.each do |key|
      @attribute_ids_loaded.add(key.to_s.strip)
    end

    write_product(product) unless skip_output

    product_id(product)
  end


  def write_product(product)
    raise Hotcat::SalsifyWriterError, "Must override write_product in subclass"
  end

end