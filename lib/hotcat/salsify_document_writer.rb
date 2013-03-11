# encoding: utf-8

require 'json'

require 'hotcat/error'

module Hotcat::SalsifyDocumentWriter

  def open_output_file(filename)
    if File.exists?(filename)
      raise Hotcat::SalsifyWriterError, "SalsifyDocumentWriter: output file exists: #{filename}"
    end
    
    output_file = File.new(filename, 'w', encoding: "UTF-8")
    if filename.end_with?(".gz")
      output_file.binmode
      output_file = Zlib::GzipWriter.new(output_file)
    end

    start_file(output_file)
    output_file
  end

  def close_output_file(file)
    end_file(file)
    file.close
  end


  private


  def start_file(file)
    file << "[\n"
  end

  def end_file(file)
    file << "\n]"
  end
  
end