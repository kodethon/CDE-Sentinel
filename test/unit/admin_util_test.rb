require 'test_helper' 

class AdminUtilsTest < ActiveSupport::TestCase

    test "du -sh to bytes should return a number" do
        d = AdminUtils::Disk.du_sh_to_bytes(Rails.root.to_s)
        assert d.is_a? Integer
    end

end
