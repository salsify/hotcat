# encoding: utf-8

require 'zip/zip'
require 'hotcat/salsify_document_writer'

# Writes out a Salsify index document. E.g.:
# [
#   { "header": { } },
#   { "attributes": "attributes.json" },
#   { "attribute_values": "attribute_values.json" },
#   { "products": "products.json" }
# ]
class Hotcat::SalsifyProductsWriter
  include Hotcat::SalsifyDocumentWriter


  def initialize(filename, attributes_file, categories_file, products_files)
    unless filename.end_with(".zip")
      raise Hotcat::SalsifyWriterError, "index filename must end in .zip: #{filename}"
    end

    @filename = filename
    @attributes_file = attributes_file
    @categories_file = categories_file
    @products_files = products_files
  end


  def write
    unless File.exists?(@attributes_file)
      raise Hotcat::SalsifyWriterError, "attributes file does not exist: #{@attributes_file}"
    end

    unless File.exists?(@categories_file)
      raise Hotcat::SalsifyWriterError, "categories (attribute_values) file does not exist: #{@categories_file}"
    end

    if @products_files.empty?
      raise Hotcat::SalsifyWriterError, "no product files listed"
    end

    @products_files.each do |f|
      unless File.exists?(f)
        raise Hotcat::SalsifyWriterError, "product file does not exist: #{f}"
      end
    end

    import_file = File.dirname(filename) + "import.json"
    if File.exists?(import_file)
      puts "WARNING: #{import_file} exists. Overwriting."
      File.delete(import_file)
    end
    create_import_file(import_file)

    Zip::ZipFile.open(@filename, Zip::ZipFile::CREATE) do |zipfile|
      zipfile.add(File.basename(import_file), import_file)
      zipfile.add(File.basename(@attributes_file), @attributes_file)
      zipfile.add(File.basename(@categories_file), @categories_file)
      products_files.each { |f| zipfile.add(File.basename(f), f) }
    end
  end


  private


  def create_import_file(filename)
    index_file = open_output_file(filename)

    write_header(index_file)

    file << ",\n"

    attributes = { attributes: "#{@attributes_file}" }
    file << attributes.to_json.force_encoding('utf-8')

    file << ",\n"

    attribute_values = { attribute_values: "#{@categories_file}" }
    file << attribute_values.to_json.force_encoding('utf-8')

    file << ",\n"

    products = { products: @products_files }
    file << products.to_json.force_encoding('utf-8')

    close_output_file(index_file)
  end


  def write_header(file)
    header = {
      header: {
        version: "2012-12",
        update_semantics: "truncate",
        scope: ["all"]
      }
    }
    file << header.to_json.force_encoding("utf-8")
  end

end