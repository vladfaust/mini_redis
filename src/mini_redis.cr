require "socket"
require "logger"
require "colorize"

require "./mini_redis/*"

# A light-weight low-level Redis client.
class MiniRedis
  # Initialize with Redis *uri* and optional *logger*.
  # The *logger* would log outcoming commands with *logger_severity* level.
  #
  # ```
  # redis = MiniRedis.new(URI.parse(ENV["REDIS_URL"]), logger: Logger.new(STDOUT))
  # ```
  def self.new(
    uri : URI = URI.parse("redis://localhost:6379"),
    logger : Logger? = nil,
    logger_severity : Logger::Severity = Logger::Severity::INFO,
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

    new(socket, logger, logger_severity)
  end

  def_equals_and_hash socket

  # Initialize with raw Crystal `Socket` and optional *logger*.
  # The *logger* would log outcoming commands with *logger_severity* level.
  def initialize(
    @socket : Socket,
    @logger : Logger? = nil,
    @logger_severity : Logger::Severity = Logger::Severity::INFO
  )
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

  # Send the *commands* marshalled according to the [Redis Protocol Specification](https://redis.io/topics/protocol).
  #
  # ```
  # redis.send("PING")       # MiniRedis::Value(@raw="PONG")
  # redis.send("GET", "foo") # MiniRedis::Value(@raw=Bytes)
  # ```
  def send(commands : Enumerable) : Value
    log(commands)

    @socket << "*" << commands.size << "\r\n"

    commands.each do |command|
      marshal(command, @socket)
    end

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
  #   # WARNING: Do not try to access its return value while
  #   # within the pipeline block. See the explaination below
  #   pipe.send("PING")
  # end
  #
  # pp response # => Array([MiniRedis::Value(@raw="PONG")])
  # ```
  #
  # WARNING: `#send` returns an `uninitalized Value` when in pipeline mode.
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
  #   pp tx.send("SET", "foo", "bar") # => MiniRedis::Value(@raw="QUEUED")
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

  protected def marshal(arg : Int, io) : Nil
    marshal(arg.to_s, io)
  end

  protected def marshal(arg : String | Char, io) : Nil
    io << "$" << arg.bytesize << "\r\n" << arg << "\r\n"
  end

  protected def marshal(arg : Bytes, io) : Nil
    io << "$" << arg.bytesize << "\r\n"
    io.write(arg)
    io << "\r\n"
  end

  protected def marshal(args : Enumerable(String | Char | Bytes), io) : Nil
    io << "$" << args.sum(&.bytesize) << "\r\n"

    args.each do |arg|
      if arg.is_a?(Bytes)
        io.write(arg)
      else
        io << arg
      end
    end

    io << "\r\n"
  end

  protected def marshal(arg : Nil, io) : Nil
    io << "$-1\r\n"
  end

  protected def log(commands : Enumerable)
    @logger.try &.log(@logger_severity) do
      String.build do |builder|
        builder << "[redis] "
        first = true
        commands.each do |cmd|
          builder << ' ' unless first; first = false
          decorate_command(cmd, builder)
        end
      end.colorize(:red).to_s
    end
  end

  protected def decorate_command(cmd, builder)
    case cmd
    when Bytes
      cmd.each do |b|
        builder << '\\' << 'x'
        builder.write_byte(to_hex(b >> 4))
        builder.write_byte(to_hex(b & 0x0f))
      end
    when String, Char, Int then builder << cmd
    when Enumerable        then cmd.each { |c| decorate_command(c, builder) }
    else
      raise "BUG: Unhandled cmd class #{cmd.class}"
    end
  end

  @[AlwaysInline]
  protected def to_hex(c)
    ((c < 10 ? 48_u8 : 87_u8) + c)
  end
end
