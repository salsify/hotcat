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

#### Primary Task

There is one main rake task that _should_ take care of everything in one fell swoop

```bash
rake hotcat:generate_salsify_import
```

This will produce a single file called `salsify-import.zip` in the _salsify_ subdirectory of the cache directory specified in your hotcat configuration. That zipfile can be fed directly to Salsify using one of the two following commands:
```bash
  rake salsify:clean_load file=/path/to/cache/dir/salsify-import.zip
  rake salsify:load file=/path/to/cache/dir/salsify-import.zip
```
That the first of these runs a *clean_load* which will reset the database. The *load* command is simply additive. If you just want to add to an existing database without resetting you can run *load* with the categories file instead of *clean_load* and everything should still work fine.

If the salsify-import.zip file exists when the rake task is run, it will be moved to a time-stamped version of the file such as salsify-import-TIMESTAMP.zip before a fresh salsify-import.zip file is generated.

#### Other Tasks

These tasks are rarely run individually as they are called implicitly as needed by other tasks. There are provided separately primarily for debugging.

* **hotcat:load_suppliers**: ensures the ICEcat supplier list is downloaded locally.
* **hotcat:load_categories**: ensures the ICEcat category list document is downloaded.
* **hotcat:convert_categories**: grabs the ICEcat category document and converts it to Salsify's data ingest format.
* **hotcat:build_product_camera_cache**: downloads details for up to the maximum number of products specified in the hotcat configuration in the camera category. The output will be a file called salsify-CategoryList.xml.gz.
* **hotcat:convert_products**: converts the locally cached products to salsify product documents. This may download additional product detail documents for related products and then load them.