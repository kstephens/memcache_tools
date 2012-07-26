# Hacked up rubinius Marshal
require 'rubinius'
$:.unshift(File.expand_path('lib/kernel'))
require 'common/marshal'
require 'common/marshal18'

require 'pp'

###############################

class Object
  def __klass_id
    self.class.__klass_id
  end
end

class Class
  def __klass_id
    @__klass_id ||= self.name.to_sym
  end
end

###############################

class MarshalStats
  attr_accessor :s, :ch, :state

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
    @state.construct_top_level
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
    def __klass_id
      @__klass_id ||= name.to_s.to_sym
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
      @__klass.__klass_id
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

  class State < HackedMarshal::Marshal::IOState
    attr_accessor :h, :unique_string, :unique_object

    def initialize *args
      super
      @h = Stats.new
      @phony_class = { }
      @unique_string = { }
      @unique_object = { }
    end

    def __log msg = nil
      if @verbose
        msg ||= yield
        $stderr.puts msg
      end
    end

    def construct_top_level
      obj = construct
      top_level_stats!
      obj
    end

    def top_level_stats!
      @unique_object.each do | oid, h |
        obj = h[:object]
        size = h[:size] = h[:end_pos] - h[:start_pos]
        begin
          # size in Marshal stream, includes subobjects.
          count_obj_size! obj, size
          # Enumerable size.
          case obj
          when String
            @unique_string[obj] ||= 0
            if (@unique_string[obj] += 1) == 1
              @h.add! "#{obj.__klass_id}#size unique", @size
            end
          when String, Array, Hash, Enumerable
            @h.add! "#{obj.__klass_id}#size", obj.size
          when Symbol, Regexp
            @h.add! "#{obj.__klass_id}#size", obj.to_s.size
          else
          end
          # # of ivars.
          @h.add! :"#{obj.__klass_id} ivars.size", obj.instance_variables.size
        rescue SignalException, Interrupt, SystemExit
          raise
        rescue ::Exception => exc
          $stderr.puts "  #{self.class}: ERROR #{exc.inspect} in #{obj.class} #{obj}"
        end
      end

      @unique_string.each do | obj, c |
        next unless c >= 2
        @h.add! :'String redunancies size', obj.size
        @h.add! :'String redunancies counts', c
      end

      self
    end

    def construct ivar_index = nil, call_proc = nil
      start_pos = @stream.pos
      obj = super
      end_pos = @stream.pos

      unless Rubinius::Type.object_kind_of? obj, ImmediateValue
        h = @unique_object[obj.object_id] ||= { :object => obj }
        h[:start_pos] ||= start_pos
        h[:end_pos] = end_pos unless ivar_index
      end

      obj
    end

    def const_lookup name, type = nil
      __log { "  const_lookup #{name.inspect} #{type.inspect}" }
      @phony_class[name] ||= PhonyClass.new(name)
    end

    def construct_extended_object
      @h.count! :_extended_object
      super
    end

    def construct_object_ref
      @h.count! :_object_ref
      super
    end
    def construct_symbol_ref
      @h.count! :_symbol_ref
      super
    end

    def construct_class
      @h.count! :_class
      super
    end
    def construct_module
      @h.count! :_module
      super
    end
    def construct_old_module
      @h.count! :_old_module
      super
    end

    def count_obj! obj
      @h.count! obj.__klass_id
      obj
    end

    def count_obj_size! obj, size
      # $stdout.puts "  # count_obj_size! #{obj.__klass_id} #{obj.object_id}"
      @h.add! :"#{obj.__klass_id} stream_size", size
=begin
      #if Hash === obj and size > 2000
        pp [ :big_Hash, obj ]
      end
=end
      obj
    end

    def construct_integer
      @h.count! :_integer
      count_obj! super
    end
    def construct_bignum
      @h.count! :_bignum
      count_obj! super
    end
    def construct_float
      @h.count! :_float
      count_obj! super
    end
    def construct_symbol
      @h.count! :_symbol
      obj = count_obj! super
      #if obj.to_s.size > 40
      #  $stdout.puts "   # **** large Symbol: #{obj}"
      #end
      obj
    end
    def construct_string
      @h.count! :_string
      obj = count_obj! super
      obj
    end
    def construct_regexp
      @h.count! :_regexp
      count_obj! super
    end
    def construct_array
      @h.count! :_array
      obj = count_obj! super
      obj
    end
    def construct_hash
      @h.count! :_hash
      obj = count_obj! super
      obj
    end
    def construct_hash_def
      @h.count! :_hash_def
      super
    end
    def construct_struct
      @h.count! :_struct
      count_obj! super
    end
    def construct_object
      @h.count! :_object
      count_obj! super
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
        @h.count! :_extend_object
        @h.add!   :extend, @modules.size
        @h.count! :"extend(#{@modules.pop.name})" until @modules.empty?
        __log { "  extend_object #{obj} #{@modules.inspect}" }
      end
      @modules.clear
    end

    def _set_instance_variables obj, count
      __log { "  set_instance_variables #{obj}" }
      super
    end

  end

end # class MarshalStats


require 'marshal_stats/stats'
