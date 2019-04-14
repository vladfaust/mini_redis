class MiniRedis
  # A `MiniRedis` connection pool. It has dynamic `#capacity` and `#block` values.
  class Pool
    # Initialize a new pool with `#block` initializing a
    # `MiniRedis` client from the *uri*.
    def self.new(
      uri : URI = URI.parse("redis://localhost:6379"),
      capacity : Int32 = Int32::MAX,
      initial_size : Int32 = 0,
      dns_timeout : Time::Span? = 5.seconds,
      connect_timeout : Time::Span? = 5.seconds,
      read_timeout : Time::Span? = nil,
      write_timeout : Time::Span? = 5.seconds
    )
      new(capacity, initial_size) do
        MiniRedis.new(
          uri: uri,
          dns_timeout: dns_timeout,
          connect_timeout: connect_timeout,
          read_timeout: read_timeout,
          write_timeout: write_timeout,
        )
      end
    end

    # The pool's capacity. Can be changed after the pool is initialized.
    property capacity : Int32

    # The pool's block to call to initialize a new `MiniRedis` instance.
    # Can be changed after the pool is initialized.
    property block : Proc(MiniRedis)

    # The number of free clients in this pool.
    def free
      @free.size
    end

    # The number of clients in this pool currently being used.
    def used
      @used.size
    end

    # The total size of this pool (`#free` plus `#used`).
    def size
      free + used
    end

    @free = Deque(MiniRedis).new
    @used = Set(MiniRedis).new

    def initialize(@capacity : Int32 = Int32::MAX, initial_size : Int32 = 0, &@block : -> MiniRedis)
      initial_size.times do
        @free.push(@block.call)
      end
    end

    # Yield a free `MiniRedis` client.
    # Blocks until one is available, raises `TimeoutError` on optional *timeout*.
    # Calls `#release` after yield.
    def get(timeout : Time::Span? = nil, &block : MiniRedis ->)
      redis = get(timeout)
      result = yield(redis)
      result
    ensure
      release(redis) if redis
    end

    # Return a free `MiniRedis` client.
    # Blocks until one is available, raises `TimeoutError` on optional *timeout*.
    #
    # NOTE: Do not forget to `#release` the client afterwards!
    def get(timeout : Time::Span? = nil) : MiniRedis
      if redis = @free.shift?
        return redis
      else
        if @capacity.nil? || @used.size < @capacity.not_nil!
          redis = @block.call
          @used.add(redis)
          return redis
        else
          if timeout! = timeout
            started_at = Time.monotonic

            loop do
              sleep(0.01)

              if redis = @free.shift?
                return redis
              elsif Time.monotonic - started_at >= timeout!
                raise TimeoutError.new
              end
            end
          else
            loop do
              sleep(0.01)

              if redis = @free.shift?
                return redis
              end
            end
          end
        end
      end
    end

    # Put the *redis* client back into the pool.
    def release(redis : MiniRedis) : Nil
      @used.delete(redis)
      @free.push(redis)
    end

    # Could be raised when a *timeout* argument is provided upon `#get` call.
    class TimeoutError < Exception
    end
  end
end
