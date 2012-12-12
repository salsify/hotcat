require 'uri'
require 'net/http'
require 'nokogiri'
require 'active_support/ordered_options'

require 'hotcat'
require 'hotcat/icecat'
require 'hotcat/icecat_index_document'
require 'hotcat/icecat_product_document'
require 'hotcat/icecat_supplier_document'
require 'hotcat/icecat_category_document'

# TODO: task to download the daily update
# TODO: have a task to delete the local cache
# TODO: zip up the local XML files and figure out how to parse them with nokogiri

namespace :hotcat do

  task :setup => [:environment] do
    config = Hotcat::Configuration
    puts "domain: #{config.icecat_domain}"

    # FIXME: here
    # hotcat.builder = Requirejs::Rails::Builder.new(hotcat.config)
  end


  ICECAT_USERNAME = ENV['ICECAT_USERNAME']
  ICECAT_PASSWORD = ENV['ICECAT_PASSWORD']
  ICECAT_DOMAIN = "data.icecat.biz"

  # I downloaded the first 370 products in 2012-09-05
  ICECAT_MAX = 371

  # The number of products whose related produts we should load
  ICECAT_RELATED_MAX = 200

  # The number of relations to load for the first ICECAT_RELATED_MAX products
  ICECAT_RELATED_MAX_PER_PRODUCT = 5

  DIRECTORY = 'db/data/icecat'
  DAILY_FILE = "#{DIRECTORY}/daily.index.xml"
  FULL_FILE = "#{DIRECTORY}/files.index.xml"
  CATEGORIES_FILE = "#{DIRECTORY}/CategoriesList.xml"
  SUPPLIERS_FILE = "#{DIRECTORY}/SuppliersList.xml"
  PRODUCTS_DIRECTORY = "#{DIRECTORY}/product_cache"
  IMAGE_DIRECTORY = ENV['ICECAT_IMAGES']
  IMAGE_URL_BASE = ENV['ICECAT_URL']

  IMAGE_PROPERTIES = {
    high: "High Resolution Picture URL Local",
    low: "Low Resolution Picture URL Local",
    thumb: "Thumbnail URL Local"
  }

  AWS_BUCKET = 'icecat'

  CAMERA_CATEGORY_ICECAT_ID = "571"

  @suppliers = {}
  def load_supplier_hash()
    puts "Building Supplier hash for cross-referencing. Note that this does not update anything in the database."
    @suppliers = {}
    supplier_document = SupplierDocument.new
    parser = Nokogiri::XML::SAX::Parser.new(supplier_document)
    parser.parse(File.open(SUPPLIERS_FILE))
    @suppliers = supplier_document.suppliers
    puts "Done loading suppliers. #{@suppliers.keys.length} loaded."
  end

  desc "Loads supplier list into a local hash for cross-referencing. Makes no updates to the database."
  task :load_suppliers do
    if not File.exists? SUPPLIERS_FILE then
      puts "ERROR: specified suppliers file does not exist <#{SUPPLIERS_FILE}>"
      break
    end

    load_supplier_hash
  end

  # builds a URI to the icecat file from the path property.
  # there is an alternative way using the query interface, which is covered in the next method.
  def product_icecat_path_uri(products, prod_id)
    prod_vals = products[prod_id]
    prod_doc_path = prod_vals['path'].sub('/INT/', '/EN/')
    URI("http://#{ICECAT_DOMAIN}/#{prod_doc_path}")
  end

  # uses the ICEcat query interface instead of the file paths.
  # very useful for related products which come with an ID and a supplier ID but nothing else...
  def product_icecat_query_uri(product_id, supplier_name)
    encoded_id = URI.encode_www_form_component(product_id)
    encoded_supplier = URI.encode_www_form_component(supplier_name.downcase)
    URI("http://data.icecat.biz/xml_s3/xml_server3.cgi?prod_id=#{encoded_id};vendor=#{encoded_supplier};lang=en;output=productxml")
  end

  PRODUCT_FILENAME_PREFIX = 'product_'
  PRODUCT_FILENAME_SUFFIX = '.xml'
  def product_file_name(product_id)
    return nil if product_id == nil
    PRODUCTS_DIRECTORY + '/' + PRODUCT_FILENAME_PREFIX + URI.encode_www_form_component(product_id) + PRODUCT_FILENAME_SUFFIX
  end
  # this is the inverse of the above function
  def product_id_from_filename(filename)
    match = /#{PRODUCT_FILENAME_PREFIX}(?<encoded_id>\w+)#{PRODUCT_FILENAME_SUFFIX}/.match filename
    return nil if not match
    URI.decode_www_form_component(match[:encoded_id])
  end

  def product_file?(product_id)
    return File.exists? product_file_name product_id
  end

  def image_name(url, parent_id, image_type, image_quality)
    image_type + '_' + URI.encode_www_form_component(parent_id) + "_" + image_quality + url[-4..-1].downcase
  end

  # return whether successfuls
  def download_to_local(uri, filename, retry_download = true, auth_required = true, indent = '')
    puts "#{indent}Downloading from <#{uri.to_s}>"
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(ICECAT_USERNAME, ICECAT_PASSWORD) if auth_required
    response = http.request(req)
    if response.code == "200" then
      puts "#{indent}Download successful. saving to <#{filename}>"
      open(filename, "wb") { |file| file.write(response.body) }
      true
    else
      puts "#{indent}  ERROR: HTTP RESPONSE #{response.code}"
      if retry_download then
        puts "#{indent}  Retrying..."
        return download_to_local(uri, filename, false)
      end
      false
    end
  end

  # task :test_download => [:environment] do
  #   uri = URI("http://data.icecat.biz/xml_s3/xml_server3.cgi?prod_id=PX1268E-1G40;vendor=toshiba;lang=en;output=productxml")
  #   file = "lib/assets/icecat/product_cache/http%3A%2F%2Fdata.icecat.biz%2Fxml_s3%2Fxml_server3.cgi%3Fprod_id%3DPX1268E-1G40%3Bvendor%3Dtoshiba%3Blang%3Den%3Boutput%3Dproductxml"
  #   download_to_local(uri, file, false)
  # end

  desc "Download ICEcat data about Cameras to local cache but do not commit data to DB."
  task :build_product_camera_cache => [:environment] do
    build_product_cache CAMERA_CATEGORY_ICECAT_ID
  end

  def build_product_cache category_id, max_products = nil
    if category_id == nil
      puts "ERROR: category ID is nil. Cannot currently build cache for all categories."
      return
    end

    start_time = Time.now
    puts "Ensuring product files are in local cache."

    puts "Reading #{FULL_FILE} for full list."
    index_document = IcecatIndexDocument.new(category_id)
    parser = Nokogiri::XML::SAX::Parser.new(index_document)
    parser.parse(File.open(FULL_FILE))
    
    puts "Total products in file: #{index_document.total} -- Total valid found: #{index_document.total_valid}"

    already_downloaded = 0
    total_downloaded = 0
    total_downloaded_failed = 0
    index_document.products.each_with_index do |p,i|
      break if i == max_products

      prod_id = p[:id]
      if product_file? prod_id then
        already_downloaded += 1
        puts "#{total_downloaded}: Local file exists for #{prod_id}"
      else
        puts "#{total_downloaded}: Downloading data file for product #{prod_id}"
        product_details_uri = URI("http://#{ICECAT_DOMAIN}/#{p[:path]}")
        if download_to_local(product_details_uri, product_file_name(prod_id)) then
          total_downloaded += 1
        else
          total_downloaded_failed += 1
        end
      end
    end

    puts "********************************************************************************************************"
    puts "DONE."
    puts "Downloaded #{total_downloaded} products."
    puts "Failed to download #{total_downloaded_failed} products that we don't already have locally."
    puts "Already had locally #{already_downloaded} product files."
    puts "Total number of locally cached products: #{total_downloaded + already_downloaded}"
    puts "Total job time in seconds: #{Time.now - start_time}"
  end

  desc "Downloads images for all products and catelogs in the database"
  task :build_image_cache => [:environment] do
    start_time = Time.now

    # this is here since you can't refer to Rails objects (such as Product)
    # until the environment has been loaded.
    LOCAL_IMAGE_MAP = {
      'Thumbnail URL' => IMAGE_PROPERTIES[:thumb],
      'High Resolution Picture URL' => IMAGE_PROPERTIES[:high],
      'Low Resolution Picture URL' => IMAGE_PROPERTIES[:low]
    }

    already_downloaded = 0
    total_downloaded = 0
    total_downloaded_failed = 0

    puts "Downloading local cache of product files..."
    Product.all.each_with_index do |p,i|
      # break if i == 1500

      puts "#{p.external_id}: Downloading images..."

      LOCAL_IMAGE_MAP.each do |k,v|
        image = p.data[k]
        quality = image_quality(k)
        if image == nil or image.empty? then
          puts "    #{p.external_id}: WARNING: no image of quality #{quality}"
          next
        end
        name = image_name(image, p.external_id, 'product', quality)
        file = '/' + IMAGE_DIRECTORY + '/' + "#{name}"
        url = IMAGE_URL_BASE + "#{name}"
        old_url = p.data[v]
        if old_url == nil then
          old_file = nil
        else
          old_file = '/' + IMAGE_DIRECTORY + '/' + "#{image_name_from_url(old_url)}"
        end
        if old_url != url then
          if old_url != nil && File.exists?(old_file) then
            puts "    #{p.external_id}: Renaming file from #{old_file} to #{file}"
            File.rename(old_file, file)
          end
          puts "    #{p.external_id}: Updating data entry for product #{p.external_id} and image #{file}"
          p.data[v] = url
          p.save
        end
        if File.exists?(file) then
          already_downloaded += 1
          puts "    #{p.external_id}: Already have a local file for #{image}: #{file}"
          next
        end
        if ensure_local_image image,file then
          total_downloaded += 1
          puts "    #{p.external_id}: Successfully downloaded the image."
        else
          total_downloaded_failed += 1
          puts "    #{p.external_id}: WARNING: could not download image #{image}"
        end
      end
    end

    puts "********************************************************************************************************"
    puts "DONE."
    puts "Downloaded #{total_downloaded} images"
    puts "Failed to download #{total_downloaded_failed} images"
    puts "Already had locally #{already_downloaded} images"
    puts "Total number of locally cached images: #{total_downloaded + already_downloaded}"
    puts "Total job time in seconds: #{Time.now - start_time}"
  end

  def image_name_from_url(url)
    # /assets/ has 8 characters
    url[8..-1]
  end

  def image_quality(image_key)
    case image_key[0..2]
    when 'Hig'
      'high'
    when 'Low'
      'low'
    else
      'thumb'
    end
  end

  def ensure_local_image image, file, indent = '    '
    puts "#{indent}Downloading local copy for #{image}..."
    download_to_local URI(image), file, true, false, indent + '    '
  end


  # TODO the iteration logic in here is a complete copy of the build_image_cache.
  # if we end up doing much more work on this we should refactor into a new Iterator.
  desc "Uploads all image data to AWS. Requires task icecat:build_image_cache to have been completed."
  task :upload_to_aws => [:environment] do
    start_time = Time.now

    LOCAL_IMAGE_MAP = {
      'Thumbnail URL' => IMAGE_PROPERTIES[:thumb],
      'High Resolution Picture URL' => IMAGE_PROPERTIES[:high],
      'Low Resolution Picture URL' => IMAGE_PROPERTIES[:low]
    }

    LOCAL_IMAGE_PROPERTY_MAP = {
      'low-width' => 'Low Resolution Picture Width',
      'low-height' => 'Low Resolution Picture Height',
      'low-source' => 'Low Resolution Picture URL',
      'low-local_file' => 'Low Resolution Picture URL Local',

      'high-width' => 'High Resolution Picture Width',
      'high-height' => 'High Resolution Picture Height',
      'high-source' => 'High Resolution Picture URL',
      'high-local_file' => 'High Resolution Picture URL Local',

      'thumb-source' => 'Thumbnail URL',
      'thumb-local_file' => 'Thumbnail URL Local'
    }

    already_uploaded = 0
    total_uploaded = 0
    total_upload_failed = 0

    s3 = AWS::S3.new
    bucket = s3.buckets[AWS_BUCKET]

    puts "Uploading locally cached ICEcat images to AWS..."
    Product.all.each_with_index do |p,i|
      LOCAL_IMAGE_MAP.each do |k,v|
        image = p.property_value_for_name(k)
        quality = image_quality(k)
        if image == nil or image.empty? then
          puts "    #{p.external_id}: WARNING: no image of quality #{quality}"
          next
        end
        name = image_name(image, p.external_id, 'product', quality)
        file = '/' + IMAGE_DIRECTORY + '/' + "#{name}"
        if not File.exists? file then
          puts "    #{p.external_id}: WARNING: no image file for quality #{quality} even though it's specified in the DB."
          next
        end
        name.downcase!

        # FIXME this is commented out temporarily, but it works.
        # aws_object = bucket.objects[name]
        # if aws_object.exists? then
        #   already_uploaded += 1
        #   puts "    #{p.external_id}: image already exists for quality #{quality}."
        # else
        #   begin
        #     aws_object.write file: file, acl: :public_read
        #   rescue Exception => e
        #     total_upload_failed += 1
        #     puts "    #{p.external_id}: ERROR uploading file for quality #{quality}: #{e.message}"
        #     next
        #   end
        #   total_uploaded += 1
        #   puts "    #{p.external_id}: SUCCESS: uploaded image for quality #{quality}"
        # end

        # seems tedious, but when updating tens of thousands of products the save
        # adds minutes to the entire process
        save = false
        asset = DigitalAsset.find_by_key name
        if asset != nil then
          puts "    #{p.external_id}: DigitalAsset already exists. Ensuring product relationship and URL"
        else
          puts "    #{p.external_id}: creating DigitalAsset and associating it with the product"
          asset = p.digital_assets.create
          asset.key = name
          save = true
        end
        if asset.product == nil then
          asset.product = p
          save = true
        end
        # calculating this dynamically from the name of the resource
        # if asset.public_url == nil then
        #   asset.public_url = aws_object.public_url
        #   save = true
        # end
        if asset.data[:source_url] == nil then
          asset.data[:source_url] = p.property_value_for_name LOCAL_IMAGE_PROPERTY_MAP["#{quality}-source"]
          save = true
        end
        if asset.data[:quality] == nil then
          asset.data[:quality] = quality
          save = true
        end
        if quality == "thumb" then
          if asset.data[:is_thumbnail] == nil then
            asset.data[:is_thumbnail] = true
            save = true
          end
        else
          if asset.data[:width] == nil then
            asset.data[:width] = p.property_value_for_name LOCAL_IMAGE_PROPERTY_MAP["#{quality}-width"]
            save = true if asset.data[:width] != nil
          end
          if asset.data[:height] == nil then
            asset.data[:height] = p.property_value_for_name LOCAL_IMAGE_PROPERTY_MAP["#{quality}-height"]
            save = true if asset.data[:height] != nil
          end
        end

        asset.save if save
      end

    end

    puts "********************************************************************************************************"
    puts "DONE."
    puts "Uploaded #{total_uploaded} images"
    puts "Failed to upload #{total_upload_failed} images"
    puts "Already had locally #{already_uploaded} images"
    puts "Total number of images in AWS: #{total_uploaded + already_uploaded}"
    puts "Total job time in seconds: #{Time.now - start_time}"
  end


  desc "Removes the image metadata from the products in the DB. WARNING: should only be done after the Digital Assets have been created."
  task :remove_image_metadata_from_products => [:environment] do
    start_time = Time.now

    IMAGE_PROPERTIES = [
      'Low Resolution Picture Width',
      'Low Resolution Picture Height',
      'Low Resolution Picture URL',
      'Low Resolution Picture URL Local',

      'High Resolution Picture Width',
      'High Resolution Picture Height',
      'High Resolution Picture URL',
      'High Resolution Picture URL Local',

      'Thumbnail URL',
      'Thumbnail URL Local'
    ]
    products_processed = 0
    Product.all.each do |p|
      puts "    #{p.external_id}: Processing..."
      IMAGE_PROPERTIES.each do |ip|
        # FIXME how do you delete a property?
        p.data.delete ip
        p.save!
      end
      products_processed += 1
    end

    puts "********************************************************************************************************"
    puts "DONE."
    puts "Processed #{products_processed} products"
    puts "Total job time in seconds: #{Time.now - start_time}"
  end


  # avoid double-loading
  @loaded_ids = {}

  desc "Load sample data from local files into database. Overwrites existing product data. Will use category data if present (see icecat:load_categories)."
  task :load_products => [:environment, 'icecat:load_suppliers'] do
    load_local_products true
  end

  desc "Load sample data from local files into database. Skips files for products already in the database. Used for adding newly downloaded files only."
  task :update_products => [:environment, 'icecat:load_suppliers'] do
    # note that relations are not rebuilt for these since that would require re-parsing the files...defeating the point.
    load_local_products false
  end

  def load_local_products replace_existing
    @external_id_property = Property.find_or_create_by_name(Product.external_id_property)

    @loaded_ids
    @relations = {}
    Dir.entries(PRODUCTS_DIRECTORY).each_with_index do |filename,i|
      product_id = product_id_from_filename filename
      next if not product_id
      begin
        product = load_product product_id, true, replace_existing, ''
      rescue Exception => e
        # don't let a single error derail the entire project...
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        puts "ERROR: Exception encountered when loading #{product_id} from #{filename}"
        puts e.inspect
        print e.backtrace.join("\n")
        puts 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        product = nil
      end
      puts "WARNING: could not load product from file: #{filename}" if not product
      puts "#{i} product files read so far..."
    end

    puts "**********************************************************************"
    puts "Done loading products."
  end

  def load_product product_id, load_related, replace_existing = true, indent = '    '
    puts "#{indent}---------------------------------------------------------------------------------------------"

    pid = @loaded_ids[product_id]
    if pid then
      puts "#{indent}#{product_id}: Already loaded this session."
      return Product.find(pid)
    end

    puts "#{indent}#{product_id}: Loading."

    if not product_file? product_id then
      puts "#{indent}#{product_id}: ERROR: No file found <#{product_file_name product_id}>. Skipping product load."
      return nil
    end

    product = Product.find_by_external_id product_id
    return product if product and not replace_existing
    if product then
      puts "#{indent}#{product.external_id}: Found entry in DB. Destroying it. Old DB id: #{product.id}"
      Product.destroy(product)
    end
    
    product = Product.create

    pval = product.property_values.build( value: product_id )
    pval.property = @external_id_property
    pval.save

    product_document = IcecatProductDocument.new product
    parser = Nokogiri::XML::SAX::Parser.new product_document
    filename = product_file_name product_id
    parser.parse File.open(filename)

    if product_document.code == "-1" then
      puts "#{indent}#{product_id}: WARNING: ICEcat document contains an error message, so skipping product (code #{product_document.code}): #{product_document.error_message}"
      # puts "#{indent}#{product_id}: Deleting file: #{filename}"
      File.delete(filename)
      return nil
    end

    product.reload

    @loaded_ids[product_id] = product.id
    puts "#{indent}#{product_id}: Done loading product. New DB id: #{product.id}"
    return product if not load_related

    # TODO make this an argument so that we can load more than just cameras in this way
    # note that for ICEcat every product belongs to only a single category
    category = product.categories.first
    root_category = nil
    if not category then
      puts "#{indent}#{product_id}: WARNING: no category loaded."
    else
      root_category = category.root
    end
    if root_category != nil and root_category.external_id != CAMERA_CATEGORY_ICECAT_ID then
      puts "#{indent}#{product_id}: Not a Camera. Skipping loading accessories."
    else
      puts "#{indent}#{product_id}: Found #{product_document.related_product_ids_suppliers.keys.length} related products to load. Loading max #{ICECAT_RELATED_MAX_PER_PRODUCT} of them."

      product_document.related_product_ids_suppliers.each_with_index do |(related_id,related_supplier_name),related_count|
        puts "ERROR: #{product_id}: #{product_document.related_product_ids_suppliers}" if not related_id

        break if related_count == ICECAT_RELATED_MAX_PER_PRODUCT
        related_pid = @loaded_ids[related_id]
        if related_pid then
          puts "#{indent}    #{related_id}: Already loaded. Re-using."
          related_prod = Product.find(related_pid)
        else
          # First ensure that there is a local file for the product to load...
          related_file = product_file_name(related_id)
          if not product_file? related_id then
            # ICEcat query interface requires ID and supplier for some reason...
            related_uri = product_icecat_query_uri(related_id, related_supplier_name)
            download_to_local related_uri, related_file, indent + '    '
          end

          related_prod = load_product related_id, false, indent + '    '
          if not related_prod then
            puts "#{indent}    #{related_id}: WARNING: could not load related product."
            next
          end
        end

        # TODO set this up so that they're done in bulk at the end
        Relation.create(
          trigger_id: product.id,
          target_id: related_prod.id,
          label: "ICEcat Relationship",
          status: :proposed)
      end
    end
    product
  end


    # puts "Building Supplier hash for cross-referencing. Note that this does not update anything in the database."
    # @suppliers = {}
    # supplier_document = SupplierDocument.new
    # parser = Nokogiri::XML::SAX::Parser.new(supplier_document)
    # parser.parse(File.open(SUPPLIERS_FILE))
    # @suppliers = supplier_document.suppliers
    # puts "Done loading suppliers. #{@suppliers.keys.length} loaded."

