# frozen_string_literal: true
# typed: strict

module Mayu
  module Signals
    class Flags
      extend T::Sig

      RUNNING = T.let(1 << 0, Integer)
      NOTIFIED = T.let(1 << 1, Integer)
      OUTDATED = T.let(1 << 2, Integer)
      DISPOSED = T.let(1 << 3, Integer)
      HAS_ERROR = T.let(1 << 4, Integer)
      TRACKING = T.let(1 << 5, Integer)

      sig { params(value: Integer).void }
      def initialize(value = 0)
        @value = value
      end

      sig { returns(String) }
      def inspect
        return "NONE" if @value.zero?

        self
          .class
          .constants
          .filter_map { |const| const if set?(self.class.const_get(const)) }
          .join("|")
      end
      alias to_s inspect

      sig { returns(Integer) }
      def to_i = @value

      sig { returns(T::Boolean) }
      def true? = @value != 0
      sig { returns(T::Boolean) }
      def false? = @value == 0

      sig { params(num: T.untyped).returns([Flags, Flags]) }
      def coerce(num) = [self, self.class.new(num)]

      sig { params(other: T.any(Flags, Integer)).returns(Flags) }
      def |(other) = self.class.new(@value | other.to_i)
      sig { params(other: T.any(Flags, Integer)).returns(Flags) }
      def &(other) = self.class.new(@value & other.to_i)
      sig { params(other: T.any(Flags, Integer)).returns(Flags) }
      def ^(other) = self.class.new(@value ^ other.to_i)

      sig { params(other: T.any(Flags, Integer)).returns(T::Boolean) }
      def ==(other) = @value == other.to_i

      sig { params(bits: T.any(Flags, Integer)).returns(T::Boolean) }
      def set?(bits) = (@value & bits.to_i) != 0
      sig { params(bits: T.any(Flags, Integer)).void }
      def set!(bits) = @value |= bits.to_i
      sig { params(bits: T.any(Flags, Integer)).returns(T::Boolean) }
      def unset?(bits) = (@value & bits.to_i) == 0
      sig { params(bits: T.any(Flags, Integer)).void }
      def unset!(bits) = @value &= ~bits.to_i
    end
  end
end
