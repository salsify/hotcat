# Hotcat

Hotcat is a library for accessing and transforming ICEcat data into Salsify's required data ingest format.

## Installation

Add this line to your Gemfile (probably for development only):

    gem 'hotcat', :git => 'git@github.com:socialceramics/hotcat.git'

And then execute:

    $ bundle

## Usage

Hotcat's primary interface is via Rake tasks which require configuration.

### Configuration

Configuration is done as follows:
```
  Hotcat::Configuration.configure do |config|
    # REQUIRED
    config.username = "ICECAT USERNAME"
    config.password = "ICECAT PASSWORD"
    
    # Max # of products to load (not included related products).
    # -1 for all.
    # config.max_products = 100

    # Max # of related products PER PRODUCT to load.
    # 0  for none (just load the products).
    # -1 for all.
    # config.max_related_products = 200

    # REQUIRED
    # This is the local icecat directory where all data will be stored.
    config.cache_dir = "/path/to/your/local/icecat/files"
  end
```
I recommend you do this in Rails using initializers. Basically put a hotcat.rb file into config/initializers and you'll be good to go.

### Rake tasks

Hotcat comes with a number of rake tasks that are the primary interface for the system. Make sure that your configuration is set up, especially the local cache directory, for this to work appropriately.

#### Primary Tasks

If starting from scratch, run the following tasks in this order:

1. **hotcat:convert_categories**: grabs the ICEcat category document and converts it to Salsify's data ingest format.
2. **hotcat:build_product_camera_cache**: downloads details for up to the maximum number of products specified in the hotcat configuration in the camera category. The output will be a file called salsify-CategoryList.xml.gz.
3. **hotcat:convert_products**: converts the locally cached products to salsify product documents. This may download additional product detail documents for related products and then load them.

Running these tasks will produce 4 files in the _salsify_ subdirectory of the specified cache directory:
* salsify-CategoriesList.xml.gz
* salsify-products.xml.gz
* salsify-products-related.xml.gz
* salsify-relations.xml.gz

They can be loaded in normally via the standard salsify data tasks.

#### Other Tasks

* **hotcat:load_suppliers**: ensures the ICEcat supplier list is downloaded locally. This task is rarely run as it is called implicitly as needed by other tasks.
* **hotcat:load_categories**: ensures the ICEcat category list document is downloaded.
