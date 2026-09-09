require 'English'
require 'base64'
require 'logger'
require 'strscan'

unless StringScanner.method_defined?(:peep)
  class StringScanner
    alias peep peek
  end
end

require 'active_support'
require 'active_support/core_ext'
require 'colorize'
require 'dotenv'
require 'erb'
require 'kwalify'
require 'ostruct'
require 'thor'
require 'thor/group'
require 'yaml'

require 'wordmove/ssh_runner'
require 'photocopier'

require 'wordmove/cli'
require 'wordmove/doctor'
require 'wordmove/doctor/movefile'
require 'wordmove/doctor/mysql'
require 'wordmove/doctor/rsync'
require 'wordmove/doctor/ssh'
require 'wordmove/doctor/wpcli'
require 'wordmove/exceptions'
require 'wordmove/guardian'
require 'wordmove/hook'
require 'wordmove/logger'
require 'wordmove/movefile'
require 'wordmove/sql_adapter/wpcli'
require 'wordmove/wordpress_directory'
require "wordmove/version"
require "wordmove/environments_list"

require 'wordmove/generators/movefile_adapter'
require 'wordmove/generators/movefile'

require 'wordmove/deployer/base'
require 'wordmove/deployer/ssh'

module Wordmove
end
