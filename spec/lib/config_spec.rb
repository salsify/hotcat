require 'spec_helper'

require 'hotcat/config'

describe Config do
  let(:config) { Hotcat::Configuration }
  let(:defaults) { config.defaults }

  subject { config }
  it { should_not be_nil }

  it { should respond_to(:cache_dir) }
  it { should respond_to(:max_products) }
  it { should respond_to(:max_related_products) }
  it { should respond_to(:username) }
  it { should respond_to(:password) }

  context "before a configuration happens" do
    subject { config }
    its(:cache_dir) { should be_nil }
    its(:max_products) { should be_nil }
    its(:max_related_products) { should be_nil }
    its(:username) { should be_nil }
    its(:password) { should be_nil }
  end

  context "after a configuration happens" do
    subject { config }
    before do
      config.configure do |conf|
        conf.cache_dir = File::SEPARATOR + 'testing'
        conf.username = "foo"
        conf.password = "bar"
      end
    end

    # make sure that the extra file separator should be on the end of it
    its(:cache_dir) { should eq "#{File::SEPARATOR}testing#{File::SEPARATOR}" }

    its(:max_products) { should_not be_nil }
    its(:max_related_products) { should_not be_nil }
    its(:username) { should eq "foo" }
    its(:password) { should eq "bar" }

    context "making sure defaults work" do
      its(:max_products) { should eq defaults[:max_products] }
      its(:max_related_products) { should eq defaults[:max_related_products] }
    end
  end
end