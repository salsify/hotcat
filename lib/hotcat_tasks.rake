require 'uri'
require 'net/http'
require 'nokogiri'
require 'active_support/ordered_options'

require "hotcat/error"
require "hotcat/config"
require "hotcat/version"
require "hotcat/icecat"
require "hotcat/salsify_document_writer"
require "hotcat/icecat_supplier_document"
require "hotcat/icecat_category_document"
require "hotcat/salsify_category_writer"
require "hotcat/icecat_index_document.rb"
require "hotcat/icecat_product_document.rb"
require "hotcat/salsify_products_writer.rb"

# TODO: task to download the daily update

namespace :hotcat do

  # subdirectories in the local cache for various pieces of the ICEcat data
  REFS_DIR = "refs#{File::SEPARATOR}"
  INDEX_DIR = "indexes#{File::SEPARATOR}"
  PRODUCTS_DIRECTORY = "product_cache#{File::SEPARATOR}"

  SALSIFY_PREFIX = "salsify-"
  SALSIFY_DIR = "salsify#{File::SEPARATOR}"


  # ICEcat category ID for digital cameras
  CAMERA_CATEGORY_ICECAT_ID = "575"


  def ensure_directory(path)
    if !File.exist?(path)
      return Dir.mkdir(path)
    elsif !File.directory?(path)
      return false
    end
    true
  end

  # Ensures that all required configuration has been set.
  task :setup => [:environment] do
    @config = Hotcat::Configuration

    dir = @config.cache_dir + REFS_DIR
    if !ensure_directory(dir)
      puts "ERROR: #{dir} not a directory. Quitting."
      exit
    end

    dir = @config.cache_dir + INDEX_DIR
    if !ensure_directory(dir)
      puts "ERROR: #{dir} not a directory. Quitting."
      exit
    end

    dir = @config.cache_dir + PRODUCTS_DIRECTORY
    if !ensure_directory(dir)
      puts "ERROR: #{dir} not a directory. Quitting."
      exit
    end

    dir = @config.cache_dir + SALSIFY_DIR
    if !ensure_directory(dir)
      puts "ERROR: #{dir} not a directory. Quitting."
      exit
    end
  end


  # return whether successful
  def download_to_local(uri, filename, retry_download = true, auth_required = true, indent = '')
    puts "#{indent}Downloading from <#{uri.to_s}>"
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(@config.username, @config.password) if auth_required
    response = http.request(req)
    if response.code == "200" then
      puts "#{indent}Download successful. saving to <#{filename}>"

      # Ensure that we're storing the document compressed locally.
      if !uri.to_s.end_with?(".gz") && filename.ends_with?(".gz")
        File.open("#{filename}", "wb") do |file|
          gz = Zlib::GzipWriter.new(file)
          gz.write(response.body)
          gz.close
        end
      else
        # We've already got a .gz file most likely. In the past this was also
        # used to cache local versions of the images from ICEcat.
        File.open(filename, "wb") { |file| file.write(response.body) }
      end

      filename
    else
      puts "#{indent}  ERROR: HTTP RESPONSE #{response.code}"
      if retry_download then
        puts "#{indent}  Retrying..."
        return download_to_local(uri, filename, false, auth_required, indent)
      end
      nil
    end
  rescue Exception => e
    puts "#{indent}  ERROR: Failure downloading from <#{uri.to_s}>. Skipping. Details:"
    puts "#{indent}    #{e.inspect}\n#{e.backtrace.join("\n")}"
  end

  # task :test_download => [:environment] do
  #   uri = URI("http://data.icecat.biz/xml_s3/xml_server3.cgi?prod_id=PX1268E-1G40;vendor=toshiba;lang=en;output=productxml")
  #   file = "lib/assets/icecat/product_cache/http%3A%2F%2Fdata.icecat.biz%2Fxml_s3%2Fxml_server3.cgi%3Fprod_id%3DPX1268E-1G40%3Bvendor%3Dtoshiba%3Blang%3Den%3Boutput%3Dproductxml"
  #   download_to_local(uri, file, false)
  # end


  # Local cache of supplier data that's cross-referenced in a bunch of places.
  @suppliers = {}

  # Local cache of category data that's cross-referenced in products.
  @categories = {}


  def load_supplier_hash()
    file = "#{@config.cache_dir}#{REFS_DIR}#{Hotcat::SupplierDocument.filename}"
    if not File.exists?(file) then
      puts "Suppliers XML is not locally cached. Fetching."
      uri = URI("#{Hotcat::Icecat.refs_url}#{Hotcat::SupplierDocument.filename}")
      download_to_local(uri, file, true, true, "    ")
    end

    puts "Building Supplier hash for cross-referencing."
    @suppliers = {}
    supplier_document = Hotcat::SupplierDocument.new
    parser = Nokogiri::XML::SAX::Parser.new(supplier_document)
    if file.end_with?("gz")
      parser.parse(Zlib::GzipReader.open(file))
    else
      parser.parse(File.open(file))
    end
    @suppliers = supplier_document.suppliers
    puts "Done loading suppliers. #{@suppliers.keys.length} loaded."
  end

  desc "Loads supplier list into a local hash for cross-referencing. Makes no updates to the database."
  task :load_suppliers  => ["hotcat:setup"] do
    load_supplier_hash
  end


  def load_categories_hash()
    file = "#{@config.cache_dir}#{REFS_DIR}#{Hotcat::CategoryDocument.filename}"
    if not File.exists?(file) then
      puts "Categories XML is not locally cached. Fetching."
      uri = URI("#{Hotcat::Icecat.refs_url}#{Hotcat::CategoryDocument.filename}")
      download_to_local(uri, file, true, true, "    ")
    end

    puts "Parsing category document #{file}"
    @categories = {}
    category_document = Hotcat::CategoryDocument.new
    parser = Nokogiri::XML::SAX::Parser.new(category_document)
    if file.end_with?(".gz")
      parser.parse(Zlib::GzipReader.open(file))
    else
      parser.parse(File.open(file))
    end
    @categories = category_document.categories
  end

  desc "Loads the ICEcat category hierarchy into memory."
  task :load_categories => ["hotcat:setup"] do
    start_time = Time.now

    load_categories_hash

    puts "********************************************************************************************************"
    puts "Done loading categories."
    puts "#{@categories.keys.length} categories loaded."
    puts "Total job time in seconds: #{Time.now - start_time}"
  end

  desc "Convert the loaded category data into Salsify format."
  task :convert_categories => ["hotcat:setup"] do
    start_time = Time.now

    load_categories_hash

    if @categories.empty?
      puts "ERROR: no categories loaded. Something has gone wrong."
    else
      ofile = "#{SALSIFY_PREFIX}#{Hotcat::SalsifyCategoryWriter.filename}"
      ofile << ".gz" unless ofile.end_with?(".gz")
      output_file = "#{@config.cache_dir}#{SALSIFY_DIR}#{ofile}"
      puts "Writing categories to #{output_file}"
      Hotcat::SalsifyCategoryWriter.new(@categories, output_file).write
    end

    puts "********************************************************************************************************"
    puts "Done printing out Salsify category document."
    puts "Total job time in seconds: #{Time.now - start_time}"
  end


  def category_is_descendant_of(category, ancestor_id)
    while !category.nil?
      return true if category[:parent_id] == ancestor_id
      category = @categories[category[:parent_id]]
    end
    false
  end

  # Totally inefficient. Totally fine.
  def category_and_descendants(root_id)
    if @categories.nil? || @categories.empty?
      load_categories_hash
    end

    cats = []
    @categories.each_pair do |id, category|
      if id == root_id || cats.include?(category[:parent_id])
        cats.push(id)
      elsif category_is_descendant_of(category, root_id)
        cats.push(id)
        while !category.nil?
          parent_id = category[:parent_id]
          cats.push(parent_id) unless cats.include?(parent_id)
          category = @categories[parent_id]
        end
      end
    end
    cats
  end



  # Uses the ICEcat query interface instead. There is also a URL path that can
  # be used, but from the index documents we don't get that. We only get the ID
  # and a supplier ID, which requires the query interface.
  #
  # Actually, the supplier ID is the only reason we're actively loading the
  # suppliers at all in this document.
  def product_icecat_query_uri(product_id, supplier_name)
    encoded_id = URI.encode_www_form_component(product_id)
    encoded_supplier = URI.encode_www_form_component(supplier_name.downcase)
    URI("http://data.icecat.biz/xml_s3/xml_server3.cgi?prod_id=#{encoded_id};vendor=#{encoded_supplier};lang=en;output=productxml")
  end

  PRODUCT_FILENAME_PREFIX = 'product_'
  PRODUCT_FILENAME_SUFFIX = '.xml.gz'
  def product_file_name(product_id)
    return nil if product_id == nil
    @config.cache_dir + PRODUCTS_DIRECTORY + PRODUCT_FILENAME_PREFIX + URI.encode_www_form_component(product_id) + PRODUCT_FILENAME_SUFFIX
  end

  # This is the inverse of the above function. From a filename it gets the
  # the product ID. This is used for iterating across all the files in a
  # directory.
  def product_id_from_filename(filename)
    match = /#{PRODUCT_FILENAME_PREFIX}(?<encoded_id>\w+)#{PRODUCT_FILENAME_SUFFIX}/.match filename
    return nil if not match
    URI.decode_www_form_component(match[:encoded_id])
  end

  def product_file?(product_id)
    return File.exists?(product_file_name(product_id))
  end

  def build_product_cache(file, valid_category_ids = nil, max_products = nil)
    puts "Reading max #{max_products} products from index file #{file}."

    index_document = Hotcat::IndexDocument.new(valid_category_ids, max_products)
    parser = Nokogiri::XML::SAX::Parser.new(index_document)
    if file.end_with?("gz")
      parser.parse(Zlib::GzipReader.open(file))
    else
      parser.parse(File.open(file))
    end
    
    puts "  Total products in file: #{index_document.total}"
    puts "  Total valid found: #{index_document.total_valid}"

    puts "Ensuring product detail documents are saved locally."

    already_downloaded = 0
    total_downloaded = 0
    total_downloaded_failed = 0
    index_document.products.each do |p|
      prod_id = p[:id]
      if product_file?(prod_id) then
        already_downloaded += 1
        puts "  #{total_downloaded}: Local file exists for #{prod_id}"
      else
        puts "  #{total_downloaded}: Downloading data file for product #{prod_id}"
        product_details_uri = URI("http://#{Hotcat::Icecat.data_url}/#{p[:path]}")
        if download_to_local(product_details_uri, product_file_name(prod_id), true, true, "    ")
          total_downloaded += 1
        else
          total_downloaded_failed += 1
        end
      end
    end

    puts "Product cache building results:"
    puts "  Downloaded #{total_downloaded} products."
    puts "  Failed to download #{total_downloaded_failed} products that we don't already have locally."
    puts "  Already had locally #{already_downloaded} product files."
    puts "  Total number of locally cached products: #{total_downloaded + already_downloaded}"
  end

  desc "Download ICEcat data about Cameras to local cache."
  task :build_product_camera_cache => ["hotcat:setup"] do
    start_time = Time.now

    file = "#{@config.cache_dir}#{INDEX_DIR}#{Hotcat::IndexDocument.full_index_local_filename}"
    if not File.exists?(file) then
      puts "Full Index XML is not locally cached. Fetching."
      uri = URI("#{Hotcat::Icecat.indexes_url}#{Hotcat::IndexDocument.full_index_remote_filename}")
      if !download_to_local(uri, file, true, true, "    ")
        puts "ERROR: could not download index locally. Aborting."
        exit
      end
    end

    valid_category_ids = category_and_descendants(CAMERA_CATEGORY_ICECAT_ID)

    build_product_cache(file, valid_category_ids, @config.max_products)

    puts "********************************************************************************************************"
    puts "DONE."
    puts "Total job time in seconds: #{Time.now - start_time}"
  end


  desc "Converts all the products in the products directory into Salsify XML files."
  task :convert_products => ["hotcat:setup"] do
    products_directory = @config.cache_dir + PRODUCTS_DIRECTORY

    products_filename = @config.cache_dir + SALSIFY_DIR + "#{SALSIFY_PREFIX}products.json.gz"
    if File.exist?(products_filename)
      puts "WARNING: products file exists. Renaming to backup before continuing."
      newname = @config.cache_dir + SALSIFY_DIR + "#{SALSIFY_PREFIX}products-#{Time.now.to_i}.json.gz"
      File.rename(products_filename, newname)
    end

    puts "Converting all products found in files in directory #{products_directory}."
    puts "Storing products in #{products_filename}"
    puts "Storing relations (max #{@config.max_related_products} per product)"

    converter = Hotcat::SalsifyProductsWriter.new(products_directory,
                                                  nil,
                                                  products_filename,
                                                  @config.max_products,
                                                  @config.max_related_products)
    converter.convert

    puts "Done writing documents. Ensuring that related product documents are loaded."
    files = []
    converter.related_product_ids_suppliers.each_pair do |id, supplier|
      filename = product_file_name(id)
      unless File.exist?(filename)
        filename = product_file_name(id)
        uri = product_icecat_query_uri(id, supplier)
        unless download_to_local(uri, filename, true, true, indent = '  ')
          puts "  WARNING: could not download to local file for product #{id}"
        end
      end
      files.push(filename)
    end

    related_products_filename = @config.cache_dir + SALSIFY_DIR + "#{SALSIFY_PREFIX}products-related.json.gz"
    if File.exist?(related_products_filename)
      puts "WARNING: related products file exists. Renaming to backup before continuing."
      newname = @config.cache_dir + SALSIFY_DIR + "#{SALSIFY_PREFIX}products-related-#{Time.now.to_i}.json.gz"
      File.rename(related_products_filename, newname)
    end
    puts "Converting the necessary related products."
    converter = Hotcat::SalsifyProductsWriter.new(products_directory,
                                                  files,
                                                  related_products_filename,
                                                  0,
                                                  0)
    converter.convert

    puts "Done converting products and related products."
  end

end