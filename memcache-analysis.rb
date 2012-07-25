#!/usr/bin/env ruby

require 'rubygems'
gem 'pry'
require 'pry'


$:.unshift(File.expand_path('~/local/src/rubinius/kernel')

require 'common/marshal'
require 'common/marshal18'

class MarshalParse
  CODE_TO_SEL = { }
  attr_accessor :s, :parsed

  def initialize s = nil
    @s = StringIO.new(s) if String === s
  end

  def code_to_sel code
    @code = code
    CODE_TO_SEL[code] ||= :"parse_code_#{code}!"
  end

  def parse_top_level!
    send(code_to_sel(@s.readbyte))
  end

  def parse!
    send(code_to_sel(@s.readbyte))
  end

  def parse_code_4! # marshal-version
    @version = @s.readbyte
    parse!
  end

  # Atoms
  def parse_code_48!; parsed(:NilClass); end # n
  def parse_code_84!; parsed(:TrueClass); end # t
  def parse_code_70!; parsed(:FalseClass); end # f
  def parse_code_105! # I
    parsed(:Fixnum)
    
  end

  def parsed x
    @parsed = x
  end
end

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

class MemcacheAnalysis
  attr_accessor :h

  class Histogram
    def initialize
      @stat = Hash.new do | h, k |
        h[k] = Hash.new do | h, k |
          h[k] = 0
        end
      end
    end

    def add! stat, value
      h = @stat[stat]
      h[:count] += 1
      h[:total] += value
      self
    end
  end

  ADD = 'add'.freeze
  
  def parse_add i
    l = i.readline
    cmd, key, x, y, size = l.split(/\s+/)
    x = x.to_i
    y = y.to_i
    size = size.to_i
    case cmd
    when ADD
      data = i.read(size)
      $stderr.write "#{size}."
      binding.pry
      h.add! :item_size, size
      MarshalParse.new(data).parse_top_level!
    else
      $stderr.puts "   Unexpected #{l}"
    end
  end

  def initialize
    @h = Histogram.new
  end

  def parse! file
    File.open(file) do | i |
      until i.eof?
        parse_add i
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

