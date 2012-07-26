require 'marshal_stats'

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
      bar = "|#{bar}#{' ' * (@width - bar.size)}|"
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
    attr_accessor :width, :height

    def initialize values = nil
      @values = values
      @width = 15
      @height = 20
    end

    def generate
      return [ ] if @values.size < 2
      @x_graph = Graph.new(@values, @width)
      return [ ] if @x_graph.empty?
      @x_graph.fix_width!

      @buckets = Hash.new { |h, k| h[k] = Bucket.new }
      @values.each do | v |
        i = @x_graph.v_to_x(v).to_i
        @buckets[i].add! v
      end

      cnt = @buckets.values.map { |b| b.count }
      cnt << 0
      @cnt_graph = Graph.new(cnt, @height)
      return [ ] if @cnt_graph.empty?
      # @cnt_graph.fix_width!

      sum = @buckets.values.map { |b| b.sum }
      sum << 0
      @sum_graph = Graph.new(sum, @height)
      # @sum_graph.fix_width!

      # binding.pry

      rows = [ ]

      # Header
      row = [ ]
      row << '%30s' % ''
      row << '-'
      row << '%30s' % ''
      row << '%30s' % 'cnt'
      row << ('=' * (@cnt_graph.width + 2))
      row << '%30s' % 'min'
      row << '%30s' % 'avg'
      row << '%30s' % 'max'
      row << '%30s' % 'sum'
      row << ('=' * (@sum_graph.width + 2))
      rows << row

      @width.times do | i |
        x0 = @x_graph.x_to_v(i).to_i
        x1 = @x_graph.x_to_v(i + 1).to_i
        b = @buckets[i]
        b.finish!

        row = [ ]
        row << x0
        row << '-'
        row << x1
        row << b.count
        row << @cnt_graph.bar(b.count)
        row << b.min
        row << b.avg
        row << b.max
        row << b.sum
        row << @sum_graph.bar(b.sum || 0)
        rows << row
      end

      rows.each do | r |
        ci = -1
        r.map! do | c |
          ci += 1
          h_size = rows[0][ci].size
          case c
          when nil
            c = (' ' * (h_size - 1)) << '-'
          when Numeric
            c = '%*d' % [ h_size, c.to_i ]
          end
          c
        end
      end

      # binding.pry

      leading_ws = [ ]
      rows.each do | r |
        r.each_with_index do | c, ci |
          ws = 0
          if c =~ /^(\s+)/
            ws = $1.size
          end
          leading_ws[ci] ||= ws
          leading_ws[ci] = ws if leading_ws[ci] > ws
        end
      end

      # binding.pry
      formatted=
      rows.map do | r |
        ci = -1
        r.map do | c |
          c[leading_ws[ci += 1] .. -1]
        end * ' '
      end
      # binding.pry

      formatted
    end
  end

end

end

