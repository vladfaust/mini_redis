require "../spec_helper"

describe MiniRedis::Pool do
  pool = MiniRedis::Pool.new(URI.parse(ENV["REDIS_URL"]), logger: Logger.new(STDOUT))

  it do
    channel = Channel(MiniRedis::Value).new(2)

    2.times do
      spawn do
        channel.send(pool.get do |redis|
          redis.send("PING", 1)
        end)
      end
    end

    until channel.full?
      sleep(0.01)
    end

    channel.receive.should eq channel.receive
    pool.size.should eq 2
  end
end
