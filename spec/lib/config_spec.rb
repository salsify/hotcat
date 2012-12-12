require 'spec_helper'

require 'hotcat/config'

describe Config do
  let(:config) { Hotcat::Configuration }
  let(:defaults) { config.defaults }

  subject { config }
  it { should_not be_nil }

  it { should respond_to(:icecat_domain) }
  it { should respond_to(:cache_dir) }
  it { should respond_to(:max_products) }
  it { should respond_to(:max_related_products) }
  it { should respond_to(:username) }
  it { should respond_to(:password) }

  context "before a configuration happens" do
    subject { config }
    its(:icecat_domain) { should be_nil }
    its(:cache_dir) { should be_nil }
    its(:max_products) { should be_nil }
    its(:max_related_products) { should be_nil }
    its(:username) { should be_nil }
    its(:password) { should be_nil }
  end

  context "after a configuration happens" do
    before do
      config.configure do |config|
        config.cache_dir = '/'
        config.username = "foo"
        config.password = "bar"
      end
    end
    subject { config }

    its(:icecat_domain) { should_not be_nil }
    its(:cache_dir) { should eq '/' }
    its(:max_products) { should_not be_nil }
    its(:max_related_products) { should_not be_nil }
    its(:username) { should eq "foo" }
    its(:password) { should eq "bar" }

    context "making sure defaults work" do
      its(:icecat_domain) { should eq defaults[:icecat_domain] }
      its(:max_products) { should eq defaults[:max_products] }
      its(:max_related_products) { should eq defaults[:max_related_products] }
    end
  end
end