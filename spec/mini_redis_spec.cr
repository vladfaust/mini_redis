require "./spec_helper"

describe MiniRedis do
  redis = MiniRedis.new(uri: URI.parse(ENV["REDIS_URL"]))

  describe "#command" do
    it do
      redis.command("SET", "foo", "bar".to_slice).raw.as(String).should eq "OK"
    end
  end

  describe "#send" do
    it do
      redis.send("GET foo")
    end
  end

  describe "#receive" do
    it do
      String.new(redis.receive.raw.as(Bytes)).should eq "bar"
    end
  end

  describe "pipeline" do
    it do
      response = redis.pipeline do |pipe|
        pipe.send("SET foo baz")
        pipe.send({"GET", "foo"})
      end

      response.should eq [MiniRedis::Value.new("OK"), MiniRedis::Value.new("baz".to_slice)]
    end
  end

  describe "transaction" do
    it do
      response = redis.transaction do |tx|
        tx.send("SET", "foo", "qux")
        tx.send("GET foo")
      end

      response.raw.should eq [MiniRedis::Value.new("OK"), MiniRedis::Value.new("qux".to_slice)]
    end
  end
end
