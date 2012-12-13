# encoding: utf-8

require 'ox'

require 'hotcat/error'

module Hotcat::SalsifyDocumentWriter

  def open_output_file(filename)
    if File.exists?(filename)
      raise Hotcat::SalsifyWriterError, "SalsifyDocumentWriter: Output file exists: #{output_filename}"
    end
    
    output_file = File.new(filename, 'w', encoding: "UTF-8")
    if filename.end_with?(".gz")
      output_file.binmode
      output_file = Zlib::GzipWriter.new(output_file)
    end

    output_file << "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n"
    output_file << "<salsify xmlns=\"http://www.salsify.com/2012-12/import\">\n"

    output_file
  end

  def close_output_file(file)
    file << "</salsify>"
    file.close
  end

  def build_product_category_xml(id)
    cat_xml = Ox::Element.new('category')
    cat_xml['id'] = id
    cat_xml
  end

  def build_property_xml(name, value, language = nil)
    property_xml = Ox::Element.new('property')
    property_xml['name'] = name
    property_xml['language'] = language if language.present?
    property_xml << value.to_s
    property_xml
  end

  def build_image_xml(url, metadata = {})
    image_xml = Ox::Element.new('image')
    image_xml['url'] = url
    image_xml['width'] = metadata[:width] if metadata[:width].present?
    image_xml['height'] = metadata[:width] if metadata[:width].present?
    image_xml['is_thumbnail'] = (metadata[:is_thumbnail] ?  "true" : "false")
    image_xml
  end
  
end