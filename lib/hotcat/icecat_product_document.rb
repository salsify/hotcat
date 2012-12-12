require 'nokogiri'

# Nokogiri SAX parser for ICEcat product XML files.
#
# This requires a Product model object in which to put most of the information
# from the document. The only exception is that related product IDs are collected
# in an array (:related_product_ids_suppliers).
#
# Note that we keep the supplier around in that hash because to use the
# ICEcat query interface you need the ID and the supplier name. Strange, right?
class IcecatProductDocument < Nokogiri::XML::SAX::Document
  attr_accessor :product, :related_product_ids_suppliers

  # the code is stored in the file. -1 means error.
  attr_reader :code, :error_message

  # This maps the ICEcat product fields to the labels that
  # are used in Salsify to express them.
  #
  # Note: these are not all the product fields.
  # Check out any of the cached XML files for that.
  PRODUCT_FIELDS = {
    Prod_id: 'ICEcat ID',
    Name: 'Label',
    Title: 'Complete Label',
    Quality: 'Editorial Quality',
    ReleaseDate: 'Release Date',
    ThumbPic: 'Thumbnail URL',
    HighPic: 'High Resolution Picture URL',
    HighPicHeight: "High Resolution Picture Height",
    HighPicWidth: "High Resolution Picture Width",
    LowPic: 'Low Resolution Picture URL',
    LowPicHeight: "Low Resolution Picture Height",
    LowPicWidth: "Low Resolution Picture Width"
  }

  def initialize product
    @product = product
    @related_product_ids_suppliers = {}

    @in_related = false
    @related_id = nil
    @related_supplier

    @in_description = false
    @in_long_description = false

    @in_product_feature = false
    @product_feature_value = nil

    @properties_db = {}
    @property_values = []

    @category_property_name = 'Category'
  end

  def start_element name, attributes = []
    @val = ""

    case name
    when 'ProductRelated'
      @in_related = true

    when 'Product'
      if not @in_related then
        # in the root product itself
        attributes.each do |a|
          key = a[0].to_sym
          val = a[1]
          if key == :Title then
            create_property_value @product, Product.name_property, val
          elsif PRODUCT_FIELDS[key] then
            create_property_value @product, PRODUCT_FIELDS[key], val
          elsif key == :Code then
            @code = val
          elsif key == :ErrorMessage then
            @error_message = val
          end
        end
      else
        attributes.each {|a| @related_id = a[1] if a[0] == 'Prod_id' }
      end
    
    when 'ShortSummaryDescription'
      @in_description = true
    when 'LongSummaryDescription'
      @in_long_description = true

    when 'Supplier'
      name = nil
      attributes.each { |a| name = a[1] if a[0] == 'Name' }
      if not @in_related then
        create_property_value @product, 'Supplier', name
      else
        @related_supplier = name
      end

    when 'Category'
      puts "    #{@product.external_id}: WARNING: multiple categories found in file." if @product.categories.length > 0
      category_id = nil
      attributes.each { |a| category_id = a[1] if a[0] == 'ID' }
      if category_id then
        category = Category.find_by_external_id(category_id)
        if category then
          create_property_value @product, @category_property_name, category
        else
          puts "    #{@product.external_id}: WARNING: no category found in database with ID <#{category_id}>"
        end
      end

    when 'ProductFeature'
      @in_product_feature = true
      attributes.each {|a| @product_feature_value = a[1] if a[0] == 'Presentation_Value' }
    when 'Name'
      if @in_product_feature then
        # the weirndess with the name array is that multiple languages could be present.
        # in our extract however we're dealing with English only for the present...
        name = nil
        attributes.each {|a| name = a[1] if a[0] == 'Value' }
        create_property_value @product, name, @product_feature_value if name
      end
    end
  end

  def characters string
    @val << string
  end

  def cdata_block string
    @val << string
  end

  def end_element name
    case name
    when 'Product'
      flush_properties unless @in_related

    when 'ProductRelated'
      @related_product_ids_suppliers[@related_id] = @related_supplier if @related_id
      @related_id = nil
      @related_supplier = nil
      @in_related = false

    when 'ShortSummaryDescription'
      create_property_value @product, 'Description', @val
      @in_description = false

    when 'LongSummaryDescription'
      create_property_value @product, 'Long Description', @val
      @in_long_description = false

    when 'ProductFeature'
      @in_product_feature = false
    end
  end

  private

    def create_property_value product, name, value
      pval = product.property_values.build
      prop = @properties_db[name]
      unless prop
        prop = Property.find_or_create_by_name name
        prop.name = name
        prop.data['hierarchical'] = true if name == @category_property_name
        prop.save
        @properties_db[name] = prop
      end
      pval.property = prop
      if value.class == Category then
        pval.category_id = value.id
      else
        pval.value = value.strip
      end
      @property_values.push pval
      pval
    end

    def flush_properties
      PropertyValue.import @property_values, validate: true
      @property_values.clear
    rescue Exception => e
      # TODO log an error
      print e.backtrace.join("\n")
      @results.errors.push e
    end
end