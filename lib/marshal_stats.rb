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
        h[k] = 0
      end
    end
  end

  def add! stat, value
    $stderr.puts "  add! #{stat.inspect} #{value.inspect}" if @verbose
    h = @h[stat]
    c = h[:count] += 1
    t = h[:total] += value
    h[:avg] += t / c
    @chain.add! stat, value if @chain
    self
  end

  def merge_from! c
    @c.each do | k, h |
      add! :"#{k}_count", h[:count]
      add! :"#{k}_total", h[:total]
    end
    self
  end

  def put o = $stdout
    ks = @h.keys.sort_by{|a, b| a.to_s <=> b.to_s }
    ks.each do | k |
      o.puts "    #{k}:"
      h = @h[k]
      hks = h.keys.sort_by{|a, b| a.to_s <=> b.to_s }
      hks.each do | hk |
        v = h[hk]
        o.puts "       #{hk}: #{v}"
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
      @h.add! :_data, 1
      super
    end

    def store_unique_object obj
      __log { "  store_unique_object #{obj.class} #{obj}" }
      @h.add! :_unique_object, 1
      super obj
    end

    def extend_object obj
      unless @modules.empty?
        @h.add! :_extend_object, @modules.size
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

