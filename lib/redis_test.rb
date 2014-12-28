require "redis_test/version"

module RedisTest
  class << self
    def port
      (ENV['TEST_REDIS_PORT'] || 9736).to_i
    end

    def db_filename
      "redis-test-#{port}.rdb"
    end

    def cache_path
      "#{Rails.root}/tmp/cache/#{port}/"
    end

    def pids_path
      "#{Rails.root}/tmp/pids"
    end

    def pidfile
      "#{pids_path}/redis-test-#{port}.pid"
    end

    def log_path
      "#{Rails.root}/tmp/redis-server.log"
    end

    def start
      FileUtils.mkdir_p cache_path
      FileUtils.mkdir_p pids_path

      redis_options = {
        "daemonize"     => 'yes',
        "pidfile"       => pidfile,
        "port"          => port,
        "timeout"       => 300,
        "dbfilename"    => db_filename,
        "dir"           => cache_path,
        "databases"     => 16,
        "logfile"       => log_path,
        "loglevel"      => "verbose"
      }.map { |k, v| "#{k} #{v}" }.join('\n')
      `echo '#{redis_options}' | redis-server -`


      wait_time_remaining = 5
      begin
        socket = TCPSocket.open("localhost", port)
        socket.puts "flushall"
        success = true
      rescue Exception => e
        if wait_time_remaining > 0
          wait_time_remaining -= 0.1
          sleep 0.1
        else
          raise "Cannot start redis server in 5 seconds. Pinging server yield\n#{e.inspect}"
        end
      end while(!success)

      ENV['REDIS_URL'] = server_url
    end

    def stop
      %x{
        cat #{pidfile} | xargs kill -QUIT
        rm -f #{cache_path}#{db_filename}
      }
    end

    def server_url
      "redis://localhost:#{port}"
    end

    def configure(*options)
      options.flatten.each do |option|
        case option
        when :default
          Redis.current = Redis.new

        when :sidekiq
          Sidekiq.configure_server do |config|
            config.redis = { url: server_url, namespace: 'sidekiq' }
          end

          Sidekiq.configure_client do |config|
            config.redis = { url: server_url, namespace: 'sidekiq' }
          end

        when :ohm
          Ohm.redis = Redic.new(server_url)

        when :resque
          Resque.configure do |config|
            config.redis = "#{server_url}/resque"
          end

        else
          raise "Unable to configure #{option}"
        end
      end
    end

    def clear
      Redis.current.flushdb
    end
  end
end
