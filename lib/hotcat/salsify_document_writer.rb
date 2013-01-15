# encoding: utf-8

require 'json'

require 'hotcat/error'

module Hotcat::SalsifyDocumentWriter

  def open_output_file(filename)
    if File.exists?(filename)
      raise Hotcat::SalsifyWriterError, "SalsifyDocumentWriter: Output file exists: #{filename}"
    end
    
    output_file = File.new(filename, 'w', encoding: "UTF-8")
    if filename.end_with?(".gz")
      output_file.binmode
      output_file = Zlib::GzipWriter.new(output_file)
    end

    header = {
      header: {
        version: "2012-12",
        update_semantics: "upsert",
        scope: ["all"]
      }
    }
    output_file << "[\n" << header.to_json << ",\n"

    output_file
  end

  def close_output_file(file)
    file << "\n]"
    file.close
  end
  
end