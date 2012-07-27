require 'marshal_stats'
gem 'terminal-table'
require 'terminal-table'

class MarshalStats
class Stats
  attr_accessor :chain
  attr_accessor :verbose

  def initialize
    @s = Hash.new do | h, k |
      b = Bucket.new
      b.values = [ ]
      h[k] = b
    end
  end

  def count! stat, value = 1
    $stderr.puts "  count! #{stat.inspect} #{value.inspect}" if @verbose
    c = @s[stat]
    c.count! value
    @chain.count! stat, value if @chain
    self
  end

  def add! stat, value
    $stderr.puts "  add! #{stat.inspect} #{value.inspect}" if @verbose
    b = @s[stat]
    b.add! value
    @chain.add! stat, value if @chain
    self
  end

  def put o = $stdout
    ks = @s.keys.sort_by{|e| e.to_s}
    ks.each do | k |
      c = @s[k]
      c.finish!
      if c.count_only?
        o.puts "    :'#{k}': #{c.count}"
        next
      end
      histogram = nil
      if values = c.values and ! values.empty?
        histogram = c.histogram
        histogram = nil if histogram.empty?
      end
      o.puts "    #{k.to_sym.inspect}:"
      c.to_a.each do | k, v |
        o.puts "       #{k.to_sym.inspect}: #{v.inspect}"
      end
      if histogram
        o.puts "       :histogram:"
        histogram.each do | l |
          o.puts "         - #{l.inspect}"
        end
      end
    end
    self
  end

  class Bucket
    KEYS =
    [
      :count,
      :min,
      :median,
      :avg,
      :stddev,
      :max,
      :sum,
    ]

    attr_accessor *KEYS
    attr_accessor :values

    def initialize
      @count = 0
    end

    def to_a
      h = [ ]
      KEYS.each do | k |
        v = instance_variable_get("@#{k}")
        h << [ k, v ] if v
      end
      h
    end

    def count! x
      @count += 1
      self
    end

    def count_only?
      ! @sum
    end

    def add! x
      unless @min
        @min = @max = x
      else
        @min = x if x < @min
        @max = x if x > @max
      end
      @values << x if @values
      @sum ||= 0
      s = @sum += x
      c = @count += 1
      @avg = s.to_f / c
      self
    end

    def empty?
      ! @min || @max == @min
    end

    def finish!
      if @count == 1
        @min = @max = @avg = nil
      end
      if @avg && @values && ! @values.empty?
        @values.sort!
        n = @values.size
        @median = @values[n / 2]
        v = @values.map{|e| e = (e - @avg); e * e}
        v.sort!
        s = 0
        v.each {|e| s += e }
        @stddev = Math.sqrt(s.to_f / n)
      end
      self
    end

    def histogram
      @histogram ||=
        Histogram.new(values).generate
    end
  end

  class Graph < Bucket
    attr_accessor :width

    def initialize values = nil, width = nil
      super()
      @width = width || 20
      @values = [ ]
      if values
        values.each { | v | add! v }
        finish!
      end
    end

    def fix_width!
      @width = 1 if @width < 1
      @max = x_to_v(@width + 1)
      @max_min = (@max - @min).to_f
      self
    end

    def finish!
      super
      return nil if empty?
      @max_min = @max - @min
      @values_are_integers = @values.all?{|e| Integer === e}
      if @values_are_integers
        if @width > @max_min
          @width = @max_min.to_i
        else
          @max_min = @max_min.to_f
        end
      end
      self
    end

    def bar value
      x = v_to_x(value).to_i
      binding.pry if x < 0
      if value > @min and x < 1
        bar = '.'
      else
        bar = "*" * x
      end
      bar = "#{bar}#{' ' * (@width - bar.size)}"
      bar
    end

    def v_to_x v
      (v - @min) * @width / @max_min # = x
    end

    def x_to_v x
      (x * @max_min / @width) + @min # = v
    end
  end

  class Histogram
    attr_accessor :values
    attr_accessor :min, :max
    attr_accessor :width, :height, :show_sum

    def initialize values = nil
      @values = values
      @width = 15
      @height = 20
    end

    def generate
      raise TypeError, "@values not set" unless @values
      return [ ] if @values.size < 2
      @x_graph = Graph.new(@values, @width)
      return [ ] if @x_graph.empty?
      @x_graph.fix_width!

      @buckets = Hash.new { |h, k| b = Bucket.new; b.name = k; h[k] = b }
      @values.each do | v |
        i = @x_graph.v_to_x(v).to_i
        if i >= 0 and i < @x_graph.width
          @buckets[i].add! v
        end
      end

      cnt = @buckets.values.map { |b| b.count }
      cnt << 0
      @cnt_graph = Graph.new(cnt, @height)
      return [ ] if @cnt_graph.empty?
      # @cnt_graph.fix_width!

      if @show_sum
      sum = @buckets.values.map { |b| b.sum }
      sum << 0
      @sum_graph = Graph.new(sum, @height)
      # @sum_graph.fix_width!
      end

      # binding.pry

      rows = [ ]
      table =
        Terminal::Table.new() do | t |

        s = t.style
        s.border_x =
          s.border_y =
          s.border_i = ''
        s.padding_left = 0
        s.padding_right = 1

        # Header:
        h = [ '<', '>', 'cnt', '%', "cnt h", "min", "avg", "max" ]
        align_right = [ 0, 1, 2, 3, 5, 6, 7 ]
        if @show_sum
          h.push('sum', '%', 'sum h')
          align_right.push(8, 9)
        end
        rows << h

        cnt_sum = sum_sum = 0
        @width.times do | i |
          x0 = @x_graph.x_to_v(i).to_i
          x1 = @x_graph.x_to_v(i + 1).to_i - 1
          b = @buckets[i]
          b.finish!

          cnt_sum += b.count
          r = [ ]
          r << x0
          r << x1
          r << b.count
          r << @cnt_graph.percent(b.count)
          r << @cnt_graph.bar(b.count)
          r << b.min
          r << (b.avg && (@cnt_graph.values_are_integers ? b.avg.to_i : b.avg))
          r << b.max
          if @show_sum
            sum_sum += b.sum || 0
            r << b.sum
            r << @sum_graph.percent(b.sum || 0)
            r << @sum_graph.bar(b.sum || 0)
          end
          rows << r
        end

        f = [ '', '=', cnt_sum, '', '', '', '', '' ]
        if @show_sum
          f.push(sum_sum, '', '')
        end
        rows << f

        rows.each do | r |
          r.map! do | c |
            case c
            when nil
              ''
            when Integer
              thousands(c)
            else
              c
            end
          end
          t << r
        end

        raise unless h.size == f.size

        align_right.each { | c | t.align_column(c, :right) }
      end

      formatted = table.to_s.split("\n")

      formatted
    end

    def thousands x
      x && x.to_s.reverse!.gsub(/(\d{3})/, "\\1,").reverse!.sub(/^(\D|\A),/, '')
    end
  end

end

end

