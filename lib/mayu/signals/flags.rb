# frozen_string_literal: true

module Mayu
  module Signals
    class Flags
      RUNNING = 1 << 0
      NOTIFIED = 1 << 1
      OUTDATED = 1 << 2
      DISPOSED = 1 << 3
      HAS_ERROR = 1 << 4
      TRACKING = 1 << 5

      def initialize(value = 0)
        @value = value
      end

      def inspect
        return "NONE" if @value.zero?

        self
          .class
          .constants
          .filter_map { |const| const if set?(self.class.const_get(const)) }
          .join("|")
      end
      alias to_s inspect

      def to_i = @value

      def true? = @value != 0
      def false? = @value == 0

      def coerce(num) = [self, self.class.new(num)]

      def |(other) = self.class.new(@value | other.to_i)
      def &(other) = self.class.new(@value & other.to_i)
      def ^(other) = self.class.new(@value ^ other.to_i)
      def ! = self.class.new(!@value)

      def ==(other) = @value == other.to_i

      def set?(bits) = (@value & bits) != 0
      def set!(bits) = @value |= bits
      def unset?(bits) = (@value & bits) == 0
      def unset!(bits) = @value &= ~bits
    end
  end
end
