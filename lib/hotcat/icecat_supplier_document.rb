require 'nokogiri'

require 'hotcat/icecat'

# Nokogiri SAX parser for the Supplier key document from ICEcat.
#
class Hotcat::SupplierDocument < Nokogiri::XML::SAX::Document
  attr_reader :suppliers

  # Stores the ICEcat server filename for the category document.
  class << self; attr_reader :filename; end
  @filename = "SuppliersList.xml.gz"

  def initialize
    @suppliers = {}
  end

  def start_element name, attributes = []
    if name == 'Supplier' then
      id = nil
      name = nil
      attributes.each do |a|
        case a[0]
        when 'ID'
          id = a[1]
        when 'Name'
          name = a[1]
        end
      end
      @suppliers[id] = name
    end
  end
end