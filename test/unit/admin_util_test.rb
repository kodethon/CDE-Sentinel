require 'test_helper' 

class AdminUtilsTest < ActiveSupport::TestCase

    test "du -sh to bytes should return a number" do
        d = AdminUtils::Disk.du_sh_to_bytes(Rails.root.to_s)
        assert d.is_a? Integer
    end

    test "kill all should kill all containers" do
        key = 'a.b.c'
        Open3.capture3("docker run -itd --rm --name %s-python hello-world" % key)
        AdminUtils::Containers.kill_all(key)
        stdout, stderr, status = Open3.capture3("docker ps | grep %s" % key)
        assert stdout.length == 0
        Open3.capture3("docker rm %s" % key)
    end

end
