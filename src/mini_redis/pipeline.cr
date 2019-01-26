class MiniRedis
  # A client in pipeline mode. See [Pipelining docs](https://redis.io/topics/pipelining).
  #
  # ```
  # response = redis.pipeline do |pipe|
  #   pipe.send("PING")
  # end
  # pp response # => Array(MiniRedis::Value)
  # ```
  class Pipeline
    # The current number of commands queued for this pipeline.
    getter queued : Int32 = 0

    def initialize(@redis : MiniRedis)
    end

    # See `MiniRedis#send`.
    def send(command : String) : Nil
      @redis.socket << command << "\r\n"
      @queued += 1
    end

    # ditto
    def send(commands : Enumerable) : Nil
      @redis.marshal(commands, @redis.socket)
      @queued += 1
    end

    # ditto
    def send(*commands) : Nil
      send(commands)
    end
  end
end
