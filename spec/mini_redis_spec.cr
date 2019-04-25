require "./spec_helper"

describe MiniRedis do
  redis = MiniRedis.new(uri: URI.parse(ENV["REDIS_URL"]), logger: Logger.new(STDOUT))

  describe "#send" do
    it do
      redis.send("PING").raw.as(String).should eq "PONG"
      redis.send("SET", "foo", "bar".to_slice).raw.as(String).should eq "OK"
    end

    describe "with compound args" do
      it do
        slice = Bytes[1, 2, 3]
        redis.send("SET", {"foo", slice, 42}, "bar").raw.as(String).should eq "OK"
        String.new(redis.send("GET", "foo\x01\x02\x0342").raw.as(Bytes)).should eq "bar"
      end

      describe "with negative numbers" do
        it do
          redis.send("SET", {"foo", -40}, "bar").raw.as(String).should eq "OK"
          String.new(redis.send("GET", "foo-40").raw.as(Bytes)).should eq "bar"
        end
      end

      describe "with zeros" do
        it do
          redis.send("SET", {"foo", 0}, "bar").raw.as(String).should eq "OK"
          String.new(redis.send("GET", "foo0").raw.as(Bytes)).should eq "bar"
        end
      end
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
