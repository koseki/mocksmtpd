$:.unshift File.dirname(__FILE__) # for test/development

require 'optparse'
require 'pathname'
require 'yaml'
require 'erb'
require 'nkf'
require 'smtpserver'

class Mocksmtpd
  VERSION = '0.0.3'
  TEMPLATE_DIR = Pathname.new(File.dirname(__FILE__)) + "../templates"

  include ERB::Util

  def initialize(argv)
    @opt = OptionParser.new
    @opt.banner = "Usage: #$0 [options] [start|stop|init PATH]"
    @opt.on("-f FILE", "--config=FILE", "Specify mocksmtpd.conf") do |v|
      @conf_file = v
    end

    @opt.on("--version", "Show version string `#{VERSION}'") do
      puts VERSION
      exit
    end

    @opt.parse!(argv)

    if argv.empty?
      @command = "console"
    else
      @command = argv.shift
      commands = %w(start stop init)
      unless commands.include? @command
        opterror "No such command: #{@command}"
        exit 1
      end
    end

    if @command == "init"
      @init_dir = argv.shift || "mocksmtpd"
      if test(?e, @init_dir)
        opterror("Init path already exists: #{@init_dir}")
        exit 1
      end
    end
  end

  def opterror(msg)
    puts("Error: #{msg}")
    puts(@opt.help)
  end

  def load_conf
    @conf_file = Pathname.new(@conf_file || "./mocksmtpd.conf")
    unless @conf_file.exist? && @conf_file.readable?
      opterror "Can't load config file: #{@conf_file}"
      exit 1
    end
    @conf_file = @conf_file.realpath

    @conf = {}
    YAML.load_file(@conf_file).each do |k,v|
      @conf[k.intern] = v
    end

    @inbox = resolve_conf_path(@conf[:InboxDir])
    @logfile = resolve_conf_path(@conf[:LogFile])
    @pidfile = resolve_conf_path(@conf[:PidFile])

    @templates = load_templates
  end

  def resolve_conf_path(path)
    result = nil
    if path[0] == ?/
      result = Pathname.new(path)
    else
      result = @conf_file.parent + path
    end
    return result.cleanpath
  end

  def run
    send(@command)
  end

  def load_templates
    result = {}
    result[:mail] = template("html/mail")
    result[:index] = template("html/index")
    result[:index_entry] = template("html/index_entry")
    return result
  end

  def template(name)
    path = TEMPLATE_DIR + "#{name}.erb"
    src = path.read
    return ERB.new(src, nil, "%-")
  end

  def init
    Dir.mkdir(@init_dir)
    puts "Created: #{@init_dir}/"
    path = Pathname.new(@init_dir)
    Dir.mkdir(path + "inbox")
    puts "Created: #{path + 'inbox'}/"
    Dir.mkdir(path + "log")
    puts "Created: #{path + 'log'}/"

    open(path + "mocksmtpd.conf", "w") do |io|
      io << template("mocksmtpd.conf").result(binding)
    end
    puts "Created: #{path + 'mocksmtpd.conf'}"
  end

  def stop
    load_conf
    unless @pidfile.exist?
      puts "ERROR: pid file does not exist: #{@pidfile}"
      exit 1
    end
    unless @pidfile.readable?
      puts "ERROR: Can't read pid file: #{@pidfile}"
      exit 1
    end

    pid = File.read(@pidfile)
    print "Stopping #{pid}..."
    system "kill -TERM #{pid}"
    puts "done"
  end

  def create_logger(file = nil)
    file = file.to_s.strip
    file = nil if file.empty?
    lvstr = @conf[:LogLevel].to_s.strip
    lvstr = "INFO" unless %w{FATAL ERROR WARN INFO DEBUG}.include?(lvstr)
    level = WEBrick::BasicLog.const_get(lvstr)
    logger = WEBrick::Log.new(file, level)
    logger.debug("Logger initialized")
    return logger
  end

  def start
    load_conf
    @logger = create_logger(@logfile)
    @daemon = true
    smtpd
  end

  def console
    load_conf
    @logger = create_logger
    @daemon = false
    smtpd
  end

  def create_pid_file
    if @pidfile.exist?
      pid = @pidfile.read
      @logger.warn("pid file already exists: pid=#{pid}")
      exit 1
    end
    pid = Process.pid
    open(@pidfile, "w") do |io|
      io << pid
    end
    @logger.debug("pid file saved: pid=#{pid} file=#{@pidfile}")
  end

  def delete_pid_file
    File.delete(@pidfile)
    @logger.debug("pid file deleted: file=#{@pidfile}")
  end

  def init_permission
    File.umask(@conf[:Umask]) unless @conf[:Umask].nil?
    stat = File::Stat.new(@conf_file)
    uid = stat.uid
    gid = stat.gid
    begin
      Process.egid = gid
      Process.euid = uid
    rescue NotImplementedError => e
      @logger.debug("Process.euid= not implemented.")
    rescue Errno::EPERM => e
      @logger.warn("could not change euid/egid. #{e}")
    end
  end

  def smtpd
    start_cb = Proc.new do
      @logger.info("Inbox: #{@inbox}")
      if @daemon
        @logger.debug("LogFile: #{@logfile}")
        @logger.debug("PidFile: #{@pidfile}")
      end

      begin
        init_permission
        create_pid_file if @daemon
      rescue => e
        @logger.error("Start: #{e}")
        raise e
      end
    end

    stop_cb = Proc.new do
      begin
        delete_pid_file if @daemon
      rescue => e
        @logger.error("Stop: #{e}")
        raise e
      end
    end

    data_cb = Proc.new do |src, sender, recipients|
      recieve_mail(src, sender, recipients)
    end

    @conf[:ServerType] = @daemon ? WEBrick::Daemon : nil
    @conf[:Logger] = @logger
    @conf[:StartCallback] = start_cb
    @conf[:StopCallback] = stop_cb
    @conf[:DataHook] = data_cb

    server = SMTPServer.new(@conf)

    [:INT, :TERM].each do |signal|
      Signal.trap(signal) { server.shutdown }
    end

    server.start
  end

  def recieve_mail(src, sender, recipients)
    @logger.info "mail recieved from #{sender}"

    mail = parse_mail(src, sender, recipients)

    save_mail(mail)
    save_index(mail)
  end

  def parse_mail(src, sender, recipients)
    src = NKF.nkf("-wm", src)
    subject = src.match(/^Subject:\s*(.+)/i).to_a[1].to_s.strip
    date = src.match(/^Date:\s*(.+)/i).to_a[1].to_s.strip

    src = ERB::Util.h(src)
    src = src.gsub(%r{https?://[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+},'<a href="\0">\0</a>')
    src = src.gsub(/(?:\r\n|\r|\n)/, "<br />\n")
  
    if date.empty?
      date = Time.now
    else
      date = Time.parse(date)
    end
  
    mail = {
      :source => src,
      :sender => sender,
      :recipients => recipients,
      :subject => subject,
      :date => date,
    }

    format = "%Y%m%d%H%M%S"
    fname = date.strftime(format) + ".html"
    while @inbox.join(fname).exist?
      date += 1
      fname = date.strftime(format) + ".html"
    end

    mail[:file] = fname
    mail[:path] = @inbox.join(fname)

    return mail
  end

  def save_mail(mail)
    open(mail[:path], "w") do |io|
      io << @templates[:mail].result(binding)
    end
    @logger.debug("mail saved: #{mail[:path]}")
  end

  def save_index(mail)
    path = @inbox + "index.html"
    unless File.exist?(path)
      open(path, "w") do |io|
        io << @templates[:index].result(binding)
      end
    end

    htmlsrc = File.read(path)
    add = @templates[:index_entry].result(binding)

    htmlsrc.sub!(/<!-- ADD -->/, add)
    open(path, "w") do |io|
      io << htmlsrc
    end
    @logger.debug("index saved: #{path}")
  end

end
