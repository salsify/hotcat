require 'nokogiri'

# Nokogiri SAX parser for ICEcat index XML files, such as full indicies or
# daily updates.
#
# If a category is specified, this will skip all products not in the category or
# in one of its decendants.
#
# If no category is specified, this loads all products.
#
# The primary return value is the index_document.products variable, which is an
# array of hashes that each contain a product's id, category id, and path to its
# more detailed ICEcat address.
#
# Note that there is data in the files that is being ignored here. We are only
# interested in the product IDs necessary to fetch the more detailed documents
# for each individual product.
class IcecatIndexDocument < Nokogiri::XML::SAX::Document
  attr_reader :total, # total products seen, whether or not 
              :total_valid, # total products seen in a valid category
              :products, # hash collection of products
              :root_valid_category_id,
              :valid_category_ids

  def initialize category = nil
    @root_valid_category_id = category
    @valid_category_ids = []
    if @root_valid_category_id != nil then
      # pre-loading SIGNIFICANTLY speeds up the overal load time
      all_valid_cat_ids = Category.find_by_external_id(category).descendants
      all_valid_cat_ids.each {|id| @valid_category_ids.push(Category.find(id).external_id) }
    end

    @total = 0
    @total_valid = 0
    @products = []
  end

  def start_element name, attributes = []
    case name
    when 'file'
      @total += 1

      path = nil
      id = nil
      cat_id = nil
      attributes.each do |a|
        case a[0]
        when 'path'
          path = a[1]
        when 'Prod_ID'
          id = a[1]
        when 'Catid'
          cat_id = a[1]
        end
      end
      if @root_valid_category_id == nil or @valid_category_ids.include? cat_id then
        @total_valid += 1
        @products.push({id: id, root_valid_category_id: cat_id, path: path})
      end
    end
  end

end