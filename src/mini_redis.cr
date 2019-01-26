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
    read_timeout : Time::Span? = 5.seconds,
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

  # Send a `String` inline *command*.
  # It's generally faster than the `Enumerable` version, because it skips marshalling.
  # However, inline commands could be a worse fit for operations with binary keys or values.
  #
  # See [Redis Protocol: Inline Commands](https://redis.io/topics/protocol#inline-commands) for more information.
  def send(command : String) : Nil
    @socket << command << "\r\n"
    @socket.flush
  end

  # Send the *commands* marshalled according to the [Redis Protocol Specification](https://redis.io/topics/protocol).
  # For inline commands consider using `String` version.
  def send(commands : Enumerable) : Nil
    marshal(commands, @socket)
    @socket.flush
  end

  # ditto
  def send(*commands) : Nil
    send(commands)
  end

  # Wrap `#send` and `#receive` in one call.
  def command(*args, **nargs) : Value
    send(*args, **nargs)
    receive
  end

  # Read a response. Blocks until read. The response is cast to a Crystal type
  # according to the [Redis Protocol Specification](https://redis.io/topics/protocol).
  # For more information on types, see `Value`.
  #
  # In case of error (`-` byte), a `Error` is raised.
  #
  # There is an optional *skip_queue* argument, which is used in `Transaction` mode --
  # it skips `QUEUED` strings, which improves the performance.
  def receive(*, skip_queued = false) : Value
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
        @socket.skip("QUEUED\r\n".bytesize)
        return Value.new(nil)
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

  # Call `#pipeline(true, &block)`, yielding `Pipeline`.
  # Use this shortcut when you want to read the response.
  #
  # ```
  # redis.pipeline do |pipe|
  #   pipe.send("PING")
  # end
  # ```
  def pipeline(&block : Pipeline ->) : Array(Value)
    pipeline(true, &block).not_nil!
  end

  # Yield `Pipeline`, accumulate requests and then flush them all in one moment.
  # *read* argument defines whether to read the response or not
  # (improves performance, may be used in throw-away clients).
  #
  # See [Pipelining docs](https://redis.io/topics/pipelining).
  def pipeline(read : Bool, &block : Pipeline ->) : Array(Value)?
    pipe = Pipeline.new(self)
    yield(pipe)
    @socket.flush

    if read
      pipe.queued.times.reduce(Array(Value).new(pipe.queued)) do |ary|
        ary << receive
      end
    end
  end

  # Call `#transaction(true, &block)`, yielding `Transaction`.
  # Use this shortcut when you want to read the response.
  #
  # ```
  # redis.transaction do |tx|
  #   tx.send("SET foo bar")
  # end
  # ```
  def transaction(&block : Transaction ->) : Value
    transaction(true, &block).not_nil!
  end

  # Send `"MULTI"` command, `yield` `Transaction` and then send `"EXEC"` command.
  # *read* argument defines whether to read the response or not
  # (improves performance, may be used in throw-away clients).
  #
  # See [Transactions docs](https://redis.io/topics/transactions).
  def transaction(read : Bool, &block : Transaction ->) : Value?
    command("MULTI")

    tx = Transaction.new(self)
    yield(tx)

    if read
      tx.queued.times do
        receive(skip_queued: true)
      end
    end

    exec_response = command("EXEC")
    return exec_response if read
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
