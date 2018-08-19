module Wrapbox
  module LogFetcher
    class Awslogs
      STOP_WAIT_TIMELIMIT = 10

      def initialize(log_group:, log_stream_prefix:, filter_pattern: nil, region: nil, access_key_id: nil, secret_access_key: nil, timestamp_format: "%Y-%m-%d %H:%M:%S.%3N", delay: 2, **options)
        begin
          require 'aws-sdk-cloudwatchlogs'
        rescue LoadError
          $stderr.puts "Require aws-sdk-cloudwatchlogs gem"
          exit 1
        end

        @log_group = log_group
        @log_stream_prefix = log_stream_prefix
        @filter_pattern = filter_pattern
        @region = region
        @access_key_id = access_key_id
        @secret_access_key = secret_access_key
        @timestamp_format = timestamp_format
        @options = options.reject { |_, v| v.nil? }
      end

      def run(task:)
        @loop_thread = Thread.start do
          main_loop(task)
        end
      end

      def stop
        @stop = true
        @loop_thread&.join(STOP_WAIT_TIMELIMIT)
      end

      def main_loop(task)
        options = {
          region: @region,
          access_key_id: @access_key_id,
          secret_access_key: @secret_access_key,
        }.compact
        client = Aws::CloudWatchLogs::Client.new(**options)

        task_id = task.task_arn.split("/").last
        log_stream_names = task.containers.map do |container|
          [@log_stream_prefix, container.name, task_id].join("/")
        end
        filter_log_opts = {
          log_group_name: @log_group,
          log_stream_names: log_stream_names,
          filter_pattern: @filter_pattern,
        }.compact
        filter_log_opts[:start_time] = ((Time.now.to_f - 60) * 1000).round
        until @stop do
          filter_log_opts[:next_token] = nil
          begin
            resp = client.filter_log_events(filter_log_opts)
            resp.events.each do |ev|
              display_message(ev)
            end
            filter_log_opts[:next_token] = resp.next_token
          end while filter_log_opts[:next_token]
          filter_log_opts[:start_time] = (Time.now.to_f * 1000).round
          sleep @delay
        end
      end

      def display_message(ev, output: $stdout)
        time = Time.at(ev.timestamp / 1000.0)
        output.puts("#{time.strftime(@timestamp_format)} #{ev.log_stream_name} #{ev.message}")
      end
    end
  end
end
