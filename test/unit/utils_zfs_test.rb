require 'test_helper' 

class UtilsZFSTest < ActiveSupport::TestCase

  test "ZFS create should create a dataset" do
    fs = Utils::ZFS.create('abc')
    assert fs.exist?
  end

end
