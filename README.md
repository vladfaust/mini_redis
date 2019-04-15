# MiniRedis

[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Build status](https://img.shields.io/travis/com/vladfaust/mini_redis/master.svg?style=flat-square)](https://travis-ci.com/vladfaust/mini_redis)
[![API Docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://github.vladfaust.com/mini_redis)
[![Releases](https://img.shields.io/github/release/vladfaust/mini_redis.svg?style=flat-square)](https://github.com/vladfaust/mini_redis/releases)
[![Awesome](https://awesome.re/badge-flat2.svg)](https://github.com/veelenga/awesome-crystal)
[![vladfaust.com](https://img.shields.io/badge/style-.com-lightgrey.svg?longCache=true&style=flat-square&label=vladfaust&colorB=0a83d8)](https://vladfaust.com)
[![Patrons count](https://img.shields.io/badge/dynamic/json.svg?label=patrons&url=https://www.patreon.com/api/user/11296360&query=$.included[0].attributes.patron_count&style=flat-square&colorB=red&maxAge=86400)](https://www.patreon.com/vladfaust)
[![Gitter chat](https://img.shields.io/badge/chat%20on-gitter-green.svg?colorB=ED1965&logo=gitter&style=flat-square)](https://gitter.im/vladfaust/Lobby)

A light-weight Redis client for [Crystal](https://crystal-lang.org/).

[![Become Patron](https://vladfaust.com/img/patreon-small.svg)](https://www.patreon.com/vladfaust)

## About

MiniRedis is a light-weight low-level alternative to existing Redis client implementations.

In comparison with [crystal-redis](https://github.com/stefanwille/crystal-redis), MiniRedis has lesser memory consumption, built-in logging and first-class support for raw bytes. It also doesn't need to be updated with every Redis release.

On the other hand, MiniRedis doesn't have commands API (i.e. instead of `redis.ping` you should write `redis.send("PING")`). However, such a low-level interface terminates the dependency on the third-party client maintainer (i.e. me), which makes it a perfect fit to use within a shard.

You can always find the actual Redis commands API at <https://redis.io/commands>.

### Benchmarks

Benchmarks code can be found at <https://github.com/vladfaust/mini_redis-benchmarks>.
These are recent results of comparison MiniRedis with [crystal-redis](https://github.com/stefanwille/crystal-redis).

#### `send` benchmarks

```sh
> env REDIS_URL=redis://localhost:6379/1 crystal src/send.cr --release
mini_redis     13.4k ( 74.62µs) (± 2.50%)   32 B/op        fastest
crystal-redis  13.36k ( 74.83µs) (± 2.97%)  144 B/op   1.00× slower
```

**Conclusion:** `mini_redis` is more memory-efficient.

#### Pipeline mode benchmarks

1 million pipelined `send`s, average from 30 times repeats:

```sh
> env REDIS_URL=redis://localhost:6379/1 crystal src/pipeline.cr --release
mini_redis    914.569ms 1.093M ops/s
crystal-redis 908.182ms 1.101M ops/s
```

**Conclusion:** `mini_redis` has almost the same speed as `crystal-redis`.

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  mini_redis:
    github: vladfaust/mini_redis
    version: ~> 0.2.0
```

2. Run `shards install`

This shard follows [Semantic Versioning v2.0.0](http://semver.org/), so check [releases](https://github.com/vladfaust/timer.cr/releases) and change the `version` accordingly. Note that until Crystal is officially released, this shard would be in beta state (`0.*.*`), with every **minor** release considered breaking. For example, `0.1.0` → `0.2.0` is breaking and `0.1.0` → `0.1.1` is not.

## Usage

```crystal
require "mini_redis"

redis = MiniRedis.new

# MiniRedis responses wrap `Int64 | String | Bytes | Nil | Array(Value)` values,
# which map to `Integer`, `Simple String`, `Bulk String`, `Nil` and `Array` Redis values

# SET command returns `Simple String`, which is `String` in Crystal
pp redis.send("SET", "foo", bar").raw.as(String) # => "OK"

# GET command returns `Bulk String`, which is `Bytes` in Crystal
bytes = redis.send("GET", "foo").raw.as(Bytes)
pp String.new(bytes) # => "bar"

# Bytes command payloads are also supported
redis.send("set", "foo".to_slice, "bar".to_slice)
```

### Pipelining

```crystal
response = redis.pipeline do |pipe|
  # WARNING: Accessing the `.send` return value
  # within the pipe block would crash the program!
  pipe.send("SET", "foo", "bar")
end

pp typeof(response) # => [MiniRedis::Value(@raw="OK")]
```

### Transactions

```crystal
response = redis.transaction do |tx|
  pp tx.send("SET", "foo", "bar").raw.as(String) # => "QUEUED"
end

pp typeof(response) # => MiniRedis::Value(@raw=[MiniRedis::Value(@raw="OK")])
```

### Connection pool

```crystal
pool = MiniRedis::Pool.new

response = pool.get do |redis|
  # Redis is MiniRedis instance, can do anything
  redis.send("PING")
end

# Return value equals to the block's
pp response.raw.as(String) # => "PONG"

conn = pool.get
pp conn.send("PING").raw.as(String) # => "PONG"
pool.release(conn) # Do not forget to put it back!
```

## Development

`env REDIS_URL=redis://localhost:6379 crystal spec` and you're good to go.

## Contributing

1. Fork it (<https://github.com/vladfaust/mini_redis/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'feat: new feature'`) using [angular-style commits](https://docs.onyxframework.org/contributing/commit-style)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Vlad Faust](https://github.com/vladfaust) - creator and maintainer
