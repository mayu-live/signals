# frozen_string_literal: true
# typed: strict

module Mayu
  module Signals
    module Utils
      extend T::Sig

      sig { params(str: String).returns(String) }
      def self.numbers_to_subscript(str)
        str
          .to_s
          .codepoints
          .map { |cp| (cp in 48..58) ? 0x2080 - 48 + cp : cp }
          .pack("U*")
      end

      sig { params(name: T.any(Symbol, String), value: T.untyped, block: T.proc.void).void }
      def self.with_fiber_local(name, value, &block)
        prev = Fiber[name]
        Fiber[name] = value
        yield
      ensure
        Fiber[name] = prev
      end

      sig {returns([String, Integer])}
      def self.get_caller_location
        location = caller.find { !_1.start_with?(__FILE__) }
        location.match(/^(.*):(\d+):in /) => [file, line]
        [file, line.to_i]
      end
    end
  end
end
