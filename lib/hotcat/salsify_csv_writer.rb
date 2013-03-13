require 'csv'

require 'hotcat/salsify_products_loader'
require 'hotcat/salsify_category_writer'


# Generates a Salsify CSV for import
class Hotcat::SalsifyCsvWriter < Hotcat::SalsifyProductsLoader


  def initialize(options)
    options = super(options)

    unless skip_output
      @categories = options[:categories]
      if @categories.blank?
        raise Hotcat::ConfigError, "Require categories to write a CSV."
      end


      @accessory_category_ids = options[:accessory_category_ids]
      if @accessory_category_ids.blank?
        raise Hotcat::ConfigError, "Require accessory categories to write a CSV."
      end
      @accessory_category_ids = @accessory_category_ids.to_a.select do |id|
        # purge the categories for which we did not successfully load even a
        # single product across the entire system
        @product_category_mapping.values.include?(id)
      end
      @accessory_category_ids.sort!


      @attributes_list = options[:attributes_list]
      if @attributes_list.blank?
        raise Hotcat::ConfigError, "Require attributes_list to write a CSV."
      end
      @attributes_list.delete(product_id_attribute)
      @attributes_list.delete(Hotcat::SalsifyCategoryWriter.default_accessory_category)
      @attributes_list.delete(Hotcat::SalsifyCategoryWriter.default_accessory_relationship)

      # often comes in as a Set or some other Enumerable
      @attributes_list = @attributes_list.to_a

      # adding a column per accessory category
      @accessory_categories = Hash.new
      @accessory_category_ids.each do |id|
        category = @categories[id]
        if category.blank?
          raise Hotcat::ConfigError, "Invalid accessory category id specified: #{id}"
        end
        name = clean_category_name(category[:name])
        @accessory_categories[name] = id
        @attributes_list.unshift(name)
      end

      @attributes_list.unshift('Image')
      @attributes_list.unshift('Category')

      # make sure sku is first column by adding last
      @attributes_list.unshift(product_id_attribute)
    end
  end


  private


  def open_output_file(filename)
    csv = CSV.open(filename, "wb", { force_quotes: true })
    # write the header row
    csv << @attributes_list.map { |a| clean_for_csv(a) }
    csv
  end


  def close_output_file(file)
    file.close
  end


  def clean_category_name(name)
    # Since we're going to be adding the name to a path, we want to remove any
    # path-like character.
    name.gsub('/',' ')
        .gsub('\\', ' ')
  end


  def category_path(category_id)
    category = @categories[category_id]
    if category.blank?
      raise Hotcat::SalsifyWriterError, "Category id not recognized: #{category_id}"
    end

    name = clean_category_name(category[:name])
    parent_id = category[:parent_id]

    # don't show the root in the path, and the root ID for ICEcat is 1
    return name if parent_id.blank? || parent_id == '1'

    category_path(parent_id) + '/' + name
  end


  def category_path_for_product(product)
    cat_id = product[:category]
    return nil if cat_id.blank?
    category_path(cat_id)
  end


  def accessories_list(product, category_name)
    accessory_ids = product[:accessory_ids]
    return nil if accessory_ids.blank?

    # to_a since sometimes we're dealing with sets
    accessory_ids = accessory_ids.to_a

    category_id = @accessory_categories[category_name]
    accessory_ids.select! { |id| @product_category_mapping[id] == category_id }
    return nil if accessory_ids.blank?

    accessory_ids.join(',')
  end


  def clean_for_csv(str)
    str = str.strip
    return nil if str.empty?
    str.gsub(/\s+/, " ")
       .gsub("\\n"," ")
  end


  def write_product(product)
    output_file << @attributes_list.map do |attribute|
      if attribute == 'Image'
        product[:image_url]
      elsif attribute == 'Category'
        category_path_for_product(product)
      elsif @accessory_categories.has_key?(attribute)
        accessories_list(product, attribute)
      else
        clean_for_csv(product[:properties][attribute].to_s)
      end
    end
  end

end