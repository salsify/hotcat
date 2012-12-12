require "hotcat/version"

module Hotcat
  class HotcatTasks < ::Rails::Railtie
    rake_tasks do
      load 'hotcat/hotcat_tasks.rake'
    end
  end
end
