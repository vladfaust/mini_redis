require "../spec_helper"

describe MiniRedis::Pool do
  pool = MiniRedis::Pool.new(uri: URI.parse(ENV["REDIS_URL"]))

  it do
    channel = Channel(MiniRedis::Value).new(5)

    5.times do
      spawn do
        channel.send(pool.get do |redis|
          redis.send("PING")
        end)
      end
    end

    until channel.full?
      sleep(0.01)
    end

    channel.receive.should eq channel.receive
    pool.size.should eq 5
  end
end