# FIXME make sure the default ROOT CATEGORY is added
  @categories
  desc "Load category data from the master CategoriesList.xml into DB. This will re-use existing DB entries."
  task :load_categories => [:environment] do
    start_time = Time.now
    if not File.exists?(CATEGORIES_FILE) then
      puts "ERROR: specified categories file does not exist <#{CATEGORIES_FILE}>"
      break
    end

    @categories = {}
    category_document = CategoryDocument.new
    parser = Nokogiri::XML::SAX::Parser.new category_document
    parser.parse(File.open CATEGORIES_FILE)
    @categories = category_document.categories
    @categories.each_key {|category_id| load_category category_id }

    puts "********************************************************************************************************"
    puts "Done loading categories."
    puts "#{@categories.keys.length} categories loaded."
    puts "Total job time in seconds: #{Time.now - start_time}"
  end

  def load_category category_id, indent = "  "
    return nil if category_id == nil or category_id.empty?

    puts "#{indent}#{category_id}: Loading..."
    category = @categories[category_id][:category]
    if category then
      "#{indent}#{category_id}: Found category #{category.name}"
      return category
    end

    if not category then
      # try to load into cache
      category = Category.find_by_external_id(category_id)
      if category then
        puts "#{indent}#{category_id}: Found category #{category_id} in database: #{category.name}"
        @categories[category_id][:category] = category
        return category
      end
    end

    # this is the first time we're seeing this category
    puts "#{indent}#{category_id}: Not in database. Loading ancestry first..."
    parent_id = @categories[category_id][:parent_id]
    if parent_id == "1" then
      parent = nil
    else
      parent = load_category parent_id, "#{indent}#{indent}"
    end
    category = Category.create(name: @categories[category_id][:name], external_id: category_id)
    parent.add_child(category) if parent != nil
    @categories[category_id][:category] = category
  end


  ############################################################################################
  # The following are tasks for analyzing the data instead of just for loading it.
  ############################################################################################

  desc "Goes through the full product index and counts the number of products in each category"
  task :analyze_full_data => [:environment, 'icecat:load_categories'] do
    # need to use nokogiri due to file size
    product_xml = Nokogiri::XML(open("#{DIRECTORY}/files.index.xml"))
    products = product_xml.xpath("//file")
    categories = {}
    total = 0
    products.each do |p|
      total += 1
      catid = p['Catid']
      if categories[catid] == nil then
        categories[catid] = 1
      else
        categories[catid] += 1
      end
    end
    puts "TOTAL PRODUCTS: #{total}"

    puts "FULL CATEGORY COUNTS: NAME (ROOT) -- COUNT"
    root_category_counts = {}
    categories.each_pair do |id,count|
      cat = Category.find_by_external_id("#{id}")
      root = cat.root

      puts "  #{cat.name} (#{root.name}) -- #{count}"
      
      if root_category_counts[root.external_id] == nil
        root_category_counts[root.external_id] = count
      else
        root_category_counts[root.external_id] += count
      end
    end

    puts "-----------------------------------"
    puts "ROOT CATEGORY COUNTS: NAME -- COUNT"
    root_category_counts.each_pair do |catid,count|
      cat = Category.find_by_external_id("#{catid}")
      puts "  #{cat.name} -- #{count}"
    end
  end

end # namespace :icecat