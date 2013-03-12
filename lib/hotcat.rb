require 'active_support/ordered_options'
require "rails/railtie"


module Hotcat
  class << self
    def configure(&block)
      Hotcat::Configuration.configure(&block)
    end
  end


  class Railtie < ::Rails::Railtie
    rake_tasks do
      load 'hotcat_tasks.rake'
    end
  end
end


require "hotcat/error"
require "hotcat/config"
require "hotcat/version"

require "hotcat/icecat"
require "hotcat/salsify_csv_writer"
require "hotcat/salsify_document_writer"
require "hotcat/salsify_index_writer"
require "hotcat/salsify_attributes_writer"
require "hotcat/icecat_supplier_document"
require "hotcat/icecat_category_document"
require "hotcat/salsify_category_writer"
require "hotcat/icecat_index_document.rb"
require "hotcat/icecat_product_document.rb"
require "hotcat/salsify_products_writer.rb"
require "hotcat/aws_uploader"