require 'csv'

require 'hotcat/salsify_products_loader'
require 'hotcat/salsify_category_writer'


# Generates a Salsify CSV for import
class Hotcat::SalsifyCsvWriter < Hotcat::SalsifyProductsLoader


  def initialize(options)
    options = super(options)

    @categories = options[:categories]
    if @categories.blank?
      raise Hotcat::ConfigError, "Require categories to write a CSV."
    end

    @attributes_list = options[:attributes_list].dup
    if @attributes_list.blank?
      raise Hotcat::ConfigError, "Require attributes_list to write a CSV."
    end

    @attributes_list.delete(product_id_attribute)
    @attributes_list.delete(Hotcat::SalsifyCategoryWriter.default_accessory_category)
    @attributes_list.delete(Hotcat::SalsifyCategoryWriter.default_accessory_relationship)

    # make sure sku is first column
    @attributes_list.unshift('Related Products')
    @attributes_list.unshift('Image')
    @attributes_list.unshift('Category')
    @attributes_list.unshift(product_id_attribute)
  end


  private


  def open_output_file(filename)
    csv = CSV.open(filename, "wb")
    # write the header row
    csv << @attributes_list.map { |a| clean_for_csv(a) }
    csv
  end


  def close_output_file(file)
    file.close
  end


  def clean_category_name(name)
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
    return name if parent_id.blank?
    category_path(parent_id) + '/' + name
  end


  def category_path_for_product(product)
    cat_id = product[:category]
    return nil if cat_id.blank?
    category_path(cat_id)
  end


  def accessories_list(product)
    accessory_ids = product[:accessory_ids]
    return nil if accessory_ids.blank?
    accessory_ids.join('|')
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
      elsif attribute == 'Related Products'
        accessories_list(product)
      else
        clean_for_csv(product[:properties][attribute].to_s)
      end
    end
  end

end