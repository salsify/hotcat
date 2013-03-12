# encoding: utf-8

require 'hotcat/salsify_document_writer'

# Writes out a Salsify category document.
class Hotcat::SalsifyCategoryWriter
  include Hotcat::SalsifyDocumentWriter


  attr_reader :categories


  # Stores the ICEcat server filename for the category document.
  class << self
    attr_reader :filename, :default_root_category,
                :default_accessory_category, :default_accessory_relationship
  end
  @filename = "categories.json.gz"
  @default_root_category = "ICEcat Product Category"

  @default_accessory_category = "Accessory Label"
  @default_accessory_relationship = "Related Product"


  # categories is a hash of hashes representing a bunch of categories to be
  # written out:
  # { id: { name: @name, parent_id: @parent_id } }
  def initialize(categories, output_filename)
    @categories = categories
    @output_filename = output_filename
  end


  def write
    # Category trees tend not to be super big, so it's OK to do this whole thing
    # in memory instead of streaming it out at little at a time.

    attribute_values = [{
      attribute_id: Hotcat::SalsifyCategoryWriter.default_accessory_category,
      id: Hotcat::SalsifyCategoryWriter.default_accessory_relationship,
      name: Hotcat::SalsifyCategoryWriter.default_accessory_relationship
    }]

    @categories.each_pair do |id, category|
      attribute = {
                    attribute_id: Hotcat::SalsifyCategoryWriter.default_root_category,
                    id: id,
                    name: category[:name]
                  }
      attribute[:parent_id] = category[:parent_id] unless category[:parent_id].nil?
      attribute_values.push(attribute)
    end

    output_file = open_output_file(@output_filename)
    output_file << attribute_values.to_json.force_encoding('utf-8')
    close_output_file(output_file)
  end


  private


  # override to prevent writing the wrapping array bracket
  def start_file(file)
    # noop
  end

  # override to prevent writing the wrapping array bracket
  def end_file(file)
    # noop
  end

end