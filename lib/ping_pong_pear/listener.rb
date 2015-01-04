require 'socket'
require 'ipaddr'
require 'json'
require 'ping_pong_pear'

module PingPongPear
  class Listener
    def initialize
      @multicast_addr = "224.0.0.1"
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
end
