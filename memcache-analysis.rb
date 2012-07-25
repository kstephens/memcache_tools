#!/usr/bin/env ruby

require 'rubygems'
gem 'pry'
require 'pry'

require 'time'
$:.unshift(File.expand_path('lib'))
require 'marshal_stats'

#######################################
module TrickSerial
  class Serializer
    class ActiveRecordProxy
      def __klass_id
        "#{self.class}(#{@cls})" # @id
      end
    end
  end
end

module ActiveRecord
  module Reflection
    class AssociationReflection
      def __klass_id
        #"#{self.class}(#{instance_variables.inspect})"
        # "#{self.class}(#{@klass}, #{@name}, #{@primary_key_name}, #{@active_record})"
        "#{self.class}(#{@class_name}, #{@name})"
      end
      alias :to_s :__klass_id
    end
  end
  module Associations
    class BelongsToAssociation
      def __klass_id
        "#{self.class}(#{@reflection})"
      end
    end
  end
end

#######################################

=begin
[
  nil,
  true,
  false,
  123,
  1234.123,
].each do | x |
  m = Marshal.dump(x)
  puts "  x = #{x.inspect}\n  => m = #{m.inspect}"
  MarshalParse.new(m).parse_top_level!
end
exit 0
=end

class MemcacheAnalysis
  attr_accessor :h, :ch

  ADD = 'add'.freeze

  def parse_cmd
    l = readline
    cmd, *args = l.split(/\s+/)
    case cmd
    when ADD
      key, what, atime, size = args
      what = what.to_i
      atime = atime.to_i
      atime = Time.at(atime).utc
      size = size.to_i

      data = read(size)
      readline

      @count += 1
      cmd = {
        :key => key,
        :size => size,
        :atime => atime,
      }

      h.add! :item_size, size
      begin
        ms = MarshalStats.new(data)
        ch = Histogram.new
        ch.chain = @ch
        ms.ch = ch
        ms.parse_top_level!
      rescue Exception => exc
        cmd[:error] = [ exc.class.name, exc.inspect, exc.backtrace ]
      end

      begin
        o = $stderr
        o.puts "#{cmd[:key]}:"
        o.puts "  :size:  #{cmd[:size]}"
        o.puts "  :atime: #{cmd[:atime].iso8601}"
        o.puts "  :stats:"
        ch.put o
        o.puts "  :error: #{cmd[:error].inspect}"
        o.puts "\n"
      end

      if @count % 100 == 0
        # binding.pry
      end
    else
      $stderr.puts "   Unexpected cmd: #{l.inspect}"
    end
  end

  def readline
    @lines += 1
    @in.readline
  end

  def read size
    @in.read size
  end

  def initialize
    @lines = 0
    @count = 0
    @h = Histogram.new
    @ch = Histogram.new
  end

  def parse! file
    File.open(file) do | i |
      @in = i
      until i.eof?
        parse_cmd
      end
    end
    binding.pry
    self
  end

  def run!
    parse!(ARGV.first || "memcache-contents.txt")
  end

end

MemcacheAnalysis.new.run!

