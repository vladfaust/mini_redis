class MiniRedis
  # A Redis value. It's `#raw` value has a type according to [Redis Protocol Specification](https://redis.io/topics/protocol):
  #
  # ```
  # # Redis type    | First byte | Crystal type |
  # # ------------- | ---------- | ------------ |
  # # Simple String | `+`        | `String`     |
  # # Integer       | `:`        | `Int64`      |
  # # Bulk String   | `$`        | `Bytes`      |
  # # Array         | `*`        | `Array`      |
  # ```
  #
  # ```
  # response = redis.transaction do |tx|
  #   pp tx.send("SET foo bar") # => MiniRedis::Value(@raw="QUEUED")
  # end
  #
  # response = String.new(response.raw.as(Array).first.raw.as(Bytes))
  # pp response # => "bar"
  #
  # response = redis.send("GET foo")
  # response = String.new(response.raw.as(Bytes))
  # pp response # => "bar"
  # ```
  #
  # Reminder — do not try to directly print a `MiniRedis#send` response when in
  # pipeline mode! See `MiniRedis#pipeline` docs.
  struct Value
    getter raw

    def initialize(@raw : Int64 | String | Bytes | Nil | Array(Value))
    end
  end
end
