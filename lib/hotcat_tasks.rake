require 'set'
require 'uri'
require 'net/http'

require 'nokogiri'
require 'active_support/ordered_options'

require "hotcat/error"
require "hotcat/config"
require "hotcat/version"
require "hotcat/cache_manager"
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


# TODO factor out the job running into its own class. This is getting silly.
#      in particular CacheManager feels like a very strong candidate for a
#      separable concern which would clean this up remarkably.

# TODO be smarter about when we build the product cache. We should possibly
#      organize them by category into subdirectories, as this would make it
#      far faster to load csvs.


namespace :hotcat do

  # FIXME is this really required?
  SALSIFY_PREFIX = "salsify-"

  # ICEcat category ID for digital cameras
  CAMERA_CATEGORY_ICECAT_ID = "575"

  def whitelist_trigger_categories
    valid_category_ids = category_and_descendants(CAMERA_CATEGORY_ICECAT_ID)
    valid_category_ids.map { |cid| cid.to_s }
  end


  def output_filename(basename)
    basename << ".gz" if basename.end_with?(".json")
    File.join(@cache.generated_files_directory, "#{SALSIFY_PREFIX}#{basename}")
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

    @cache = Hotcat::CacheManager.configure(@config.cache_dir)

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

      @aws_uploader = Hotcat::AwsUploader.new(@config.aws_key_id,
                                              @config.aws_key,
                                              @config.aws_bucket_id,
                                              @cache.tmp_directory)
    end

    # keeps track of all attribute IDs seen throughout the import
    @attribute_ids = Set.new

    # if provided, this is a whitelist of attribute IDs to use when generating
    # CSV output
    @attr_list_file = ENV['attributes']

    @load_images = ENV["load_images"]
    if @load_images.present? && @load_images != 'true'
      puts "No images will be loaded."
      @load_images = false
    else
      @load_images = true
    end
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
    file = File.join(@cache.reference_files_directory, Hotcat::SupplierDocument.filename)
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
    file = File.join(@config.reference_files_directory, Hotcat::CategoryDocument.filename)
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

    puts "*********************************************************************"
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

    puts "*********************************************************************"
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
      if @cache.local_file_for_product_id?(prod_id)
        already_downloaded += 1
        puts "  #{total_downloaded}: Local file exists for #{prod_id}"
      else
        puts "  #{total_downloaded}: Downloading data file for product #{prod_id}"
        product_details_uri = URI("http://#{Hotcat::Icecat.data_url}/#{p[:path]}")
        prod_file = @cache.new_local_file_for_product_id(prod_id)
        if download_to_local(product_details_uri, prod_file, true, true, "    ")
          total_downloaded += 1
        else
          total_downloaded_failed += 1
        end
      end
    end

    puts "Organizing local cache."
    @cache.organize_product_files

    puts "Product cache building results:"
    puts "  Downloaded #{total_downloaded} products."
    puts "  Failed to download #{total_downloaded_failed} products that we don't already have locally."
    puts "  Already had locally #{already_downloaded} product files."
    puts "  Total number of locally cached products: #{total_downloaded + already_downloaded}"
  end

  desc "Download ICEcat data about Cameras to local cache."
  task :build_product_camera_cache => ["hotcat:setup"] do
    start_time = Time.now

    file = File.join(@cache.product_index_files_directory, Hotcat::IndexDocument.full_index_local_filename)
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

    puts "*********************************************************************"
    puts "DONE."
    puts "Total job time in seconds: #{Time.now - start_time}"
  end


  desc "Organizes the local cache for better performance."
  task :organize_cache => ["hotcat:setup"] do
    puts "Organizing local cache."
    @cache.organize_product_files
  end


  desc "Converts all the products in the products directory into Salsify XML files."
  task :convert_products => ["hotcat:setup"] do
    convert_products_to_salsify(:json)
  end

  desc "Generates a Salsify CSV import."
  task :generate_salsify_csv_import => ["hotcat:setup","hotcat:load_suppliers","hotcat:load_categories"] do
    if @attr_list_file.present?
      if !File.exists?(@attr_list_file)
        raise Hotcat::SalsifyWriterError, "Specified attribute list file does not exist: #{@attr_list_file}"
      end
      @attributes_whitelist = []
      File.open(@attr_list_file, 'r') do |f|
        f.each_line { |a| @attributes_whitelist.push(a.strip) unless a.blank? }
      end
      puts "Read in attributes whitelist from #{@attr_list_file}. #{@attributes_whitelist.length} columns loaded."
    end

    puts "Performing dry run to get enough information to build the CSV..."
    load_info = convert_products_to_salsify(:csv, true)

    puts "Done performing dry run. Now doing actual conversion..."
    load_info = convert_products_to_salsify(:csv, false, load_info)

    puts "Done."
  end


  # a load_info keeps track of load information, such as failed files,
  # successfully loaded product IDs, etc.
  def update_load_info(load_info, converter, product_type)
    load_info ||= {
      good_product_ids: Set.new,
      failed_files: Set.new,
      accessory_category_ids: Set.new,
      product_category_mapping: Hash.new
    }

    load_info[:failed_files].merge(converter.product_files_failed)
    load_info[:good_product_ids].merge(converter.product_ids_loaded)
    load_info[:product_category_mapping].merge(converter.product_category_mapping)

    if product_type == :trigger
      load_info[:trigger_files] = converter.product_files_succeeded
      load_info[:accessory_product_ids] = converter.related_product_ids_suppliers.keys
    elsif product_type == :target
      load_info[:target_files] = converter.product_files_succeeded
      load_info[:accessory_category_ids].merge(converter.category_ids_loaded)
    end

    @attribute_ids.merge(converter.attribute_ids_loaded)

    load_info
  end

  def convert_products_to_salsify(mode, dryrun = false, load_info = nil)
    puts "Processing at most #{@config.max_products} trigger products."

    skip_digital_assets = dryrun || !@load_images

    unless dryrun
      products_file = products_filename(mode)
      puts "Storing products in #{products_file}"
      archive_file_if_needed(products_file, products_archive_filename(mode))

      attr_whitelist = @attribute_ids
      if @attributes_whitelist.present?
        attr_whitelist = attr_whitelist & @attributes_whitelist
      end
    end

    products_writer_settings = {
      skip_output: dryrun,
      skip_digital_assets: skip_digital_assets,
      output_file: products_file,
      categories: @categories,
      category_whitelist: whitelist_trigger_categories,
      max_products: @config.max_products,
      max_related_products: @config.max_related_products,
      aws_uploader: @aws_uploader
    }
    if load_info.present?
      # already been through once
      products_writer_settings.merge!({
        files_whitelist: load_info[:trigger_files],
        product_files_blacklist: load_info[:failed_files],
        product_id_whitelist: load_info[:good_product_ids],
        product_category_mapping: load_info[:product_category_mapping]
      })
    end
    if mode == :json
      converter = Hotcat::SalsifyProductsWriter.new(products_writer_settings)
    elsif mode == :csv
      unless dryrun
        products_writer_settings.merge!({
          accessory_category_ids: load_info[:accessory_category_ids],
          attributes_list: attr_whitelist  
        })
      end
      converter = Hotcat::SalsifyCsvWriter.new(products_writer_settings)
    end
    converter.convert
    load_info = update_load_info(load_info, converter, :trigger)


    if load_info[:target_files].present?
      files = load_info[:target_files]
    else
      # TODO this should all be happening in the cache manager transparently

      "Ensuring that related product documents are downloaded."
      files = []
      converter.related_product_ids_suppliers.each_pair do |id, supplier|
        next if @cache.invalid_product_file_for_product_id(id)

        file = @cache.valid_product_file_for_product_id(id)
        if file.nil?
          # download to local
          file = @cache.new_local_file_for_product_id(id)
          uri = product_icecat_query_uri(id, supplier)
          if !download_to_local(uri, file, true, true, indent = '  ')
            load_info[:good_product_ids].delete(id)
            next
          end
        end
        files.push(file)
      end
    end


    puts "Processing the related products files..."
    puts "Storing relations (max #{@config.max_related_products} per trigger product)"

    unless dryrun
      related_products_filename = accessories_filename(mode)
      archive_file_if_needed(related_products_filename, accessories_archive_filename(mode))
    end

    accessory_writer_settings = {
      skip_output: dryrun,
      skip_digital_assets: skip_digital_assets,
      files_whitelist: files,
      output_file: related_products_filename,
      categories: @categories,
      max_products: -1,
      max_related_products: 0,
      aws_uploader: @aws_uploader,
      product_files_blacklist: load_info[:failed_files]
    }
    accessory_writer_settings[:product_files_blacklist] = load_info[:failed_files]
    accessory_writer_settings[:product_category_mapping] = load_info[:product_category_mapping]
    if mode == :json
      converter = Hotcat::SalsifyProductsWriter.new(accessory_writer_settings)
    elsif mode == :csv
      unless dryrun
        # this isn't required for json since we're only doing one run through
        # the system to generate the json document

        accessory_writer_settings.merge!({
          product_id_whitelist: load_info[:accessory_product_ids],
          accessory_category_ids: load_info[:accessory_category_ids],
          attributes_list: attr_whitelist
        })
      end
      converter = Hotcat::SalsifyCsvWriter.new(accessory_writer_settings)
    end
    converter.convert
    load_info = update_load_info(load_info, converter, :target)


    merge_product_files(mode, products_file, related_products_filename) unless dryrun
    puts "Done converting products and related products."

    puts "Writing out all attributes seen into list file."
    write_attributes_list_file unless dryrun


    load_info
  end


  def merge_product_files(mode, products_file, related_products_filename)
    if mode == :json
      merge_product_json_files(products_file, related_products_filename)
    elsif mode == :csv
      puts "merging CSV files"
      merge_product_csv_files(products_file, related_products_filename)
    end
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