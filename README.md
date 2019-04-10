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

In comparison with [crystal-redis](https://github.com/stefanwille/crystal-redis), MiniRedis is slightly faster, has first-class support for raw bytes and doesn't need to be updated with every Redis release. On the other hand, MiniRedis doesn't have commands API (i.e. instead of `redis.ping` you should write `redis.send("PING")`). However, such a low-level interface terminates the dependency on the third-party client maintainer (i.e. me), which makes it a perfect fit to use within a shard.

### Benchmarks

Benchmarks code can be found at <https://github.com/vladfaust/mini_redis-benchmarks>.
These are recent results of comparison MiniRedis with [crystal-redis](https://github.com/stefanwille/crystal-redis).

#### `send` benchmarks

```sh
> env REDIS_URL=redis://localhost:6379/1 crystal src/send.cr --release
Begin benchmarking...
    mini_redis inline  13.23k ( 75.61µs) (± 2.19%)   32 B/op   1.02× slower
mini_redis marshalled  13.51k ( 74.04µs) (± 2.54%)   32 B/op        fastest
     redis marshalled  13.14k (  76.1µs) (± 2.76%)  368 B/op   1.03× slower
```

As we can see, MiniRedis is **much** more memory-efficient.

#### Pipeline mode benchmarks

1 million pipelined `send`s, average from 30 times repeats:

```sh
> env REDIS_URL=redis://localhost:6379/1 crystal src/pipeline.cr --release
MiniRedis (inline: t):  1.734s    0.577M ops/s
MiniRedis (inline: f):  898.669ms 1.113M ops/s
Redis                :  1.465s    0.683M ops/s
```

MiniRedis is almost **twice** as fast as crystal-redis in pipeline mode!

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  mini_redis:
    github: vladfaust/mini_redis
    version: ~> 0.2.0
```

2. Run `shards install`

## Usage

```crystal
require "mini_redis"

redis = MiniRedis.new

# Inline (i.e. one-line) commands allow to have simpler syntax but usually slower
pp redis.send("GET foo").raw # => nil

# MiniRedis responses wrap `Int64 | String | Bytes | Nil | Array(Value)` values, which are
# properly mapped to `integer`, `simple string`, `bulk string`, `nil` and `array` Redis values
pp redis.send("SET foo bar").raw.as(String) # => "OK"
bytes = redis.send("GET foo").raw.as(Bytes)
pp String.new(bytes) # => "bar"

# It is possible to declare commands as enumerables (or pass as many arguments),
# so they are going to be marshalled according to the Redis protocol.
# It is particulary useful for commands with binary payloads and usually faster
redis.send({"set", "foo", "bar"})
redis.send("set", "foo", "bar".to_slice)

# Pipelining
#

response = redis.pipeline do |pipe|
  pipe.send("SET foo bar")
end

pp typeof(response) # => [MiniRedis::Value(@raw="OK")]

# Transactions
#

response = redis.transaction do |tx|
  tx.send("SET foo bar")
end

pp typeof(response) # => MiniRedis::Value(@raw=[MiniRedis::Value(@raw="OK")])

# Connection pool
#

pool = MiniRedis::Pool.new

response = pool.get do |redis|
  redis.send({"PING"})
end

conn = pool.get
conn.send("PING")
pool.release(conn)
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
