class MiniRedis
  # A error which is raised in case when a error is read from Redis response.
  class Error < Exception
  end

  # A error which is raised when something's wrong with Redis connection.
  class ConnectionError < Exception
  end
end
