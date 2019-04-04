require "socket"

require "./mini_redis/*"

# A light-weight low-level Redis client.
class MiniRedis
  # Initialize with Redis `URI`.
  #
  # ```
  # redis = MiniRedis.new(URI.parse(ENV["REDIS_URL"]))
  # ```
  def self.new(
    uri : URI = URI.parse("redis://localhost:6379"),
    dns_timeout : Time::Span? = 5.seconds,
    connect_timeout : Time::Span? = 5.seconds,
    read_timeout : Time::Span? = nil,
    write_timeout : Time::Span? = 5.seconds
  )
    socket = TCPSocket.new(
      host: uri.host.not_nil!,
      port: uri.port.not_nil!,
      dns_timeout: dns_timeout,
      connect_timeout: connect_timeout
    )

    socket.sync = false
    socket.read_timeout = read_timeout
    socket.write_timeout = write_timeout

    new(socket)
  end

  def_equals_and_hash socket

  # Initialize with raw Crystal `Socket`.
  def initialize(@socket : Socket)
  end

  def finalize
    close
  end

  # Close the underlying socket.
  def close
    @socket.close
  end

  # The underlying socket.
  getter socket

  # Whether is current connection in transaction mode. See `#transaction`.
  getter? transaction : Bool = false

  # Whether is current connection in pipeline mode. See `#pipeline`.
  getter? pipeline : Bool = false

  # Send a `String` inline *command*.
  # It's a bit slower than the `Enumerable` (i.e. bytes) version,
  # but allows to pass commands in one line.
  #
  # See [Redis Protocol: Inline Commands](https://redis.io/topics/protocol#inline-commands) for more information.
  def send(command : String) : Value
    @socket << command << "\r\n"
    send_impl
  end

  # Send the *commands* marshalled according to the [Redis Protocol Specification](https://redis.io/topics/protocol).
  def send(commands : Enumerable) : Value
    marshal(commands, @socket)
    send_impl
  end

  # ditto
  def send(*commands) : Value | Nil
    send(commands)
  end

  @queued = 0

  # Yield `self`, accumulate requests and then flush them all in one moment.
  # See [Pipelining docs](https://redis.io/topics/pipelining).
  #
  # It returns an `Array` of `Value`s.
  #
  # ```
  # response = redis.pipeline do |pipe|
  #   pipe.send("PING")
  # end
  #
  # pp response # => Array([MiniRedis::Value(@raw="PONG")])
  # ```
  #
  # NOTE: `#send` returns an `uninitalized Value` when in pipeline mode.
  # Trying to access it would crash the program. Use `#pipeline?` if you want to be sure.
  #
  # ```
  # # When you're not sure about the `redis` type...
  #
  # # Wrong ✖️
  # puts redis.send("PING") # May crash with `Invalid memory access`
  #
  # # Right ✔️
  # unless redis.pipeline?
  #   puts redis.send("PING")
  # end
  # ```
  def pipeline(&block : self ->) : Array(Value)
    @pipeline = true
    @queued = 0

    yield(self)

    @socket.flush
    @pipeline = false

    @queued.times.reduce(Array(Value).new(@queued)) do |ary|
      ary << receive
    end
  end

  # Send `"MULTI"` command, yield `self` and then send `"EXEC"` command.
  # See [Transactions docs](https://redis.io/topics/transactions).
  #
  # It returns a `Value` containing an `Array` of `Value`s.
  #
  # ```
  # response = redis.transaction do |tx|
  #   pp tx.send("SET foo bar") # => MiniRedis::Value(@raw="QUEUED")
  # end
  #
  # pp response # => MiniRedis::Value(@raw=[MiniRedis::Value(@raw=Bytes)])
  # ```
  def transaction(&block : self ->) : Value
    send("MULTI")

    @transaction = true.try do
      yield(self); false
    end

    send("EXEC")
  end

  # Internal `#send` implementation.
  protected def send_impl : Value
    unless @pipeline
      @socket.flush
    end

    if @pipeline
      @queued += 1
      value = uninitialized Value
    elsif @transaction
      value = receive(skip_queued: true)
    else
      value = receive
    end

    return value
  end

  # :nodoc:
  QUEUED_BYTESIZE = "QUEUED\r\n".bytesize

  # Read a response. Blocks until read. The response is cast to a Crystal type
  # according to the [Redis Protocol Specification](https://redis.io/topics/protocol).
  # For more information on types, see `Value`.
  #
  # In case of error (`-` byte), a `Error` is raised.
  #
  # There is an optional *skip_queue* argument, which is used in `Transaction` mode --
  # it skips reading `"QUEUED"` strings, which improves the performance.
  protected def receive(*, skip_queued = false) : Value
    type = @socket.read_char

    case type
    when '-'
      raise Error.new(read_line)
    when ':'
      return Value.new(read_line.to_i64)
    when '$'
      length = read_line.to_i32
      return Value.new(nil) if length == -1

      bytes = Bytes.new(length)
      @socket.read_fully(bytes)

      @socket.skip(2)
      return Value.new(bytes)
    when '+'
      if skip_queued
        @socket.skip(QUEUED_BYTESIZE)
        return Value.new("QUEUED")
      else
        return Value.new(read_line)
      end
    when '*'
      size = read_line.to_i

      if size == -1
        return Value.new(nil)
      else
        return size.times.reduce(Value.new(Array(Value).new(size))) do |val, _|
          val.raw.as(Array).push(receive)
          val
        end
      end
    else
      raise Error.new("Received invalid type string '#{type}'")
    end
  end

  protected def read_line : String
    @socket.gets || raise ConnectionError.new("The Redis server has closed the connection")
  end

  protected def marshal(arg : Enumerable, io) : Nil
    io << "*" << arg.size << "\r\n"

    arg.each do |element|
      marshal(element, io)
    end
  end

  protected def marshal(arg : Int, io) : Nil
    io << ":" << arg << "\r\n"
  end

  protected def marshal(arg : String | Char, io) : Nil
    io << "$" << arg.bytesize << "\r\n" << arg << "\r\n"
  end

  protected def marshal(arg : Bytes, io) : Nil
    io << "$" << arg.bytesize << "\r\n"
    io.write(arg)
    io << "\r\n"
  end

  protected def marshal(arg : Nil, io) : Nil
    io << "$-1\r\n"
  end
end
