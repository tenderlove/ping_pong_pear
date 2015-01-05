require 'socket'
require 'ipaddr'
require 'json'

module PingPongPear
  VERSION        = '1.0.0'
  UDP_PORT       = 4545
  MULTICAST_ADDR = "224.0.0.1"

  class Broadcaster
    def self.my_public_address
      Socket.ip_address_list.reject { |addr|
        addr.ipv4_loopback? || addr.ipv6_loopback? || addr.ipv6_linklocal?
      }.first
    end

    def self.send_update args
      new.send ['commit'] + args
    end

    def self.send_location name, port
      new.send ['source', name, my_public_address.ip_address, port]
    end

    def self.where_is? name
      listener_t = Thread.new {
        listener = Listener.new
        listener.start { |cmd, *rest|
          if cmd == 'source' && rest.first == name
            break(rest.drop(1))
          end
        }
      }
      broadcast = new
      while listener_t.alive?
        broadcast.send ['locate', name]
      end
      addr, port = listener_t.value
      "http://#{addr}:#{port}/"
    end

    def initialize
      @multicast_addr = MULTICAST_ADDR
      @port           = UDP_PORT
      @socket         = UDPSocket.open
      @socket.setsockopt :IPPROTO_IP, :IP_MULTICAST_TTL, 1
    end

    def send message
      @socket.send(JSON.dump(message), 0, @multicast_addr, @port)
    end
  end

  class Listener
    def initialize
      @multicast_addr = MULTICAST_ADDR
      @bind_addr      = "0.0.0.0"
      @port           = UDP_PORT

      @socket = UDPSocket.new
      membership = IPAddr.new(@multicast_addr).hton + IPAddr.new(@bind_addr).hton

      @socket.setsockopt :IPPROTO_IP, :IP_ADD_MEMBERSHIP, membership
      @socket.setsockopt :SOL_SOCKET, :SO_REUSEPORT, 1

      @socket.bind @bind_addr, @port
    end

    def start
      loop do
        message, _ = @socket.recvfrom 1024
        yield JSON.parse(message)
      end
    end
  end

  module Commands
    def self.start args
      require 'webrick'
      require 'securerandom'

      project_name     = args.first || File.basename(Dir.pwd)
      post_commit_hook = '.git/hooks/post-commit'
      uuid             = SecureRandom.uuid

      system 'git update-server-info'

      server = WEBrick::HTTPServer.new Port: 0, DocumentRoot: '.git'
      http_port = server.listeners.map { |x| x.addr[1] }.first

      File.open(post_commit_hook, 'w') { |f|
        f.puts "#!/usr/bin/env ruby"
        f.puts "ARGV[0] = 'update'"
        f.puts "ARGV[1] = '#{project_name}'"
        f.puts "ARGV[2] = '#{uuid}'"
        f.puts "ARGV[3] = '#{Broadcaster.my_public_address.ip_address}'"
        f.puts "ARGV[4] = '#{http_port}'"
        f.write File.read __FILE__
      }
      File.chmod 0755, post_commit_hook

      Thread.new {
        listener = PingPongPear::Listener.new
        listener.start { |cmd, name, *rest|
          next unless name == project_name

          case cmd
          when 'locate' then Broadcaster.send_location project_name, http_port
          when 'commit'
            unless rest.first == uuid
              url = "http://#{rest.drop(1).join(':')}"
              system "git pull #{url}"
            end
          end
        }
      }

      trap('INT') {
        File.unlink post_commit_hook
        server.shutdown
      }
      server.start
    end

    def self.clone args
      require 'shellwords'
      name = args.first
      url = PingPongPear::Broadcaster.where_is? name
      system "git clone #{Shellwords.escape(url)} #{Shellwords.escape(name)}"
    end

    def self.update args
      system 'git update-server-info'
      PingPongPear::Broadcaster.send_update args
    end

    def self.run args
      send args.first, args.drop(1)
    end
  end
end

PingPongPear::Commands.run(ARGV) if $0 == __FILE__
