#!/usr/bin/env ruby

require 'English'

classes = ["NoHostname","S25R"]

$sender = Struct.new("Sender", :to, :from, :host, :ipaddr)
$counted_sender = Struct.new("CountedSender", :to, :host, :ipaddr, :froms, :count)
$classified_result = Struct.new("ClassifiedResult", :classifier, :senders)

class MessageClassifier
  def self.label(label = nil)
    @label = label if label
    @label
  end
end

class NoHostnameMessageClassifier < MessageClassifier
  label "No hostname (DNS resolution failure)"

  # return true if 'sender' is classified into this class
  def self.classify(sender)
    sender.host =~ /^[\.0-9]+$/
  end
end

class OtherMessageClassifier < MessageClassifier
  label "Others"

  # return true if 'sender' is classified into this class
  def self.classify(sender)
    true
  end
end

class ClassifierRunner
  def self.run(classes, senders)
    classifiers = (classes + ["Other"]).map do |class_name|
      begin
        eval("#{class_name}MessageClassifier")
      rescue NameError
        OtherMessageClassifier
      end
    end.sort do |klass1, klass2|
      # move OtherMessageClassifier to the last
      if klass1 == OtherMessageClassifier
        1
      else
        -1
      end
    end.uniq

    classified_results = classifiers.map do |klass|
      $classified_result.new(klass, Array.new)
    end

    senders.each do |sender|
      classified = false
      classified_results.each do |result|
        if result.classifier.classify(sender)
          classified = true
          result.senders << sender
          break
        end
      end

      unless classified
        raise Error.new("Sender #{sender.inspect} not classified into any class")
      end
    end

    classified_results
  end
end

def sort_senders_by_dest(logfile)
  mailaddr_senders = Hash.new{Array.new}
  logfile.each_line do |line|
    next unless line =~ /^\w+ \d+ \d{2}:\d{2}:\d{2} \w+ milter-greylist:/
    
    next unless $POSTMATCH =~ /addr (\[[\.0-9]+\]|\S+)\[([\.0-9]+)\] from <?([^> ]+)>? to <?([^> ]+)>?/
    
    host = $~[1]
    ipaddr = $~[2]
    from = $~[3]
    to = $~[4]

    host.gsub!(/^\[([^\]]+)\]$/, "\\1")

    sender = $sender.new(to, from, host, ipaddr)
    mailaddr_senders[to] <<= sender
  end
  mailaddr_senders
end

def count_senders(senders)
  counted_senders = Hash.new
  senders.each do |sender|
    counted_sender = counted_senders[sender.host]
    unless counted_sender
      counted_sender = $counted_sender.new(sender.to, sender.host,
                                           sender.ipaddr, [], 0)
      counted_senders[sender.host] = counted_sender
    end
    
    counted_sender.count += 1
    counted_sender.froms << sender.from
  end

  counted_senders.each do |host,sender|
    sender.froms = sender.froms.sort.uniq
  end
  counted_senders.values.sort{|s1, s2| s2.count <=> s1.count}
end

if __FILE__ == $0
  sorted_senders = sort_senders_by_dest(ARGF)
  sorted_classified_senders = sorted_senders.map do |dest, senders|
    [dest, ClassifierRunner.run(classes, senders)]
  end

  sorted_classified_senders.each do |entry|
    dest = entry[0]
    classified_results = entry[1]

    puts "#{dest}:"
    
    classified_results.each do |result|
      klass = result.classifier
      senders = count_senders(result.senders)

      puts "  #{klass.label}:"
      
      senders.each do |sender|
        puts "    [#{sender.count}] #{sender.host} (#{sender.froms.join(", ")})"
      end
    end
  end
end
