# Hack rubinius Marshal
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
        h[k] =
          case k
          when :values
            [ ]
          else
            0
          end
      end
    end
  end

  def count! stat, value = 1
    $stderr.puts "  count! #{stat.inspect} #{value.inspect}" if @verbose
    h = @h[stat]
    c = h[:count] += value
    @chain.count! stat, value if @chain
    self
  end

  def add! stat, value
    $stderr.puts "  add! #{stat.inspect} #{value.inspect}" if @verbose
    h = @h[stat]
    if ! (x = h[:min]) or value < x
      h[:min] = value
    end
    if ! (x = h[:max]) or value > x
      h[:max] = value
    end
    h[:values] << value
    c = h[:count] += 1
    t = h[:total] += value
    h[:avg] += t.to_f / c
    @chain.add! stat, value if @chain
    self
  end

  def merge_from! c
    @c.each do | k, h |
      add! :"#{k}_count", h[:count]
      add! :"#{k}_total", h[:total] if h[:total]
    end
    self
  end

  def put o = $stdout
    ks = @h.keys.sort_by{|e| e.to_s}
    ks.each do | k |
      h = @h[k]
      if h.keys.size == 1 and h.keys[0] == :count
        o.puts "    '#{k}': #{h[:count]}"
        next
      end
      if values = h.delete(:values) and ! values.empty?
        n = values.size
        values.sort!
        h[:median] = values[n / 2]
        avg = h[:avg]
        values.map!{|v| v = (v - avg); v * v}
        values.sort!
        h[:stddev] = Math.sqrt(values.inject(0){|s, e| s + e}.to_f / n)
      end
      o.puts "    #{k.inspect}:"
      hks = h.keys.sort_by{|e| e.to_s}
      hks.each do | hk |
        v = h[hk]
        o.puts "       #{hk.inspect}: #{v.inspect}"
      end
    end
    self
  end

end

###############################

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
    @state.relax_struct_checks = true
    @state.relax_object_ref_checks = true
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
    def marshal_load x
      @marshal_load = x
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
      @h.count! :Class
      super
    end
    def construct_module
      @h.count! :Module
      super
    end
    def construct_old_module
      @h.count! :_old_module
      super
    end
    def construct_integer
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_bignum
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_float
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_symbol
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_string
      obj = super
      @h.count! obj.__klass_id
      @h.add! "#{obj.__klass_id}#size", @size
      obj
    end
    def construct_regexp
      obj = super
      super
      @h.count! obj.__klass_id
      obj
    end
    def construct_array
      obj = super
      @h.count! obj.__klass_id
      @h.add! "#{obj.__klass_id}#size", @size
      obj
    end
    def construct_hash
      obj = super
      @h.count! obj.__klass_id
      @h.add! "#{obj.__klass_id}#size", @size
      obj
    end
    def construct_hash_def
      @h.count! :_hash_def
      super
    end
    def construct_struct
      @h.count! :Struct
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_object
      @h.count! :_object
      obj = super
      @h.count! obj.__klass_id
      obj
    end
    def construct_user_defined i
      @h.count! :_user_defined
      super
    end
    def construct_user_marshal
      @h.count! :_user_marshal
      super
    end
    def construct_data
      @h.count! :_data
      super
    end

    def store_unique_object obj
      __log { "  store_unique_object #{obj.class} #{obj}" }
      @h.count! :_unique_object
      super obj
    end

    def extend_object obj
      unless @modules.empty?
        @h.count! :_extend_object, @modules.size
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

