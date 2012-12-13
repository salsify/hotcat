require 'nokogiri'

# Nokogiri SAX parser for ICEcat index XML files, such as full indicies or
# daily updates.
#
# This will only load products for the given set of category IDs. There is no
# intelligence in this document to deal with category hierarchy, so you should
# send in the entire tree you want saved.
#
# If no category is specified, this will load all products.
#
# The primary return value is the index_document.products variable, which is an
# array of hashes that each contain a product's id, category id, and path to its
# more detailed ICEcat address.
#
# Note that there is data in the files that is being ignored here. We are only
# interested in the product IDs necessary to fetch the more detailed documents
# for each individual product.
class Hotcat::IndexDocument < Nokogiri::XML::SAX::Document
  attr_reader :total, # total products seen, whether or not 
              :total_valid, # total products seen in a valid category
              :products, # hash collection of products
              :root_valid_category_id,
              :valid_category_ids


  class << self
    attr_reader :full_index_remote_filename,
                :full_index_local_filename,
                :daily_index_remote_filename,
                :daily_index_local_filename
  end

  # Stores the ICEcat server filename for the full index document document.
  @full_index_remote_filename = "files.index.xml"
  @full_index_local_filename = "#{@full_index_remote_filename}.gz"

  # Stores the ICEcat server filename for the daily index document document.
  @daily_index_remote_filename = "daily.index.xml"
  @daily_index_local_filename = "#{@daily_index_remote_filename}.gz"


  def initialize(valid_category_ids, max_products)
    @valid_category_ids = valid_category_ids
    @total = 0
    @max_products = max_products
    @total_valid = 0
    @products = []
  end

  def start_element(name, attributes = [])
    return if !@max_products.nil? && @total_valid >= @max_products

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
      if @valid_category_ids.nil? or @valid_category_ids.include?(cat_id) then
        @total_valid += 1
        @products.push({id: id, root_valid_category_id: cat_id, path: path})
      end
    end
  end

end