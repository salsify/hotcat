require 'nokogiri'

require 'hotcat/icecat'

# Nokogiri SAX parser for ICEcat product XML files.
#
# Note that we keep the supplier around in the related_product_ids_suppliers
# hash because to use the ICEcat query interface you need the ID and the
# supplier name. Strange, right?
class Hotcat::ProductDocument < Nokogiri::XML::SAX::Document
  attr_accessor :product

  # the code is stored in the file. -1 means error.
  attr_reader :code, :error_message

  # This maps the ICEcat product fields to the labels that
  # are used in Salsify to express them.
  #
  # This is effectively a whitelist of properties to be loaded.
  #
  # Note: these are not all the product fields. We could load more.
  #        Check out any of the cached XML files for other ideas.
  PRODUCT_FIELDS = {
    Prod_id: 'id',
    Name: 'name',
    Title: 'Complete Label',
    Quality: 'Editorial Quality',
    ReleaseDate: 'Release Date',
  }

  PICTURE_PROPERTY = :HighPic

  def initialize
    @product = {}
    @product[:properties] = {}
    @product[:related_product_ids_suppliers] = {}

    @in_related = false
    @related_id = nil
    @related_supplier

    @in_description = false
    @in_long_description = false

    @in_product_feature = false
    @product_feature_value = nil
  end

  def start_element(name, attributes = [])
    @val = ""

    case name
    when 'ProductRelated'
      @in_related = true

    when 'Product'
      if @in_related
        attributes.each { |a| @related_id = a[1] if a[0] == 'Prod_id' }
      else
        # in the root product itself
        attributes.each do |a|
          key = a[0].to_sym
          val = a[1]

          if key == PICTURE_PROPERTY
            @product[:image_url] = val
          elsif PRODUCT_FIELDS.has_key?(key)
            @product[:properties][PRODUCT_FIELDS[key]] = val
          elsif key == :Code
            @code = val
          elsif key == :ErrorMessage
            @error_message = val
          end
        end
      end
    
    when 'ShortSummaryDescription'
      @in_description = true
    when 'LongSummaryDescription'
      @in_long_description = true

    when 'Supplier'
      name = nil
      attributes.each { |a| name = a[1] if a[0] == 'Name' }
      if @in_related
        @related_supplier = name
      else
        @product[:properties]['Supplier'] = name
      end

    when 'Category'
      category_id = nil
      attributes.each { |a| category_id = a[1] if a[0] == 'ID' }
      # ICEcat products have only one category
      @product[:category] = category_id if category_id

    when 'ProductFeature'
      @in_product_feature = true
      attributes.each { |a| @product_feature_value = a[1] if a[0] == 'Presentation_Value' }

    when 'Name'
      if @in_product_feature
        # the weirndess with the name array is that multiple languages could be present.
        # in our extract however we're dealing with English only for the present...
        name = nil
        attributes.each { |a| name = a[1] if a[0] == 'Value' }
        @product[:properties][name] = @product_feature_value if name
      end
    end
  end

  def characters(string)
    @val << string
  end

  def cdata_block(string)
    @val << string
  end

  def end_element(name)
    case name
    when 'ProductRelated'
      @product[:related_product_ids_suppliers][@related_id] = @related_supplier if @related_id
      @related_id = nil
      @related_supplier = nil
      @in_related = false

    when 'ShortSummaryDescription'
      @product[:properties]['Description'] = @val.strip
      @in_description = false

    when 'LongSummaryDescription'
      @product[:properties]['Long Description'] = @val.strip
      @in_long_description = false

    when 'ProductFeature'
      @in_product_feature = false

    end
  end
end