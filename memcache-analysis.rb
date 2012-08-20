#!/usr/bin/env ruby

require 'rubygems'
gem 'pry'
require 'pry'

require 'time'
$:.unshift(File.expand_path('lib'))
require 'marshal_stats'
require 'object_class_graph'

require 'zlib'

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
      attr_accessor :finder_sql, :conditions, :loaded, :reflection, :owner, :counter_sql, :target
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

class MemcacheAnalysis
  class Item
    include MarshalStats::Initialization, Comparable
    def <=> b
      self.size <=> b.size
    end
    attr_accessor :filename, :line, :lineno, :i
    attr_accessor :key, :x, :y, :size
    attr_accessor :pos, :pos_data, :pos_end
    attr_accessor :error
    attr_accessor :s

    attr_accessor :root_object, :objects, :classes, :modules

    def data
      data = File.open(@filename) do | f |
        f.seek(pos_data)
        f.read(size)
      end
      data
    end

    def root_object; analysis unless @root_object; @root_object; end
    alias :r :root_object
    def objects;     analysis unless @objects; @objects; end
    def classes;     analysis unless @classes; @classes; end
    def modules;     analysis unless @modules; @modules; end
    def c name; classes.find{|c| c.name == name}; end

    def analyze!
      self.s = MarshalStats::Stats.new
      begin
        ms = MarshalStats.new(data)
        ms.name = key
        ms.stats = s
        ms.parse_top_level! self
      rescue Interrupt, SystemExit
        raise
      rescue Exception => exc
        self.error = [ exc.class.name, exc.inspect, exc.backtrace ]
      end
      if error && (ENV['PRY_ON_ERROR'] || 0).to_i > 0
        binding.pry
      end
      ms
    end

    alias :inspect :to_s
    def desc
      o = StringIO.new
      o.puts "# #{inspect}"
      o.puts "#{key}:"
      o.puts "  :lineno: #{lineno}"
      o.puts "  :size: #{size}"
      o.puts "  :x:    #{x}"
      o.puts "  :y:    #{y}"
      # o.puts "  :atime: #{atime.iso8601}"
      o.puts "  :pos:  #{pos}"
      o.puts "  :stats:"
      s.put o
      o.puts "  :error: #{error.inspect}"
      o.string
    end

    def analysis o = nil
      ms = analyze!
      o ||= $stdout
      o.puts desc
      # ms.state.unique_string.to_a.sort_by{|a| - a[1]}.each do | s, v |
      #   o.puts "  # #{v} #{s.inspect}"
      # end
      o.puts "\n"
      nil
    end

    def s
      unless @s
        analysis
      end
      @s
    end
  end # class Item

  attr_accessor :s

  ADD = 'add'.freeze

  def parse_cmd
    l = readline
    item = Item.new(:pos => @in.pos, :filename => @filename, :line => l, :lineno => @lineno)
    cmd, *args = l.split(/\s+/)
    case cmd
    when ADD
      key, x, y, size = args
      x = x.to_i # What is this number?
      y = y.to_i # What is this number?
      # atime = Time.at(x).utc
      size = size.to_i

      if @count % 100 == 0
        $stderr.write "\n # #{@count}: "
      end
      $stderr.write "#{size}."

      item.i = @items.size
      item.key = key.freeze
      item.size = size
      item.x = x
      item.y = y

      @items << item
      @item_by_key[key] = item
      @s.add! :key_size, key.size
      @s.add! :item_size, size

      item.pos_data = @in.pos
      data = read(size)
      readline
      item.pos_end = @in.pos

      (1..9).each do | level |
        GC.disable
        t0 = Time.now.to_f
        zlib_data = Zlib::Deflate.deflate(data, level)
        Zlib::Inflate.inflate(zlib_data)
        zlib_time = Time.now.to_f - t0
        GC.enable
        zlib_size = zlib_data.size
        @s.add! :"item_time_zlib_#{level}", zlib_time
        @s.add! :"item_size_zlib_#{level}", zlib_size
      end

      @count += 1
    else
      $stderr.puts "   Unexpected cmd: #{l.inspect}"
    end
    item
  end

  def readline
    @lineno += 1
    @in.readline
  end

  def read size
    if str = @in.read(size)
      @lineno += str.count("\n")
    end
    str
  end

  attr_accessor :items
  def item key
    @item_by_key[key]
  end
  def keys
    @items.map{|i| i.key}
  end

  def initialize
    @lineno = 0
    @count = 0
    @s = MarshalStats::Stats.new
    @pry_on_error = (ENV['PRY_ON_ERROR'] || 0).to_i > 0
    @items = [ ]
    @item_by_key = { }
  end

  def parse! file
    obj = self
    file_dump = "#{file}.marshal"
    if File.exist?(file_dump) && File.size(file_dump) > 100
      $stderr.puts "loading #{file_dump}"
      obj = Marshal.load(File.read(file_dump))
      $stderr.puts "loading #{file_dump} : DONE"
    else
      obj = self
      $stderr.puts "parsing #{file}"
      File.open(file) do | i |
        @filename = file.freeze
        @in = i
        until i.eof?
          parse_cmd
        end
      end
      @in = nil
      @items.sort!
      $stderr.puts "\nparsing #{file}: DONE"
      begin
        $stderr.puts "dumping #{file_dump}"
        File.open(file_dump, "w+") do | o |
          o.write Marshal.dump(self)
        end
        $stderr.puts "dumping #{file_dump} : DONE"
      rescue ::Exception => exc
        $stderr.puts "  ERROR: #{exc.inspect}\n  #{exc.backtrace * "\n  "}"
        File.unlink(file_dump) rescue nil
      end
    end
    obj
  end

  def h b = nil
    b ||= @s[:item_size]
    puts "\n= #{b.count} ======================"
    puts b.histogram(:width => 50, :height => 40) * "\n"
    nil
  end

  def run!
    file = ARGV.first or raise "No file specified"
    obj = parse!(file)
    @items.sort!
    obj.h
    obj.shell! if $stdout.isatty
    obj
  end

  def ocg x
    ObjectClassGraph.new.run!(x)
  end

  def shell!
    IRB.start_session(binding)
    self
  end

end

#####################

require 'irb'

module IRB # :nodoc:
  def self.start_session(binding)
    unless @__initialized
      args = ARGV
      ARGV.replace(ARGV.dup)
      IRB.setup(nil)
      ARGV.replace(args)
      @__initialized = true
    end

    workspace = WorkSpace.new(binding)

    irb = Irb.new(workspace)

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end

#####################

MemcacheAnalysis.new.run!

