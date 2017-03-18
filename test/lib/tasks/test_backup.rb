require 'test_helper'
 
class BackupTest < ActiveSupport::TestCase

  test "simulation abbrevs count" do
    create_user_files()
    abbrev_count = `ls -1 #{@@user_files} | wc -l`.to_i

    rollback()
    assert_equal @@num_abbrevs, abbrev_count
  end

  test "simulation users count" do
    create_user_files() 
    user_count = 0

    Dir.foreach(@@user_files) do |abbrev|
      next if abbrev == '.' or abbrev == '..'
      abbrev_path = File.join(@@user_files, abbrev)

      Dir.foreach(abbrev_path) do |user_id|
        next if user_id == '.' or user_id == '..'
        user_count += 1 
      end
    end

    rollback()
    assert_equal (@@num_abbrevs * @@num_users), user_count
  end 

  test "simulation user owned files and dirs count" do
    create_user_files()
    file_count = 0

    Dir.foreach(@@user_files) do |abbrev|
      next if abbrev == '.' or abbrev == '..'
      abbrev_path = File.join(@@user_files, abbrev)

      Dir.foreach(abbrev_path) do |user_id|
        next if user_id == '.' or user_id == '..'
        user_id_path = File.join(abbrev_path, user_id)

        Dir.foreach(user_id_path) do |file|
          next if file == '.' or file == '..'
          file_count += 1
        end
      end
    end

    rollback()
    assert_equal (@@num_abbrevs * @@num_users * (@@num_user_files + @@num_user_dirs)), file_count
  end

  test "backup folder created" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    backup_created = File.directory?(@@mirror_path)

    rollback()
    assert backup_created
  end

  test "number of abbrevs in mirror" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    mirror_dir_count = `ls -1 #{@@mirror_path} | wc -l`.to_i
    user_files_dir_count = `ls -1 #{@@user_files} | wc -l`.to_i

    rollback()
    assert_equal user_files_dir_count, mirror_dir_count
  end

  test "number of users in mirror" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    user_count = 0
    
    Dir.foreach(@@mirror_path) do |abbrev|
      next if abbrev == '.' or abbrev == '..'
      abbrev_path = File.join(@@mirror_path, abbrev)

      Dir.foreach(abbrev_path) do |user_id|
        next if user_id == '.' or user_id == '..'
        user_count += 1 
      end
    end

    rollback()
    assert_equal (@@num_abbrevs * @@num_users), user_count
  end

  test "log/backup.log creation" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    log_created = File.exists?(@@log_path)

    rollback()
    assert log_created
  end

  test "borg init success" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke

    Dir.foreach(@@mirror_path) do |abbrev|
      next if abbrev == '.' or abbrev == '..'
      abbrev_path = File.join(@@mirror_path, abbrev)

      Dir.foreach(abbrev_path) do |user_id|
        next if user_id == '.' or user_id == '..'
        user_id_path = File.join(abbrev_path, user_id)

        # glob to check if directory is empty
        assert false if Dir[user_id_path + '/*'].empty?
      end
    end

    rollback()
    assert true
  end

  test "borg init logging" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    init_logged = !File.zero?(@@log_path) # exists and not empty

    rollback()
    assert init_logged
  end

  test "snapshot success" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    Rake::Task["backup:snapshot"].reenable
    Rake::Task["backup:snapshot"].invoke("Once")

    Dir.foreach(@@mirror_path) do |abbrev|
      next if abbrev == '.' or abbrev == '..'
      abbrev_path = File.join(@@mirror_path, abbrev)

      Dir.foreach(abbrev_path) do |user_id|
        next if user_id == '.' or user_id == '..'
        user_id_path = File.join(abbrev_path, user_id)
        assert false if `borg list #{user_id_path}`.include? 'does not exist'
      end
    end

    rollback()
    assert true
  end

  test "snapshot logging" do
    create_user_files()
    Rake::Task["backup:diff"].reenable
    Rake::Task["backup:diff"].invoke
    Rake::Task["backup:snapshot"].reenable
    Rake::Task["backup:snapshot"].invoke("Once")

    # Open backup.log, grep for 'SNAPSHOT',
    # returns array with lines matching,
    # then check if not empty
    snapshot_logged = !(open(@@log_path) { |f| 
      f.each_line.detect { |line| 
        /SNAPSHOT/.match(line) 
      }
    }.empty?)

    rollback()
    assert snapshot_logged
  end

  test "on demand snapshot success" do
    #create_user_files()
    #Rake::Task["backup:diff"].reenable
    #Rake::Task["backup:diff"].invoke
    #Rake::Task["backup:snapshot_ondemand"].reenable
    #Rake::Task["backup:snapshot_ondemand"].invoke("Once")



    #rollback()
    #assert true
  end

  test "borg prune success" do

  end

  test "prune logging" do

  end
end
