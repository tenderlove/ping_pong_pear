require 'socket'
require 'ipaddr'
require 'json'

module PingPongPear
  VERSION        = '1.0.0'
  HTTP_PORT      = 4544
  UDP_PORT       = 4545
  MULTICAST_ADDR = "224.0.0.1"

  class Broadcaster
    def self.my_public_address
      Socket.ip_address_list.reject { |addr|
        addr.ipv4_loopback? || addr.ipv6_loopback? || addr.ipv6_linklocal?
      }.first
    end

    def self.send_update name
      new.send ['commit', my_public_address.ip_address, HTTP_PORT, name]
    end

    def self.send_location name
      new.send ['source', name, my_public_address.ip_address, HTTP_PORT]
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

      project_name = args.first || File.basename(Dir.pwd)
      post_commit_hook = '.git/hooks/post-commit'

      system 'git update-server-info'
      File.open(post_commit_hook, 'w') { |f|
        f.puts "#!/usr/bin/env ruby"
        f.puts "ARGV[0] = 'update'"
        f.puts "ARGV[1] = '#{project_name}'"
        f.write File.read __FILE__
      }
      File.chmod 0755, post_commit_hook

      Thread.new {
        listener = PingPongPear::Listener.new
        listener.start { |cmd, *rest|
          if cmd == 'locate' && rest.first == project_name
            Broadcaster.send_location project_name
          end
        }
      }

      server = WEBrick::HTTPServer.new Port: HTTP_PORT, DocumentRoot: '.git'

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
      PingPongPear::Broadcaster.send_update args.first
    end

    def self.run args
      send args.first, args.drop(1)
    end
  end
end

PingPongPear::Commands.run(ARGV) if $0 == __FILE__
