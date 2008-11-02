#! /usr/bin/env ruby

DIR = File.expand_path(File.dirname(__FILE__))
$:.unshift(DIR)

require 'smtpserver'
require 'erb'
require 'nkf'
include ERB::Util

logfile = "#{DIR}/log/mocksmtpd.log"
pidfile = "#{DIR}/log/mocksmtpd.pid"
inbox = "#{DIR}/inbox"

euid,egid,umask = nil,nil,nil
# euid = File::Stat.new(__FILE__).uid
# egid = File::Stat.new(__FILE__).gid
# umask = 2

config = {
  :Port => 25,
  :ServerName => 'mocksmtpd',
  :RequestTimeout => 120,
  :LineLengthLimit => 1024,
}

if ARGV.include? "-d"
  daemon = true
end

if ARGV.include? "stop"
  pid = File.read(pidfile)
  system "kill -TERM #{pid}"
  exit
end

logger = daemon ? WEBrick::Log.new(logfile, WEBrick::BasicLog::INFO) : WEBrick::Log.new 

start_cb = Proc.new do
  File.umask(umask) unless umask.nil?
  Process.egid = egid unless egid.nil?
  Process.euid = euid unless euid.nil?

  if daemon
    if File.exist?(pidfile)
      pid = File.read(pidfile)
      logger.warn("pid file already exists: #{pid}")
      exit
    end
    open(pidfile, "w") do |io|
      io << Process.pid
    end
  end
end

stop_cb = Proc.new do
  File.delete(pidfile) if daemon
end

config[:ServerType] = daemon ? WEBrick::Daemon : nil
config[:Logger] = logger
config[:StartCallback] = start_cb
config[:StopCallback] = stop_cb

eval DATA.read

def save_entry(mail)
  open(mail[:path], "w") do |io|
    io << ERB.new(ENTRY_ERB, nil, "%-").result(binding)
  end
end

def save_index(mail, path)
  unless File.exist?(path)
    open(path, "w") do |io|
      io << INDEX_SRC
    end
  end

  htmlsrc = File.read(path)
  add = ERB.new(INDEX_ITEM_ERB, nil, "%-").result(binding)

  htmlsrc.sub!(/<!-- ADD -->/, add)
  open(path, "w") do |io|
    io << htmlsrc
  end
end


config[:DataHook] = Proc.new do |src, sender, recipients|
  logger.info "mail recieved from #{sender}"

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
  while File.exist?(inbox + "/" + fname)
    date += 1
    fname = date.strftime(format) + ".html"
  end

  mail[:file] = fname
  mail[:path] = inbox + "/" + fname

  save_entry(mail)
  save_index(mail, inbox + "/index.html")
end

server = SMTPServer.new(config)

[:INT, :TERM].each do |signal|
  Signal.trap(signal) { server.shutdown }
end

server.start

__END__

ENTRY_ERB = <<'EOT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja-JP" lang="ja-JP">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link rel="index" href="./index.html" />
<title><%=h mail[:subject] %> (<%= mail[:date].to_s %>)</title>
</head>
<body style="background:#eee">
<h1 id="subject"><%=h mail[:subject] %></h1>
<div><p id="date" style="font-size:0.8em;"><%= mail[:date].to_s %></div>
<div id="source" style="border: solid 1px #666; background:white; padding:2em;">
<p><%= mail[:source] %></p>
</div>
</body>
</html>
EOT

INDEX_SRC = <<'EOT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja-JP" lang="ja-JP">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link rel="index" href="./index.html" />
<title>Inbox</title>
<style type="text/css">
body {
  background:#eee;
}
table {
  border: 1px #999 solid;
  border-collapse: collapse;
}
th, td {
  border: 1px #999 solid;
  padding: 6px 12px;
}
th {
  background: #ccc;
}
td {
  background: white;  
}
</style>
</head>
<body>
<h1>Inbox</h1>
<table>
<thead>
<tr>
<th>Date</th>
<th>Subject</th>
<th>From</th>
<th>To</th>
</tr>
</thead>

<tbody>
<!-- ADD -->

</tbody>
</table>
</body>
</html>
EOT

INDEX_ITEM_ERB = <<'EOT'
<!-- ADD -->

<tr>
<td><%= mail[:date].strftime("%Y-%m-%d %H:%M:%S") %></td>
<td><a href="<%=h mail[:file] %>"><%=h mail[:subject] %></a></td>
<td><%=h mail[:sender] %></td>
<td><%=h mail[:recipients].to_a.join(",") %></td>
</tr>
EOT
