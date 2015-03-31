require 'dnssd'
require 'webrick'
require 'securerandom'
require 'set'
require 'net/http'
require 'logger'
require 'shellwords'

class PingPongPear
  VERSION = '2.0.0'

  SERVICE = "_http._tcp,pingpongpear"

  def self.run args
    new.public_send args.first, *args.drop(1)
  end

  attr_reader :pull_requests, :peers, :logger

  def initialize
    @pull_requests      = Queue.new
    @send_pull_requests = Queue.new
    @peers              = Set.new
    @logger             = Logger.new $stdout
  end

  def start name = File.basename(Dir.pwd)
    post_commit_hook = '.git/hooks/post-commit'
    pidfile = '.git/pingpongpear.pid'

    if File.exist? pidfile
      raise "Another instance of Ping Pong Pear is running"
    else
      File.open(pidfile, 'w') { |f| f.write $$ }
    end

    File.open(post_commit_hook, 'w') { |f|
      f.write <<-eof
#!/bin/sh

git update-server-info
kill -INFO $(cat #{pidfile})
      eof
    }
    File.chmod 0755, post_commit_hook

    system "git update-server-info"

    at_exit {
      File.unlink pidfile
      File.unlink post_commit_hook
    }

    identifier    = make_ident name

    logger.debug "MY PROJECT NAME: #{name} IDENT: #{identifier}"

    server        = start_server pull_requests
    http_port     = server.listeners.map { |x| x.addr[1] }.first
    hostname      = Socket.gethostname

    discover identifier, name, peers
    process_pull_requests pull_requests
    process_send_pull_requests @send_pull_requests

    trap('INFO') { send_pull_requests peers, hostname, http_port }

    advertise(identifier, name, hostname, http_port).each { |x| x }
  end

  def clone name, dir = nil
    browser = DNSSD::Service.browse SERVICE
    browser.each do |response|
      r = response.resolve
      if r.text_record['project'] == name
        url = "http://#{r.target}:#{r.port}"
        system "git clone #{Shellwords.escape(url)} #{dir || Shellwords.escape(name)}"
        break
      end
    end
  end

  private

  def start_server pull_requests
    server = WEBrick::HTTPServer.new Port: 0,
                                     DocumentRoot: '.git',
                                     Logger: logger
    server.mount_proc '/pull' do |req, res|
      host = req.query['host']
      port = req.query['port']
      if host && port
        logger.info "ADDED PR: #{host}:#{port}"
        pull_requests << [host, port.to_i]
      end
      res.body = ''
    end
    Thread.new { server.start }
    server
  end

  def advertise ident, name, hostname, http_port
    txt = DNSSD::TextRecord.new 'project' => name
    DNSSD::Service.register ident, SERVICE, nil, http_port, hostname, txt
  end

  def make_ident name
    "#{name} (#{SecureRandom.hex.slice(0, 4)})"
  end

  def discover ident, name, peers
    browser = DNSSD::Service.browse SERVICE
    browser.async_each do |response|
      if response.flags.to_i > 0
        logger.debug "SAW: #{response.name}"
        unless response.name == ident
          r = response.resolve
          if r.text_record['project'] == name
            logger.info "PEER: #{response.name}"
            peers << [response.name, r.target, r.port]
          end
        end
      else
        peers.delete_if { |id, _, _| id == response.name }
        logger.info "REMOVED: #{response.name}"
      end
    end
  end

  def send_pull_requests peers, http_host, http_port
    peers.each do |_, host, port|
      @send_pull_requests << [host, port, http_host, http_port]
    end
  end

  def process_send_pull_requests requests
    Thread.new do
      while pr = requests.pop
        host, port, http_host, http_port = *pr
        http    = Net::HTTP.new host, port
        request = Net::HTTP::Post.new '/pull'
        request.set_form_data 'host' => http_host, 'port' => http_port
        http.request request
      end
    end
  end

  def process_pull_requests pull_requests
    Thread.new do
      while pr = pull_requests.pop
        url = "http://#{pr.join(':')}"
        logger.debug "git pull #{Shellwords.escape(url)}"
        system "git pull #{Shellwords.escape(url)}"
      end
    end
  end
end

PingPongPear.run(ARGV) if $0 == __FILE__
