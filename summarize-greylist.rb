#!/usr/bin/env ruby

require 'English'

classes = ["NoHostname"]

class MessageClassifier

end

class NoHostnameMessageClassifier < MessageClassifier

end

class ClassifierRunner

end

$sender = Struct.new("Sender", :from, :host, :ipaddr)

$c = 0

def sort_by_mailaddr(logfile)
  mailaddr_senders = Hash.new{Array.new}
  logfile.each_line do |line|
    next unless line =~ /^\w+ \d+ \d{2}:\d{2}:\d{2} \w+ milter-greylist:/
    
    next unless $POSTMATCH =~ /addr (\[[\.0-9]+\]|\S+)\[([\.0-9]+)\] from <?([^>]+)>? to <?([^>]+)>?/
    
    host = $~[1]
    ipaddr = $~[2]
    from = $~[3]
    to = $~[4]

    host.gsub!(/^\[([^\]]+)\]$/, "\\1")

    sender = $sender.new(from, host, ipaddr)
    mailaddr_senders[to] <<= sender
    
    $c += 1
  end
  mailaddr_senders
end

if __FILE__ == $0
  sort_by_mailaddr(ARGF).each do |mailaddr, senders|
    puts "#{mailaddr}:"
    senders.each do |sender|
      puts "  #{sender.from}(#{sender.host})"
    end
  end
  puts $c
end
