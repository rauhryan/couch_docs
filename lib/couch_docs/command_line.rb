require 'optparse'
require 'pp'

require 'rubygems'
require 'directory_watcher'

module CouchDocs
  class CommandLine
    COMMANDS            = %w{push dump}
    DEPRECATED_COMMANDS = %w{load}

    def self.run(*args)
      CommandLine.new(*args).run
    end

    attr_reader :command, :options

    def initialize(args)
      parse_options(args)
    end

    def run
      case command
      when "dump"
        CouchDocs.dump(@options[:couchdb_url],
                       @options[:target_dir],
                       @options[:dump])
      when "push"
        if @options[:destructive]
          CouchDocs.destructive_database_create(options[:couchdb_url])
        end

        dw = DirectoryWatcher.new @options[:target_dir]
        dw.glob = '**/*'
        dw.interval = 2.0

        dw.add_observer do |*args|
          puts "Updating documents on CouchDB Server..."
          directory_watcher_update(args)
        end

        if @options[:watch]
          dw.start

          begin
            sleep 30 while active?
          rescue Interrupt
            dw.stop
            puts
          end
        else
          dw.run_once
        end
      when "load" # DEPRECATED
        CouchDocs.put_dir(@options[:target_dir],
                          @options[:couchdb_url])
      end
    end

    def parse_options(args)
      @options = { :target_dir => "." }

      options_parser = OptionParser.new do |opts|
        opts.banner = "Usage: couch-docs push|dump [OPTIONS] couchdb_url [target_dir]"

        opts.separator ""
        opts.separator "If a target_dir is not specified, the current working directory will be used."

        opts.separator ""
        opts.separator "Push options:"

        opts.on("-R", "--destructive",
                "Drop the couchdb_uri (if it exists) and create a new database") do
          @options[:destructive] = true
        end

        # TODO: bulk_docs in 1.2
        # opts.on("-b", "--bulk [BATCH_SIZE=1000]", Integer,
        #         "Use bulk insert when pushing new documents") do |batch_size|
        #   @options[:bulk] = true
        #   @options[:batch_size] = batch_size || 1000
        # end

        opts.on("-w", "--watch", "Watch the directory for changes, uploading when detected") do
          @options[:watch] = true
        end

        opts.separator ""
        opts.separator "Dump options:"

        opts.on("-d", "--design", "Only dump design documents") do
          @options[:dump] = :design
        end
        opts.on("-D", "--data", "Only dump data documents") do
          @options[:dump] = :doc
        end

        opts.separator ""
        opts.separator "Common options:"

        opts.on_tail("-v", "--version", "Show version") do
          puts File.basename($0) + " "  + CouchDocs::VERSION
          exit
        end

        # No argument, shows at tail.  This will print an options summary.
        # Try it and see!
        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      begin
        options_parser.parse!(args)
        additional_help = "#{options_parser.banner}\n\nTry --help for more options."
        unless (COMMANDS+DEPRECATED_COMMANDS).include? args.first
          puts "invalid command: \"#{args.first}\".  Must be one of #{COMMANDS.join(', ')}.\n\n"
          puts additional_help
          exit
        end
        @command = args.shift
        unless args.first
          puts "Missing required couchdb_uri argument.\n\n"
          puts additional_help
          exit
        end
        @options[:couchdb_url] = args.shift
        @options[:target_dir]  = args.shift if (args.size >= 1)

      rescue OptionParser::InvalidOption => e
        raise e
      end
    end

    def directory_watcher_update(args)
      if initial_add? args
        CouchDocs.put_dir(@options[:couchdb_url],
                          @options[:target_dir])
      else
        if design_doc_update? args
          CouchDocs.put_design_dir(@options[:couchdb_url],
                                   "#{@options[:target_dir]}/_design")
        end
        documents(args).each do |update|
          CouchDocs.put_file(@options[:couchdb_url],
                             update.path)
        end
      end
    rescue RestClient::ResourceNotFound => e
      $stderr.puts "\n"
      $stderr.puts e.message
      $stderr.puts "Does the database exist? Try using the -R option."
      $stderr.puts "\n"
    rescue Exception => e
      $stderr.puts "\n"
      $stderr.puts e.message
      $stderr.puts e.backtrace
    end

    def initial_add?(args)
      args.all? { |f| f.type == :added }
    end

    def design_doc_update?(args)
      args.any? { |f| f.path =~ /_design/ }
    end

    def documents(args)
      args.reject { |f| f.path =~ /_design/ }
    end

    private
    def active?; true end
  end
end
