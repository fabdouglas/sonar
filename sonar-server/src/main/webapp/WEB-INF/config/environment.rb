# Specifies gem version of Rails to use when vendor/rails is not present
#RAILS_GEM_VERSION = '2.3.5' unless defined? RAILS_GEM_VERSION

# Avoid conflict with local ruby installations
# See http://jira.codehaus.org/browse/SONAR-3579
ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require 'color'

#
# Limitation of Rails 2.3 and Rails Engines (plugins) when threadsafe! is enabled in production mode
# See http://groups.google.com/group/rubyonrails-core/browse_thread/thread/9067bce01444fb24?pli=1
#
class EagerPluginLoader < Rails::Plugin::Loader
  def add_plugin_load_paths
    super
    plugins.each do |plugin|
      if configuration.cache_classes
        configuration.eager_load_paths += plugin.load_paths
      end
    end
  end
end

Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence over those specified here.
  # Application configuration should go into files in config/initializers
  # -- all .rb files in that directory are automatically loaded.
  # See Rails::Configuration for more options.

  # Skip frameworks you're not going to use. To use Rails without a database
  # you must remove the Active Record framework.
  config.frameworks -= [ :action_mailer ]

  # This property can't be set in config/environments because of execution order
  # See http://strd6.com/2009/04/cant-dup-nilclass-maybe-try-unloadable/
  config.reload_plugins=(RAILS_ENV == 'development')

  config.plugin_loader = EagerPluginLoader

  # Load the applications that are packaged with sonar plugins.
  # The development mode (real-time edition of ruby code) can be enabled on an app by replacing the
  # following line by :
  # config.plugin_paths << '/absolute/path/to/myproject/src/main/resources/org/sonar/ror'
  config.plugin_paths << "#{Java::OrgSonarServerUi::JRubyFacade.getInstance().getServerHome()}/temp/ror"

  # Force all environments to use the same logger level
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug

  # Make Time.zone default to the specified zone, and make Active Record store time values
  # in the database in UTC, and return them converted to the specified local zone.
  # Run "rake -D time" for a list of tasks for finding time zone names. Comment line to use default local time.
  # config.time_zone = 'UTC'

  # The internationalization framework can be changed to have another default locale (standard is :en) or more load paths.
  # All files from config/locales/*.rb,yml are added automatically.
  
  # Default locales provided by Ruby on Rails
  config.i18n.load_path << Dir[File.join(RAILS_ROOT, 'config', 'locales', '**', '*.{rb,yml}')] 
  
  # Overridden bundles
  config.i18n.load_path << Dir[File.join(RAILS_ROOT, 'config', 'locales', '*.{rb,yml}')] 
  
  config.i18n.default_locale = :en

  # Provided by JRuby-Rack
  config.action_controller.session_store = :java_servlet_store

  # Use SQL instead of Active Record's schema dumper when creating the test database.
  # This is necessary if your schema can't be completely dumped by the schema dumper,
  # like if you have constraints or database-specific column types
  # config.active_record.schema_format = :sql

  # Activate observers that should always be running
  # Please note that observers generated using script/generate observer need to have an _observer suffix
  # config.active_record.observers = :cacher, :garbage_collector, :forum_observer
end



class ActiveRecord::Migration
  def self.alter_to_big_primary_key(tablename)
    dialect = ::Java::OrgSonarServerUi::JRubyFacade.getInstance().getDatabase().getDialect().getActiveRecordDialectCode()
    case dialect
    when "postgre"
      execute "ALTER TABLE #{tablename} ALTER COLUMN id TYPE bigint"
    when "mysql"
      execute "ALTER TABLE #{tablename} CHANGE id id BIGINT AUTO_INCREMENT"
    when "h2"
      # not needed?
    when "oracle"
      # do nothing, oracle integer are big enough
    when "sqlserver"
        constraint=select_one "select name from sysobjects where parent_obj = (select id from sysobjects where name = '#{tablename}')"
        execute "ALTER TABLE #{tablename} DROP CONSTRAINT #{constraint["name"]}"
  	    execute "ALTER TABLE #{tablename} ALTER COLUMN id bigint"
    	  execute "ALTER TABLE #{tablename} ADD PRIMARY KEY(id)"
    end
  end

  def self.alter_to_big_integer(tablename, columnname, indexname=nil)
    dialect = ::Java::OrgSonarServerUi::JRubyFacade.getInstance().getDatabase().getDialect().getActiveRecordDialectCode()
    case dialect
     when "sqlserver"
     		execute "DROP INDEX #{indexname} on #{tablename}" if indexname
     		change_column(tablename, columnname, :big_integer, :null => true)
     		execute "CREATE INDEX #{indexname} on #{tablename}(#{columnname})" if indexname
     else
		   change_column(tablename, columnname, :big_integer, :null => true)
     end
  end
end

# patch for SONAR-1182. GWT does not support ISO8601 dates that end with 'Z'
# http://google-web-toolkit.googlecode.com/svn/javadoc/1.6/com/google/gwt/i18n/client/DateTimeFormat.html
module ActiveSupport
  class TimeWithZone
    def xmlschema
      # initial code: "#{time.strftime("%Y-%m-%dT%H:%M:%S")}#{formatted_offset(true, 'Z')}"
      "#{time.strftime("%Y-%m-%dT%H:%M:%S")}#{formatted_offset(true, nil)}"
    end
  end
end

#
# other patches :
# - activerecord : fix Oracle bug when more than 1000 elements in IN clause. See lib/active_record/association_preload.rb
#   See https://github.com/rails/rails/issues/585
# - actionview NumberHelper, patch for number_with_precision()

require File.dirname(__FILE__) + '/../lib/sonar_webservice_plugins.rb'
require File.dirname(__FILE__) + '/../lib/database_version.rb'
DatabaseVersion.automatic_setup


#
#
# IMPORTANT NOTE
# Some changes have been done in activerecord-jdbc-adapter. Most of them relate to column types.
# All these changes are prefixed by the comment #sonar
#
#