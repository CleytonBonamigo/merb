require "time" # httpdate
# ==== Public Merb Logger API
#
# To replace an existing logger with a new one:
#  Merb::Logger.set_log(log{String, IO},level{Symbol, String})
#
# Available logging levels are
#   Merb::Logger::{ Fatal, Error, Warn, Info, Debug }
#
# Logging via:
#   Merb.logger.fatal(message<String>,&block)
#   Merb.logger.error(message<String>,&block)
#   Merb.logger.warn(message<String>,&block)
#   Merb.logger.info(message<String>,&block)
#   Merb.logger.debug(message<String>,&block)
#
# Flush the buffer to 
#   Merb.logger.flush
#
# Remove the current log object
#   Merb.logger.close
# 
# ==== Private Merb Logger API
# 
# To initialize the logger you create a new object, proxies to set_log.
#   Merb::Logger.new(log{String, IO},level{Symbol, String})
module Merb

  class << self #:nodoc:
    attr_accessor :logger
  end

  class Logger

    attr_accessor :aio
    attr_accessor :level
    attr_accessor :delimiter
    attr_accessor :auto_flush
    attr_reader   :buffer
    attr_reader   :log

    # Note:
    #   Ruby (standard) logger levels:
    #     fatal: an unhandleable error that results in a program crash
    #     error: a handleable error condition
    #     warn:  a warning
    #     info:  generic (useful) information about system operation
    #     debug: low-level information for developers
    #
    #   Merb::Logger::Levels{ :fatal, :error, :warn, :info, :debug }
    Levels = 
    {
      :fatal => 7, 
      :error => 6, 
      :warn  => 4,
      :info  => 3,
      :debug => 0
    }

    private

    # Define the write method based on if aio an be used
    # ==== Parameters
    #   none
    #
    # Notes: The idea here is that instead of performing an 'if' conditional
    #        check on each logging we do it once when the log object is setup
    def set_write_method
      @log.instance_eval do

        # Determine if asynchronous IO can be used
        # ==== Parameters
        #   none
        def aio?
          @aio = !Merb.environment.to_s.match(/development|test/) && 
          !RUBY_PLATFORM.match(/java|mswin/) &&
          !(@log == STDOUT) &&
          @log.respond_to?(:write_nonblock)
        end

        undef write_method if defined? write_method #:nodoc:
        if aio?
          alias :write_method :write_nonblock
        else
          alias :write_method :write
        end
      end
    end

    def initialize_log(log)
      close if @log # be sure that we don't leave open files laying around.

      if log.respond_to?(:write)
        @log = log
      elsif File.exist?(log)
        @log = open(log, (File::WRONLY | File::APPEND))
        @log.sync = true
      else
        FileUtils.mkdir_p(File.dirname(log)) unless File.directory?(File.dirname(log))
        @log = open(log, (File::WRONLY | File::APPEND | File::CREAT))
        @log.sync = true
        @log.write("#{Time.now.httpdate} #{delimiter} info #{delimiter} Logfile created\n")
      end
      set_write_method
    end

    public

    # To initialize the logger you create a new object, proxies to set_log.
    #   Merb::Logger.new(log{String, IO},level{Symbol, String})
    #
    # ==== Parameters
    # log<IO,String>
    #   Either an IO object or a name of a logfile.
    # log_level<String>
    #   The string message to be logged
    # delimiter<String>
    #   Delimiter to use between message sections
    def initialize(*args)
      set_log(*args)
    end

    # To replace an existing logger with a new one:
    #  Merb::Logger.set_log(log{String, IO},level{Symbol, String})
    # 
    # ==== Parameters
    # log<IO,String>
    #   Either an IO object or a name of a logfile.
    # log_level<Symbol>
    #   A symbol representing the log level from {:fatal, :error, :warn, :info, :debug}
    # delimiter<String>
    #   Delimiter to use between message sections
    def set_log(log, log_level = nil, delimiter = " ~ ", auto_flush = false)
      if log_level && Levels[log_level.to_sym]
        @level = Levels[log_level.to_sym]
      elsif Merb.environment == "production"
        @level = Levels[:error]
      else
        @level = Levels[:debug]
      end
      @buffer     = []
      @delimiter  = delimiter
      @auto_flush = auto_flush

      initialize_log(log)

      Merb.logger = self
    end

    # Flush the entire buffer to the log object.
    #   Merb.logger.flush
    # ==== Parameters
    # none
    def flush
      return unless @buffer.size > 0
      @log.write_method(@buffer.slice!(0..-1).to_s)
    end

    # Close and remove the current log object.
    #   Merb.logger.close
    # ==== Parameters
    # none
    def close
      flush
      @log.close if @log.respond_to?(:close)
      @log = nil
    end

    # Appends a string and log level to logger's buffer. 
    # Note that the string is discarded if the string's log level less than the logger's log level. 
    # Note that if the logger is aio capable then the logger will use non-blocking asynchronous writes.
    #
    # ==== Parameters
    # level<Fixnum>
    #   The logging level as an integer
    # string<String>
    #   The string message to be logged
    # block<&block>
    #   An optional block that will be evaluated and added to the logging message after the string message.
    def <<(string = nil)
      message = ""
      message << delimiter
      message << string if string
      if block_given?
        message << delimiter
        message << yield
      end
      message << "\n" unless message[-1] == ?\n
      @buffer << message
      flush if @auto_flush

      message
    end
    alias :push :<<

    # Generate the following logging methods for Merb.logger as described in the api:
    #  :fatal, :error, :warn, :info, :debug 
    Levels.each_pair do |name, number|
      class_eval <<-LEVELMETHODS, __FILE__, __LINE__

      # DOC
      def #{name}(message = nil, &block)
        self.<<(message, &block) if #{number} >= level
      end

      # DOC
      def #{name}?
        #{number} >= level
      end
      LEVELMETHODS
    end

  end
  
end