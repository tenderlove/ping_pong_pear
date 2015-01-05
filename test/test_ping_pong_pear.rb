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
  ensure
    Process.kill 'INT', pid
    Process.waitpid pid
  end

  def test_shutdown
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
    refute File.exist? '.git/hooks/post-commit'
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

  def test_commit
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

    original_dir = File.expand_path Dir.pwd
    Dir.chdir Dir.mktmpdir
    PingPongPear::Commands.run ['clone', project_name]
    Dir.chdir project_name

    pid2 = fork { PingPongPear::Commands.run ['start'] }
    loop do
      break if File.exist? '.git/hooks/post-commit'
    end
    File.write 'out2.txt', 'ddddd'
    system 'git add out2.txt'
    system 'git commit -m"xx"'
    require 'timeout'
    Timeout.timeout(2) {
      loop do
        break if File.exist? File.join(original_dir, 'out2.txt')
      end
    }
  ensure
    Process.kill 'INT', pid
    Process.waitpid pid
    Process.kill 'INT', pid2
    Process.waitpid pid2
  end

  def test_commit_works_on_branches
    system 'git init'
    File.write 'out.txt', 'aset'
    system 'git checkout -b xxx'
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

    original_dir = File.expand_path Dir.pwd
    Dir.chdir Dir.mktmpdir
    PingPongPear::Commands.run ['clone', project_name]
    Dir.chdir project_name

    pid2 = fork { PingPongPear::Commands.run ['start'] }
    loop do
      break if File.exist? '.git/hooks/post-commit'
    end
    File.write 'out2.txt', 'ddddd'
    system 'git checkout -b xxx'
    system 'git add out2.txt'
    system 'git commit -m"xx"'
    require 'timeout'
    Timeout.timeout(2) {
      loop do
        break if File.exist? File.join(original_dir, 'out2.txt')
      end
    }
  ensure
    Process.kill 'INT', pid
    Process.waitpid pid
    Process.kill 'INT', pid2
    Process.waitpid pid2
  end

  def test_clone_works_with_name
    system 'git init'
    File.write 'out.txt', 'aset'
    system 'git add out.txt'
    system 'git commit -m"xx"'

    project_name = 'foo'
    stderr_rd, stderr_wr = IO.pipe
    pid = fork {
      $stderr.reopen stderr_wr
      PingPongPear::Commands.run ['start', project_name]
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

  def test_commit_works_with_name
    system 'git init'
    File.write 'out.txt', 'aset'
    system 'git add out.txt'
    system 'git commit -m"xx"'

    project_name = 'foo'
    stderr_rd, stderr_wr = IO.pipe
    pid = fork {
      $stderr.reopen stderr_wr
      PingPongPear::Commands.run ['start', project_name]
    }
    stderr_wr.close
    loop do
      line = stderr_rd.readline
      break if line =~ /WEBrick::HTTPServer#start/
    end

    original_dir = File.expand_path Dir.pwd
    Dir.chdir Dir.mktmpdir
    PingPongPear::Commands.run ['clone', project_name]
    Dir.chdir project_name

    pid2 = fork { PingPongPear::Commands.run ['start', project_name] }
    loop do
      break if File.exist? '.git/hooks/post-commit'
    end
    File.write 'out2.txt', 'ddddd'
    system 'git add out2.txt'
    system 'git commit -m"xx"'
    require 'timeout'
    Timeout.timeout(2) {
      loop do
        break if File.exist? File.join(original_dir, 'out2.txt')
      end
    }
  ensure
    Process.kill 'INT', pid
    Process.waitpid pid
    Process.kill 'INT', pid2
    Process.waitpid pid2
  end
end
