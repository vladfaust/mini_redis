class MiniRedis
  # A client in transaction mode. See [Transactions docs](https://redis.io/topics/transactions).
  #
  # ```
  # response = redis.transaction do |tx|
  #   tx.send("SET foo bar")
  #   tx.get("GET foo")
  # end
  # pp response # => MiniRedis::Value(@raw=Array(MiniRedis::Value))
  # ```
  class Transaction
    # The current number of commands queued for this transaction.
    getter queued : Int32 = 0

    def initialize(@redis : MiniRedis)
    end

    # See `MiniRedis#send`.
    def send(*args, **nargs) : Nil
      @redis.send(*args, **nargs)
      @queued += 1
    end
  end
end
