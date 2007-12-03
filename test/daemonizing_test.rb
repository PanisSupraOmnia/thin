require File.dirname(__FILE__) + '/test_helper'
require 'timeout'

class DaemonizerTest < Test::Unit::TestCase
  def setup
    TCPServer.stubs(:new) # We don't need a real socket for this
    @server = Thin::Server.new('0.0.0.0', 3000)
    @server.pid_file = 'test.pid'
  end
  
  def teardown
    @server.stop!
  end
  
  def test_pid_file
    @server.respond_to? :pid_file
    @server.respond_to? :pid_file=
  end
  
  def test_daemonize_creates_pid_file
    pid = fork do
      @server.daemonize
      sleep 0.5
    end

    Process.wait(pid)
    assert File.exist?(@server.pid_file)

    timeout 1 do
      sleep 0.1 while File.exist?(@server.pid_file)
    end
  end
  
  def test_redirect_stdio_to_log_file
    pid = fork do
      @server.log_file = 'daemon_test.log'

      @server.daemonize

      puts "simple puts"
      STDERR.puts "STDERR.puts"
      STDOUT.puts "STDOUT.puts"
    end
    Process.wait(pid)
    sleep 0.1 # Wait for the file to close and magical stuff to happen
    
    log = File.read('daemon_test.log')
    assert_match /simple puts/, log
    assert_match /STDERR.puts/, log
    assert_match /STDOUT.puts/, log
  ensure
    File.delete 'daemon_test.log'
  end
  
  def test_change_privilege
    pid = fork do
      @server.daemonize
      @server.change_privilege('root', 'admin')
    end
    Process.wait(pid)
    assert $?.success?
  end
  
  def test_kill
    pid = fork do
      @server.daemonize
      loop {}
    end
    
    timeout 3 do
      sleep 0.1 until File.exist?(@server.pid_file)
    end
    
    silence_stream STDOUT do
      Thin::Server.kill(@server.pid_file, 1)
    end
    
    assert !File.exist?(@server.pid_file)
  ensure
    Process.kill 9, pid rescue nil
  end
  
  def test_send_kill_signal_if_timeout
    pid = fork do
      trap('INT', 'IGNORE') # pretend we cannot handle INT signal
      @server.daemonize
      loop {}
    end
    
    Timeout.timeout 10 do
      sleep 0.1 until File.exist?(@server.pid_file)
    end
    
    silence_stream STDOUT do
      Thin::Server.kill(@server.pid_file, 1) rescue nil
    end
    
    assert !File.exist?(@server.pid_file)
  ensure
    Process.kill 9, pid rescue nil
  end
end