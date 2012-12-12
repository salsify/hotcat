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

I recommend you do this in Rails using initializers. Basically put a hotcat.rb file into config/initializers and you'll be good to go.

### Rake tasks

TODO: document rake tasks