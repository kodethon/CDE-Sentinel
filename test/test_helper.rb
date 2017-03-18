ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'fileutils'

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  @@user_files = '/usr/share/nginx/html/private/drives'
  @@mirror_path = '/usr/share/nginx/html/private/backup'
  @@log_path = '/usr/share/nginx/html/log/backup.log'
  
  # Warning: too many and tests will take very long to complete
  @@num_abbrevs = 3
  @@num_users = 3
  @@num_user_files = 3
  @@num_user_dirs = 3

  # Add more helper methods to be used by all tests here...

  def create_user_files()
    FileUtils.mkdir_p(@@user_files)
    FileUtils.mkdir_p('/usr/share/nginx/html/log')
 
    # All permutations of 2 char abbrevs from alphabet
    alphabet = ('a'..'z').to_a
    perm = alphabet.permutation(2).to_a

    # Iterate and join(), ['a', 'b'] -> ['ab']
    perm.map! {|abbrev| abbrev.join()}

    perm.first(@@num_abbrevs).each do |abbrev| # Create some abbrevs
      (1..@@num_users).each do |n| # Create some users per abbrev
        user_id = abbrev + rand.to_s[2..11] # user_id = abbrev + random 10 len string
        user = File.join(@@user_files, abbrev, user_id)
        FileUtils.mkdir_p(user)

        (1..@@num_user_files).each do |num| # Create some files and dirs per user
          FileUtils.touch(File.join(user, user_id + '-file-' + num.to_s))
          FileUtils.mkdir_p(File.join(user, user_id + '-dir-' + num.to_s))
        end
      end
    end
  end

  def rollback()
    FileUtils.rm_rf(@@user_files)
    FileUtils.rm_rf(@@mirror_path)
    FileUtils.rm_rf('/usr/share/nginx/html/log')
  end
end
