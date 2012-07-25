# Scaffold for Rubinus marshal.rb

module Rubinius
  class LookupTable < Hash
  end
  module ImmediateValue
  end
  module Type
    def self.coerce_to x, t, m
      case x
      when t
        x
      else
        x.send(m)
      end
    end
    def self.object_kind_of? x, t
      t === x
    end
  end
  def self.binary_string x
    x
  end
end

ImmediateValue = Rubinius::ImmediateValue
[
  NilClass,
  TrueClass,
  FalseClass,
  Fixnum,
].each { | c | c.instance_eval { include Rubinius::ImmediateValue } }


class Object
  alias :__instance_variable_set__ :instance_variable_set
end

class Hash
  alias :__store__ :[]=
end

class Array
  alias :__append__ :<<
end
