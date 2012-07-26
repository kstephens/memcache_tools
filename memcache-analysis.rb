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
      attr_accessor :macro, :class_name, :klass, :name
      def __klass_id
        #"#{self.class}(#{instance_variables.inspect})"
        # "#{self.class}(#{@klass}, #{@name}, #{@primary_key_name}, #{@active_record})"
        @__klass_id ||=
          "#{self.class}(#{@class_name || @klass.__klass_id}, #{@name})"
      end
      alias :to_s :__klass_id
    end
  end

  module Associations
    class Base
      def __klass_id
        #"#{self.class}(#{@owner && @owner.__klass_id}, #{@reflection})" #<< instance_variables.inspect
        unless Reflection::AssociationReflection === @reflection
          $stderr.puts "\n  #### Broken reflection in #{self.class}\n   association = #{inspect}\n  @reflection = #{@reflection.class} #{@reflection.inspect}"
          x = Reflection::AssociationReflection.new
          x.name = @reflection
          x.macro = :_MACRO
          x.class_name = :_CLASS
          @reflection = x
        end
        @__klass_id ||=
          "#{@owner && @owner.__klass_id}.#{@reflection.macro} :#{@reflection.name}, :class => #{@reflection.class_name || @reflection.klass.__klass_id} (#{self.class})"
      end
    end
    class BelongsToAssociation < Base
    end
    class HasAndBelongsToManyAssociation < Base
    end
    class HasManyAssociation < Base
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
      key, x, y, size = args
      x = x.to_i
      y = y.to_i
      # atime = Time.at(x).utc
      size = size.to_i

      $stderr.write "#{size}."

      data = read(size)
      readline

      @count += 1
      cmd = {
        :key => key,
        :size => size,
        :x => x,
        :y => y,
        #:atime => atime,
      }

      h.add! :item_size, size

      ch = MarshalStats::Stats.new
      begin
        ms = MarshalStats.new(data)
        # ch.chain = @ch
        ms.ch = ch
        ms.parse_top_level!
      rescue Interrupt, SystemExit
        raise
      rescue Exception => exc
        cmd[:error] = [ exc.class.name, exc.inspect, exc.backtrace ]
      end

      begin
        o = $stdout
        o.puts "#{cmd[:key]}:"
        o.puts "  :size: #{cmd[:size]}"
        o.puts "  :x:    #{cmd[:x]}"
        o.puts "  :y:    #{cmd[:y]}"
        # o.puts "  :atime: #{cmd[:atime].iso8601}"
        o.puts "  :stats:"
        ch.put o
        o.puts "  :error: #{cmd[:error].inspect}"
        ms.state.unique_string.to_a.sort_by{|a| - a[1]}.each do | s, v |
          o.puts "  # #{v} #{s.inspect}"
        end
        o.puts "\n"
      end

      if @pry_on_error and cmd[:error]
        binding.pry
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
    @h = MarshalStats::Stats.new
    @ch = MarshalStats::Stats.new
    @pry_on_error = (ENV['PRY_ON_ERROR'] || 0).to_i > 0
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

