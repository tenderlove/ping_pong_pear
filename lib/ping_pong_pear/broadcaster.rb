require 'socket'
require 'json'
require 'ping_pong_pear'

module PingPongPear
  class Broadcaster
    def self.my_public_address
      Socket.ip_address_list.reject { |addr|
        addr.ipv4_loopback? || addr.ipv6_loopback? || addr.ipv6_linklocal?
      }.first
    end

    def self.send_update name
      new.send [my_public_address.ip_address, HTTP_PORT, name]
    end

    def initialize
      @multicast_addr = "224.0.0.1"
      @port           = UDP_PORT
      @socket         = UDPSocket.open
      @socket.setsockopt :IPPROTO_IP, :IP_MULTICAST_TTL, 1
    end

    def send message
      @socket.send(JSON.dump(message), 0, @multicast_addr, @port)
    end
  end
end
