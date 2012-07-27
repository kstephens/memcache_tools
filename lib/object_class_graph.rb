  class ObjectClassGraph
    def initialize
      @visited = { }
      @depth = 0
    end
    def run! obj
      p obj.class
      visit obj
    end
    def visit obj
      case obj
      when nil, true, false, Numeric, String, Symbol, Range
      else
        return if @visited[obj.object_id]
        @visited[obj.object_id] = obj
        @cs = { }; @vs = { }
        obj.instance_variables.each do | ivar |
          add! obj.instance_variable_get(ivar)
        end
        case obj
        when Array
          obj.each { | v | add! v }
        when Hash
          obj.each { | k, v | add! k; add! v }
        end
        d do
          cs = @cs; vs = @vs
          cs.keys.sort.each do | c |
            p "%s %d" % [ c, cs[c] ]
            vs[c].each { | x | visit x }
          end
        end
      end
    end
    def add! v
      c = v.__klass.name
      (@vs[c] ||= [ ]) << v
      @cs[c] ||= 0
      @cs[c] += 1
    end
    def p x
      puts "#{'-' * @depth} #{x}"
    end
    def d
      @depth += 1
      yield
    ensure
      @depth -= 1
    end
  end # class
