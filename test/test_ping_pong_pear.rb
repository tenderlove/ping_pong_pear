require 'minitest/autorun'
require 'ping_pong_pear'
require 'tmpdir'

class TestPingPongPear < MiniTest::Test
  def setup
    super
    @current_dir = Dir.pwd
    Dir.chdir Dir.mktmpdir
  end

  def teardown
    Dir.chdir @current_dir
    super
  end

  def test_boot
    system 'git init'
    stderr_rd, stderr_wr = IO.pipe
    pid = fork {
      $stderr.reopen stderr_wr
      PingPongPear::Commands.run ['start']
    }
    stderr_wr.close
    loop do
      line = stderr_rd.readline
      break if line =~ /WEBrick::HTTPServer#start/
    end
    assert File.exist? '.git/hooks/post-commit'
    Process.kill 'INT', pid
    Process.waitpid pid
  end

  def test_clone
    system 'git init'
    File.write 'out.txt', 'aset'
    system 'git add out.txt'
    system 'git commit -m"xx"'

    project_name = File.basename Dir.pwd
    stderr_rd, stderr_wr = IO.pipe
    pid = fork {
      $stderr.reopen stderr_wr
      PingPongPear::Commands.run ['start']
    }
    stderr_wr.close
    loop do
      line = stderr_rd.readline
      break if line =~ /WEBrick::HTTPServer#start/
    end

    Dir.chdir Dir.mktmpdir
    PingPongPear::Commands.run ['clone', project_name]

    assert File.exist?(project_name), 'should be cloned'
    assert File.exist? File.join(project_name, 'out.txt')
  ensure
    Process.kill 'INT', pid
    Process.waitpid pid
  end
end
