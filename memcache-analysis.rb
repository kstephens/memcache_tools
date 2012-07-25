#!/usr/bin/env ruby

require 'rubygems'
gem 'pry'
require 'pry'

# Hack rubinius Marshal
$:.unshift(File.expand_path('lib'))
require 'rubinius'
$:.unshift(File.expand_path('lib/kernel'))
require 'common/marshal'
require 'common/marshal18'

#######################################

class Histogram
  attr_accessor :chain
  attr_accessor :verbose

  def initialize
    @h = Hash.new do | h, k |
      h[k] = Hash.new do | h, k |
        h[k] = 0
      end
    end
  end

  def add! stat, value
    $stderr.puts "  add! #{stat.inspect} #{value.inspect}" if @verbose
    h = @h[stat]
    h[:count] += 1
    h[:total] += value
    @chain.add! stat, value if @chain
    self
  end

  def put o = $stdout
    ks = @h.keys.sort_by{|a, b| a.to_s <=> b.to_s }
    ks.each do | k |
      o.puts "#{k}:"
      h = @h[k]
      ks = h.keys.sort_by{|a, b| a.to_s <=> b.to_s }
      ks.each do | k |
        v = h[k]
        o.puts "   #{k}: #{v}"
      end
    end
    self
  end

end

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

class Object
  def __klass_id
    self.class.name
  end
end

class MarshalStats
  attr_accessor :s, :ch

  def initialize s = nil
    @s = s
  end

  def parse_top_level!
    @s = StringIO.new(@s) if String === @s
    major = @s.readbyte
    minor = @s.readbyte
    @state = State.new(@s, nil, nil)
    @state.h = @ch
    @state.construct
    @state.h
  end

  class PhonyClass
    REAL_CLASS = { }
    def initialize name
      @name = name
      @real_class = (REAL_CLASS[@name] ||= [ (eval(@name.to_s) rescue nil) ]).first
    end
    def allocate
      if @real_class
        # $stderr.puts "  PhonyClass making real #{@real_class}"
        @real_class.allocate
      else
        PhonyObject.new(self)
      end
    end
    def _load data
      # $stderr.puts "  #{self} _load #{data.inspect}"
    end
    def name
      @name
    end
    def to_s
      "#<#{self.class} #{@name}>"
    end
  end

  class PhonyObject
    def initialize c
      @__klass = c
    end
    def __klass
      @__klass
    end
    def __klass_id
      @__klass.name.to_s
    end
    def _load_data x
      @_load_data = x
    end
    def __instance_variable_set__ n, v
      # $stderr.puts "  #{self} _ivs_ #{n.inspect} #{v.class} #{v}"
    end
    def __store__ k, v
      # $stderr.puts "  #{self} __store__ #{k.inspect} #{v.class} #{v}"
    end
    def to_s
      "#<#{@__klass} #{object_id}>"
    end
  end

  class State < Marshal::IOState
    attr_accessor :h

    def initialize *args
      super
      @h = Histogram.new
    end

    def __log msg = nil
      if @verbose
        msg ||= yield
        $stderr.puts msg
      end
    end

    def const_lookup name, type = nil
      __log { "  const_lookup #{name.inspect} #{type.inspect}" }
      PhonyClass.new(name)
    end

    def construct_class
      @h.add! :Class, 1
      super
    end
    def construct_module
      @h.add! :Module, 1
      super
    end
    def construct_old_module
      @h.add! :_old_module, 1
      super
    end
    def construct_integer
      @h.add! :Fixnum, 1
      super
    end
    def construct_bignum
      @h.add! :Bignum, 1
      super
    end
    def construct_float
      @h.add! :Float, 1
      super
    end
    def construct_symbol
      @h.add! :Symbol, 1
      super
    end
    def construct_string
      @h.add! :String, 1
      super
    end
    def construct_regexp
      @h.add! :Regexp, 1
      super
    end
    def construct_array
      @h.add! :Array, 1
      super
    end
    def construct_hash
      @h.add! :Hash, 1
      super
    end
    def construct_hash_def
      @h.add! :_hash_def, 1
      super
    end
    def construct_struct
      @h.add! :Struct, 1
      super
    end
    def construct_object
      @h.add! :_object, 1
      obj = super
      @h.add! obj.__klass_id, 1
      obj
    end
    def construct_user_defined i
      @h.add! :_user_defined, 1
      super
    end
    def construct_user_marshal
      @h.add! :_user_marshal, 1
      super
    end
    def construct_data
      name = get_symbol
      @h.add! name, 1
      PhonyObject.new(name)
    end

    def store_unique_object obj
      __log { "  store_unique_object #{obj.class} #{obj}" }
      super obj
    end

    def extend_object obj
      unless @modules.empty?
        __log { "  extend_object #{obj} #{@modules.inspect}" }
      end
      @modules.clear
    end

    def set_instance_variables obj
      __log { "  set_instance_variables #{obj}" }
      super
    end

  end
end

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
    cmd, key, x, y, size = l.split(/\s+/)
    x = x.to_i
    y = y.to_i
    size = size.to_i
    case cmd
    when ADD
      @count += 1
      data = read(size)
      $stderr.write "#{size}:"

      readline
      h.add! :item_size, size
      ms = MarshalStats.new(data)
      ch = Histogram.new
      ch.chain = @ch
      ms.ch = ch
      ms.parse_top_level!

      o = $stderr
      o.puts "\n"
      ch.put o
      o.puts "\n"

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

