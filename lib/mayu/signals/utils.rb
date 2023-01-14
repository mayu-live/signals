# frozen_string_literal: true

module Mayu
  module Signals
    module Utils
      def self.numbers_to_subscript(str)
        str
          .to_s
          .codepoints
          .map { |cp| (cp in 48..58) ? 0x2080 - 48 + cp : cp }
          .pack("U*")
      end

      def self.with_fiber_local(name, value, &)
        prev = Fiber[name]
        Fiber[name] = value
        yield
      ensure
        Fiber[name] = prev
      end

      def self.with_thread_local(name, value, &)
        prev = Thread.current[name]
        Thread.current[name] = value
        yield
      ensure
        Thread.current[name] = prev
      end

      def self.get_caller_location
        location = caller.find { !_1.start_with?(__FILE__) }
        location.match(/^(.*):(\d+):in /) => [file, line]
        [file, line.to_i]
      end
    end
  end
end
