require 'set'
require 'uri'
require 'net/http'

require 'nokogiri'
require 'active_support/ordered_options'

require "hotcat/error"
require "hotcat/config"
require "hotcat/version"
require "hotcat/icecat"
require "hotcat/salsify_csv_writer"
require "hotcat/salsify_document_writer"
require "hotcat/salsify_index_writer"
require "hotcat/salsify_attributes_writer"
require "hotcat/icecat_supplier_document"
require "hotcat/icecat_category_document"
require "hotcat/salsify_category_writer"
require "hotcat/icecat_index_document.rb"
require "hotcat/icecat_product_document.rb"
require "hotcat/salsify_products_writer.rb"
require "hotcat/aws_uploader"


namespace :hotcat do

  # subdirectories in the local cache for various pieces of the ICEcat data
  REFS_DIR = "refs#{File::SEPARATOR}"
  INDEX_DIR = "indexes#{File::SEPARATOR}"
  PRODUCTS_DIRECTORY = "product_cache#{File::SEPARATOR}"

  SALSIFY_PREFIX = "salsify-"
  SALSIFY_DIR = "salsify#{File::SEPARATOR}"


  # ICEcat category ID for digital cameras
  CAMERA_CATEGORY_ICECAT_ID = "575"

  def whitelist_trigger_categories
    valid_category_ids = category_and_descendants(CAMERA_CATEGORY_ICECAT_ID)
    valid_category_ids.map { |cid| cid.to_s }
  end


  def ensure_directory(path)
    if !File.exist?(path)
      return FileUtils.makedirs(path)
    elsif !File.directory?(path)
      return false
    end
    true
  end


  def output_filename(basename)
    basename << ".gz" if basename.end_with?(".json")
    "#{@config.cache_dir}#{SALSIFY_DIR}#{SALSIFY_PREFIX}#{basename}"
  end

  def archive_file_if_needed(filename, archive_filename)
    if File.exist?(filename)
      puts "#{filename} exists. Renaming to #{archive_filename} before continuing."
      File.rename(filename, archive_filename)
    end
  end

  def attributes_filename
    output_filename(Hotcat::SalsifyAttributesWriter.filename)
  end

  def attributes_list_filename
    output_filename("attributes_list.txt")
  end

  def attributes_list_archive_filename
    output_filename("attributes_list-#{Time.now.to_i}.txt")
  end

  def attribute_values_filename
    output_filename(Hotcat::SalsifyCategoryWriter.filename)
  end

  def products_filename_extension(mode)
    if mode == :json
      '.json.gz'
    elsif mode == :csv
      '.csv'
    end
  end

  def products_filename(mode)
    output_filename("products#{products_filename_extension(mode)}")
  end

  def products_archive_filename(mode)
    output_filename("products-#{Time.now.to_i}#{products_filename_extension(mode)}")
  end

  def accessories_filename(mode)
    output_filename("accessories#{products_filename_extension(mode)}")
  end

  def accessories_archive_filename(mode)
    output_filename("accessories-#{Time.now.to_i}#{products_filename_extension(mode)}")
  end

  def import_filename
    output_filename("import.zip")
  end

  def import_archive_filename
    output_filename("import-#{Time.now.to_i}.zip")
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

    if @config.use_aws_for_images
      if @config.aws_bucket_id.blank?
        puts "ERROR: if you specify use_aws_for_images a aws_bucket_id must be provided."
        exit
      end

      if @config.aws_key_id.blank?
        puts "ERROR: if you specify use_aws_for_images a aws_key_id must be provided."
        exit
      end

      if @config.aws_key.blank?
        puts "ERROR: if you specify use_aws_for_images a aws_key must be provided."
        exit
      end

      dir = @config.cache_dir + 'tmp'
      if !ensure_directory(dir)
        puts "ERROR: #{dir} not a directory. Quitting."
        exit
      end

      @aws_uploader = Hotcat::AwsUploader.new(@config.aws_key_id,
                                              @config.aws_key,
                                              @config.aws_bucket_id,
                                              dir)
    end

    @attribute_ids = Set.new
    @attr_list_file = ENV['attributes']
  end


  # return whether successful
  def download_to_local(uri, filename, retry_download = true, auth_required = true, indent = '')
    puts "#{indent}Downloading from <#{uri.to_s}>"
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(@config.username, @config.password) if auth_required
    response = http.request(req)
    if response.code == "200"
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
      if retry_download
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
    unless File.exists?(file)
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
  task :load_suppliers => ["hotcat:setup"] do
    load_supplier_hash
  end


  desc "Creates the Salsify attributes file, overwriting if necessary."
  task :convert_attributes => ["hotcat:setup"] do
    output_file = attributes_filename
    puts "Writing attributes to #{output_file}"

    if File.exists?(output_file)
      puts "WARNING: attributes file already exists. Replacing."
      File.delete(output_file)
    end

    converter = Hotcat::SalsifyAttributesWriter.new(output_file)
    converter.write

    @attribute_ids.merge(converter.attributes)

    puts "Done writing attributes file."
  end


  def load_categories_hash()
    file = "#{@config.cache_dir}#{REFS_DIR}#{Hotcat::CategoryDocument.filename}"
    unless File.exists?(file)
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
      output_file = attribute_values_filename
      puts "Writing categories to #{output_file}"
      if File.exists?(output_file)
        puts "WARNING: #{output_file} exists. Replacing."
        File.delete(output_file)
      end
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
    return nil unless match
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
      if product_file?(prod_id)
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
    unless File.exists?(file)
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
    convert_products_to_salsify(:json)
  end

  desc "Generates a Salsify CSV import."
  task :generate_salsify_csv_import => ["hotcat:setup","hotcat:load_suppliers","hotcat:load_categories"] do
    if @attr_list_file.blank? || !File.exists?(@attr_list_file)
      raise Hotcat::SalsifyWriterError, "Require an attributes file for CSV writing."
    end

    @attributes_list = []
    File.open(@attr_list_file, 'r') do |f|
      f.each_line { |a| @attributes_list.push(a.strip) unless a.blank? }
    end

    puts "Read in attributes list from #{@attr_list_file}. #{@attributes_list.length} columns loaded."
    convert_products_to_salsify(:csv)
  end

  def convert_products_to_salsify(mode)
    products_directory = @config.cache_dir + PRODUCTS_DIRECTORY

    products_file = products_filename(mode)
    archive_file_if_needed(products_file, products_archive_filename(mode))

    puts "Converting at most #{@config.max_products} trigger products found in files in directory #{products_directory}."
    puts "Storing products in #{products_file}"
    puts "Storing relations (max #{@config.max_related_products} per product)"

    products_writer_settings = {
      source_directory: products_directory,
      output_file: products_file,
      category_whitelist: whitelist_trigger_categories,
      max_products: @config.max_products,
      max_related_products: @config.max_related_products,
      aws_uploader: @aws_uploader
    }
    if mode == :json
      converter = Hotcat::SalsifyProductsWriter.new(products_writer_settings)
    elsif mode == :csv
      products_writer_settings[:categories] = @categories
      products_writer_settings[:attributes_list] = @attributes_list
      converter = Hotcat::SalsifyCsvWriter.new(products_writer_settings)
    end
    converter.convert
    if mode == :json
      @attribute_ids.merge(converter.attributes)
    end

    puts "Done writing documents. Ensuring that related product documents are loaded."
    files = []
    converter.related_product_ids_suppliers.each_pair do |id, supplier|
      filename = product_file_name(id)
      unless File.exists?(filename)
        filename = product_file_name(id)
        uri = product_icecat_query_uri(id, supplier)
        unless download_to_local(uri, filename, true, true, indent = '  ')
          puts "  WARNING: could not download to local file for product #{id}"
        end
      end
      files.push(filename)
    end

    related_products_filename = accessories_filename(mode)
    archive_file_if_needed(related_products_filename, accessories_archive_filename(mode))

    puts "Converting the necessary related products."

    accessory_writer_settings = {
      source_directory: products_directory,
      files_whitelist: files,
      output_file: related_products_filename,
      aws_uploader: @aws_uploader
    }
    if mode == :json
      converter = Hotcat::SalsifyProductsWriter.new(accessory_writer_settings)
    elsif mode == :csv
      accessory_writer_settings[:categories] = @categories
      accessory_writer_settings[:attributes_list] = @attributes_list
      converter = Hotcat::SalsifyCsvWriter.new(accessory_writer_settings)
    end
    converter.convert

    if mode == :json
      @attribute_ids.merge(converter.attributes)
      merge_product_json_files(products_file, related_products_filename)
    elsif mode == :csv
      puts "merging CSV files"
      merge_product_csv_files(products_file, related_products_filename)
    end

    puts "Done converting products and related products."
  end

  def merge_product_json_files(products_file, related_products_filename)
    # At this point we have 2 documents which are long lists of products, but
    # to be consumed by Salsify they have to be combined into one until Salsify
    # can handle multiple product import documents coming from a single source.
    tmp_filename = File.join(File.dirname(products_file), "#{Time.now.to_i}-#{File.extname(products_file)}")
    File.open(tmp_filename, 'wb') do |output_file|
      output_file = Zlib::GzipWriter.new(output_file) if tmp_filename.end_with?(".gz")
      output_file << "[\n"
      copy_file_contents(output_file, products_file)
      output_file << "\n,\n"
      copy_file_contents(output_file, related_products_filename)
      output_file << "\n]"
    end
    File.delete(products_file)
    File.delete(related_products_filename)
    File.rename(tmp_filename, products_file)
  end

  def merge_product_csv_files(products_file, related_products_filename)
    tmp_filename = File.join(File.dirname(products_file), "#{Time.now.to_i}-#{File.extname(products_file)}")
    File.open(tmp_filename, 'wb') do |file|
      File.open(products_file, 'rb').each do |line|
        next if line.blank?
        file << line.strip << "\n"
      end
      File.open(related_products_filename, 'rb').each_with_index do |line, index|
        next if index == 0 || line.blank?
        file << line.strip << "\n"
      end
    end
    File.delete(products_file)
    File.delete(related_products_filename)
    File.rename(tmp_filename, products_file)
  end

  def copy_file_contents(output_stream, input_file)
    input_stream = if input_file.ends_with?(".gz")
      Zlib::GzipReader.open(input_file)
    else
      File.open(input_file, "rb")
    end

    begin
      while bytes = input_stream.read(4096)
        output_stream << bytes
      end
    ensure
      input_stream.close
    end
  end


  desc "Generates a complete Salsify import from ICEcat data"
  task :generate_salsify_import => ["hotcat:setup","hotcat:convert_attributes","hotcat:convert_categories","hotcat:convert_products"] do
    import_file = import_filename
    puts "Generating Salsify import document at #{import_file}"
    archive_file_if_needed(import_file, import_archive_filename)

    Hotcat::SalsifyIndexWriter.new(
      import_file,
      attributes_filename,
      attribute_values_filename,
      products_filename(:json)
    ).write
    puts "Done creating import document: #{import_file}"

    puts "Writing out all attributes seen into list file."
    write_attributes_list_file
    puts "Done."
  end


  def write_attributes_list_file
    attributes_list_file = attributes_list_filename
    archive_file_if_needed(attributes_list_file, attributes_list_archive_filename)
    File.open(attributes_list_file, 'w') do |f|
      @attribute_ids.each { |aid| f << aid << "\n" }
    end
  end

end