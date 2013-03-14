require 'find'

require 'hotcat/salsify_products_loader'

# Manages the cache for Salsify
#
# TODO need to move over a great deal of stuff from the rake task.
class Hotcat::CacheManager

  @@cache = Hotcat::CacheManager.new

  # This must be called before the CacheManager can be used.
  def self.configure(cache_directory)
    @@cache.init(cache_directory)
    @@cache
  end


  def init(cache_directory)
    if initialized?
      raise Hotcat::CacheError, "Cannot reinitialize cache."
    end

    ensure_directory(cache_directory)
    @cache_directory = cache_directory

    # ensure that core directory structure exists
    ensure_directory(tmp_directory)
    ensure_directory(reference_files_directory)
    ensure_directory(product_index_files_directory)
    ensure_directory(product_files_directory)
    ensure_directory(product_failed_files_directory)
    ensure_directory(generated_files_directory)
  end


  def initialized?
    !@cache_directory.nil?
  end


  def self.instance
    if !@@cache.initialized?
      raise Hotcat::CacheError, "Cache not yet initialized."
    end
    @@cache
  end


  def tmp_directory
    File.join(@cache_directory, "tmp")
  end


  # contains things like the categories list, suppliers list, etc.
  def reference_files_directory
    File.join(@cache_directory, "refs")
  end


  # returns where the indexes are stored
  def product_index_files_directory
    File.join(@cache_directory, "indexes")
  end


  # returns where the individual product files are stored
  def product_files_directory
    File.join(@cache_directory, "product_cache")
  end


  def product_files_directory_for_category(category_id)
    category_directory = File.join(product_files_directory, category_id.to_s)
    ensure_directory(category_directory)
    category_directory
  end


  # we keep around these files to prevent ourselves from re-downloading them.
  # usually these files represent products that were referenced but that we don't
  # have permission to see.
  def product_failed_files_directory
    File.join(@cache_directory, "product_cache_failures")
  end


  # this is where to put files that we generate (as opposed to download from
  # ICEcat).
  def generated_files_directory
    File.join(@cache_directory, "salsify")
  end


  # This organizes the product files into directories according to category.
  # This makes loading products for specific categoreis much easier.
  def organize_product_files
    Dir.entries(product_files_directory).sort.each do |file|
      next if file.start_with?(".")
      file = File.join(product_files_directory, file)
      next if File.directory?(file)

      begin
        product = load_product(file)
        if product.nil?
          archive_failed_file(file)
          next
        end
      rescue Exception => e
        # don't let this ruin the whole project
        puts "ERROR: could not process #{file}: #{e.inspect}"
        next
      end

      category_id = product[:category]
      category_directory = product_files_directory_for_category(category_id)
      FileUtils.mv(file, File.join(category_directory, File.basename(file)))
    end
  end


  def product_files_for_category(category_id)
    files = Dir.entries(product_files_directory_for_category(category_id)).select do |file|
      !File.directory?(file)
    end
    files.sort
  end


  # returns the base filename for the product
  def product_file_basename_for_product_id(product_id)
    'product_' + URI.encode_www_form_component(product_id) + '.xml.gz'
  end


  # returns a file location in which to put the product's file
  def new_local_file_for_product_id(product_id)
    File.join(product_files_directory, product_file_basename_for_product_id(product_id))
  end


  # returns whether we have a local file for this product. helpful for determining
  # whether we need to download something.
  def local_file_for_product_id?(product_id)
    valid_product_file_for_product_id != nil || invalid_product_file_for_product_id != nil
  end


  # returns the valid file for the given product id, or nil if one does not
  # exist.
  def valid_product_file_for_product_id(product_id)
    find_file_for_product(product_id, product_files_directory)
  end


  # returns the valid file for the given product id, or nil if one does not
  # exist.
  def invalid_product_file_for_product_id(product_id)
    find_file_for_product(product_id, product_failed_files_directory)
  end


  private


  def ensure_directory(path)
    success = true
    if !File.exist?(path)
      success = FileUtils.makedirs(path)
    elsif !File.directory?(path)
      success = false
    end
    raise Hotcat::CacheError, "could not ensure directory: #{path}" unless success
    success
  end


  # helper for methods above
  def find_file_for_product(product_id, source_directory)
    local_filename = product_file_basename_for_product_id(product_id)
    found = nil

    Find.find(source_directory) do |file|
      if File.basename(file) == local_filename
        found = file
        Find.prune
      end
    end
    found
  end


  def load_product(file)
    Hotcat::SalsifyProductsLoader.load_product(file)
  end


  def archive_failed_file(file)
    FileUtils.mv(file, File.join(product_failed_files_directory, File.basename(file)))
  end

end