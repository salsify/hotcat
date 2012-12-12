require 'nokogiri'

require 'hotcat/icecat'

# Nokogiri SAX parser for the Supplier key document from ICEcat.
#
# To use, run the parser on the ICEcat category XML document and then refer to
# the category_document.categories hashtable for the details. It contains a hash
# mapping external ID to a hash with name nad parent_id as keys.
#
# Note that the ICEcat category document has data that is not being used in
# this. For example, we only take one label per category (the English label) and
# ignore all of the internationalization articles.
#
# Another example is that ICEcat categories have thumbnails associated with
# them. Since we don't bother with thujmbnails for categories in Salsify we
# don't do anything with that.
#
# etc.
class CategoryDocument < Nokogiri::XML::SAX::Document
  attr_reader :categories

  def initialize
    @categories = {}
    init_values
  end

  # Resets all values between categories.
  def init_values
    @id = nil
    @name = nil
    @parent_id = nil
  end

  def start_element name, attributes = []
    case name
    when 'Category'
      attributes.each do |a|
        case a[0]
        when 'ID'
          @id = a[1]
        end
      end

    when 'Name'
      langid = nil
      value = nil
      attributes.each do |a|
        case a[0]
        when 'Value'
          value = a[1]
        when 'langid'
          langid = a[1]
        end
      end

      if !value.nil? && !value.empty?
        if langid == Icecat.english_language_id
          @name = value
        elsif langid == Icecat.fallback_language_id && @name.nil?
          # @name.nil? ensures that we're not overwriting an English name if
          # we've seen it already.
          @name = value
        end
      end

    when 'ParentCategory'
      attributes.each { |a| @parent_id = a[1] if a[0] == 'ID' }

    end
  end

  def end_element name
    case name
    when 'Category'
      # ID 1 is the root Category for ICEcat. In fact, in its document it is
      # listed as its own parent...
      #
      # Strangely some categories do not have parents, so the whole thing isn't
      # very consistent.
      @categories[@id] = { name: @name, parent_id: @parent_id } unless @id == "1"
      init_values
    end
  end
end
