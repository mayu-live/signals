# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require_relative "signals/version"
require_relative "signals/core"

module Mayu
  module Signals
    module Helpers
      extend T::Sig

      sig { params(block: T.proc.void).void }
      def root(&block) = Core::Root.create(&block)

      sig { params(block: T.proc.void).void }
      def batch(&block) = Core::Root.current.batch(&block)

      sig do
        type_parameters(:U)
          .params(initial_value: T.type_parameter(:U))
          .returns(Core::Signal::Proxy[T.all(T.type_parameter(:U), Object)])
      end
      def signal(initial_value) = Core::Signal.new(initial_value).proxy

      sig do
        type_parameters(:U)
          .params(compute: T.proc.returns(T.type_parameter(:U)))
          .returns(Core::Signal::Proxy[T.all(T.type_parameter(:U), Object)])
      end
      def computed(&compute) = Core::Computed.new(&compute).proxy

      sig do
        type_parameters(:U)
          .params(compute: T.proc.returns(T.type_parameter(:U)))
          .returns(Method)
      end
      def effect(&compute) = Core::Effect.create(&compute)
    end

    module S
      extend Helpers
    end
  end
end
