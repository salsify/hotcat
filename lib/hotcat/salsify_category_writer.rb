# encoding: utf-8

require 'hotcat/error'
require 'hotcat/salsify_document_writer'

# Writes out a Salsify category document.
class Hotcat::SalsifyCategoryWriter
  include Hotcat::SalsifyDocumentWriter

  attr_reader :categories

  # categories is a hash of hashes representing a bunch of categories to be
  # written out:
  # { id: { name: @name, parent_id: @parent_id } }
  def initialize(categories, output_filename)
    @categories = categories
    @output_filename = output_filename
  end

  # will very likely raise errors if there are any problems
  def write
    output_file = open_output_file(@output_filename)
    
    cats_xml = Ox::Element.new('categories')
    @categories.each_pair do |id, category|
      cat_xml = Ox::Element.new('category')
      cat_xml[:id] = id
      category.each_pair do |key,val|
        if key == :parent_id
          cat_xml[key] = val unless !val.nil?
        else
          cat_xml << build_property_xml(key,val)
        end
      end
      cats_xml << cat_xml
    end
    output_file << Ox.dump(cats_xml).force_encoding('utf-8')

    close_output_file(output_file)
  end
end