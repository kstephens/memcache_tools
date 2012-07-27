require 'pp'

###############################

class Object
  def __klass
    self.class
  end
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
  class PhonyModule
    REAL_MODULE = { }
    def initialize name
      @name = name
      @real_module = (REAL_MODULE[@name] ||= [ (eval(@name.to_s) rescue nil) ]).first
    end
    def _metaclass; ::Module; end
    def __klass_id
      @__klass_id ||= name.to_s.to_sym
    end
    def name
      @name.to_s
    end
    def to_s
      name
    end
    def inspect
      "#<#{_metaclass} #{@name}>"
    end
  end

  class PhonyClass < PhonyModule
    def _metaclass; ::Class; end
    def allocate
      if @real_module
        # $stderr.puts "  PhonyClass making real #{@real_class}"
        @real_module.allocate
      else
        PhonyObject.new(self)
      end
    end
    def _load data
      # $stderr.puts "  #{self} _load #{data.inspect}"
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
      (@_instance_variables ||= { })[n] = v
      # $stderr.puts "  #{self} _ivs_ #{n.inspect} #{v.class} #{v}"
    end
    def instance_variable_get n
      @_instance_variables && @_instance_variables[n]
    end
    def instance_variables
      (@_instance_variables || EMPTY_Hash).keys
    end
    def __store__ k, v
      # $stderr.puts "  #{self} __store__ #{k.inspect} #{v.class} #{v}"
    end
    def to_s
      "#<#{@__klass} #{object_id}>"
    end
    def inspect
      "#<#{@__klass} #{object_id} #{instance_variables.inspect}>"
    end
    def method_missing sel, *args
      if args.size == 1 and
          ! block_given? and
          @_instance_variables and
          @_instance_variables.key?(k = :"@#{sel}")
        @_instance_variables[k]
      else super end
    end
  end # class

end # class MarshalStats




