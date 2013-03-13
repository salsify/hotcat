require 'open-uri'

require 'aws'

# Uploads images to ICEcat and provides public URLs to those images.
class Hotcat::AwsUploader


  def initialize(access_key_id, access_key, bucket_id, tmpdir)
    AWS.config(:access_key_id => access_key_id, :secret_access_key => access_key)

    @s3 = AWS::S3.new
    @bucket = @s3.buckets[bucket_id]
    @bucket = @s3.buckets.create(bucket_id) if !@bucket.exists?

    @tmpdir = tmpdir
  end


  # done by ID so that hopefully we don't have to re-upload a million times
  def upload(product_id, image_url)
    key = get_object_id(product_id, image_url)
    obj = @bucket.objects[key]

    if !obj.exists?
      puts "  Caching ICEcat image in AWS for #{product_id}"
      tmpfile = download_image(key, image_url)
      obj.write(file: tmpfile)
      obj.acl = :public_read
      File.delete(tmpfile)
    else
      # Gets chatty when dealing with thousands of products...
      # puts "  Cached ICEcat image already in AWS for #{product_id}"
    end

    obj.public_url
  end


  private


  def get_object_id(product_id, image_url)
    id = product_id.gsub('/','')
                   .gsub(/\s+/,'')
                   .gsub(/\./,'')
                   .gsub(/\\/,'')
    "#{id}#{File.extname(image_url)}"
  end


  def download_image(dest_filename, image_url)
    tmpfile = File.join(@tmpdir, dest_filename)
    open(image_url) do |f|
      File.open(tmpfile, "wb") { |file| file << f.read }
    end
    tmpfile
  end


end