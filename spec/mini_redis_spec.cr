require "./spec_helper"

describe MiniRedis do
  redis = MiniRedis.new(uri: URI.parse(ENV["REDIS_URL"]), logger: Logger.new(STDOUT))

  describe "#send" do
    it do
      redis.send("PING").raw.as(String).should eq "PONG"
      redis.send("SET", "foo", "bar".to_slice).raw.as(String).should eq "OK"
    end
  end

  describe "#pipeline" do
    it do
      response = redis.pipeline do |pipe|
        pipe.send("SET", "foo", "baz")
        pipe.send({"GET", "foo"})
      end

      response.should eq [MiniRedis::Value.new("OK"), MiniRedis::Value.new("baz".to_slice)]
    end
  end

  describe "#transaction" do
    it do
      response = redis.transaction do |tx|
        tx.send("SET", "foo", "qux".to_slice)
        tx.send("GET", "foo")
      end

      response.raw.should eq [MiniRedis::Value.new("OK"), MiniRedis::Value.new("qux".to_slice)]
    end
  end
end
