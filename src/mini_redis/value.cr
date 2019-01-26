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
  # response = String.new(redis.command("GET foo").raw.as(Bytes))
  # pp response # => "bar"
  # ```
  struct Value
    getter raw

    def initialize(@raw : Int64 | String | Bytes | Nil | Array(Value))
    end
  end
end
