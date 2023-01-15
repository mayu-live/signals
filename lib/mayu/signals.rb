# frozen_string_literal: true

require_relative "signals/version"
require_relative "signals/utils"
require_relative "signals/flags"

module Mayu
  module Signals
    module Core
      class Root
        CURRENT_KEY = :"Signals::Core::Root.current"

        def self.current = Fiber[CURRENT_KEY] ||= new

        def self.create(&) =
          Utils.with_fiber_local(CURRENT_KEY, new, &)

        def initialize
          @global_version = 0
          @batched_effect = nil
          @batch_depth = 0
          @batch_iteration = 0
        end

        attr_accessor :batched_effect
        attr_accessor :global_version
        attr_reader :batch_iteration

        def batch(&)
          return yield if @batch_depth > 1

          begin
            @batch_depth += 1
            return yield
          ensure
            if @batch_depth > 1
              @batch_depth -= 1
            else
              end_batch
            end
          end
        end

        private

        def end_batch
          error = nil
          has_error = false

          while @batched_effect
            effect = @batched_effect
            @batched_effect = nil
            @batch_iteration += 1

            while effect
              next_effect = effect.next_batched_effect
              effect.next_batched_effect = nil
              effect.flags.unset!(Flags::NOTIFIED)

              if effect.flags.unset?(Flags::DISPOSED) &&
                   Core.needs_to_recompute?(effect)
                begin
                  effect._callback
                rescue => e
                  unless has_error
                    error = e
                    has_error = true
                  end
                end
              end

              effect = next_effect
            end
          end

          raise error if has_error
        ensure
          @batch_iteration = 0
          @batch_depth -= 1
        end
      end

      class Node
        attr_accessor :source
        attr_accessor :next_source
        attr_accessor :prev_source

        attr_accessor :target
        attr_accessor :prev_target
        attr_accessor :next_target

        attr_accessor :version
        attr_accessor :rollback_node

        def initialize(**kwargs)
          kwargs.each { self.send("#{_1}=", _2) }
        end

        def inspect
          "#<#{self.class.name}#{Utils.numbers_to_subscript(@version)} source=#{@source.inspect} prev_source=#{@prev_source.inspect} next_source=#{@next_source.inspect} target=#{@target.inspect} prev_target=#{@prev_target.inspect} next_target=#{@next_target.inspect}>"
        end
      end

      def self.add_dependency(signal)
        eval_context = Fiber[:eval_context]
        return unless eval_context

        node = signal.node

        if !node || node.target != eval_context
          node =
            Node.new(
              version: 0,
              source: signal,
              prev_source: eval_context.sources,
              next_source: nil,
              target: eval_context,
              prev_target: nil,
              next_target: nil,
              rollback_node: node
            )

          eval_context.sources.next_source = node if eval_context.sources

          eval_context.sources = node
          signal.node = node

          # Subscribe to change notifications from this dependency if we're in an effect
          # OR evaluating a computed signal that in turn has subscribers.
          signal._subscribe(node) if eval_context.flags.set?(Flags::TRACKING)

          return node
        elsif node.version == -1
          # `signal` is an existing dependency from a previous evaluation. Reuse it.
          node.version = 0

          # If `node` is not already the current tail of the dependency list (i.e.
          # there is a next node in the list), then make the `node` the new tail. e.g:
          #
          # { A <-> B <-> C <-> D }
          #         ↑           ↑
          #        node   ┌─── tail (evalContext._sources)
          #         └─────│─────┐
          #               ↓     ↓
          # { A <-> C <-> D <-> B }
          #                     ↑
          #                    tail (evalContext._sources)
          if node.next_source
            node.next_source.prev_source = node.prev_source

            node.prev_source.next_source = node.next_source if node.prev_source

            node.prev_source = eval_context.sources
            node.next_source = nil

            eval_context.sources.next_source = node
            eval_context.sources = node
          end

          # We can assume that the currently evaluated effect / computed signal is already
          # subscbed to change notifications from `signal` if needed.
          return node
        end

        nil
      end

      class Signal
        class Proxy
          def initialize(signal)
            @signal = signal
          end

          def subscribe(&) = @signal.subscribe(&)
          def inspect = @signal.inspect
          alias to_s inspect

          def peek = @signal.peek
          def value = @signal.value
          def value=(new_value)
            @signal.value = new_value
          end
        end

        attr_accessor :version
        attr_accessor :targets
        attr_accessor :node

        def initialize(value)
          @value = value
          @version = 0
          @node = nil
          @targets = nil
          @proxy = nil
        end

        def inspect
          "𝙎#{Utils.numbers_to_subscript(@version)}(#{@value.inspect})"
        end

        def proxy = @proxy ||= Proxy.new(self)

        def subscribe(&)
          S.effect do
            Fiber[:eval_context] => Effect => effect
            value = self.value
            flag = effect.flags & Flags::TRACKING
            effect.flags.unset!(Flags::TRACKING)
            begin
              yield value
            rescue StandardError
              effect.flags |= flag
            end
          end
        end

        def peek = @value

        def value
          if node = Core.add_dependency(self)
            node.version = @version
          end

          @value
        end

        def value=(new_value)
          unless new_value == @value
            Core.cycle_detected! if Root.current.batch_iteration > 100

            @value = new_value
            @version += 1
            Root.current.global_version += 1

            S.batch do
              node = @targets

              while node
                node.target._notify
                node = node.next_target
              end
            end
          end
        end

        def _refresh = true

        def _subscribe(node)
          if @targets != node && node.prev_target.nil?
            node.next_target = @targets
            @targets.prev_target = node if @targets
            @targets = node
          end
        end

        def _unsubscribe(node)
          # Only run the unsubscribe step if the signal has any subscribers to begin with.
          if @targets
            prev_target = node.prev_target
            next_target = node.next_target
            if prev_target
              prev_target.next_target = next_target
              node.prev_target = nil
            end
            if next_target
              next_target.prev_target = prev_target
              node.next_target = nil
            end
            @targets = next_target if node == @targets
          end
        end
      end

      class Computed < Signal
        attr_accessor :sources
        attr_accessor :flags

        def initialize(&compute)
          super(nil)
          @compute = compute
          @sources = nil
          @global_version = Root.current.global_version - 1
          @flags = Flags.new(Flags::OUTDATED)
        end

        def inspect
          @compute.source_location => [file, line]
          "𝙘𝙤𝙢𝙥𝙪𝙩𝙚#{Utils.numbers_to_subscript(@version)}[#{@flags}](#{file}:#{line} 𝚺(#{@value.inspect}))"
        end

        def peek
          Core.cycle_detected! unless _refresh()
          raise @value if @flags.set?(Flags::HAS_ERROR)
          @value
        end

        def value
          Core.cycle_detected! if @flags.set?(Flags::RUNNING)

          node = Core.add_dependency(self)
          self._refresh()

          node.version = @version if node

          raise @value if @flags.set?(Flags::HAS_ERROR)

          @value
        end

        def _refresh
          @flags.unset!(Flags::NOTIFIED)

          return false if @flags.set?(Flags::RUNNING)

          # If this computed signal has subscribed to updates from its dependencies
          # (TRACKING flag set) and none of them have notified about changes (OUTDATED
          # flag not set), then the computed value can't have changed.
          # if (@flags & (Flags::OUTDATED | Flags::TRACKING)) == Flags::TRACKING
          if @flags.set?(Flags::TRACKING)
            return true if @flags.unset?(Flags::OUTDATED)
          end

          @flags.unset!(Flags::OUTDATED)

          return true if @global_version == Root.current.global_version

          @global_version = Root.current.global_version

          # Mark this computed signal running before checking the dependencies for value
          # changes, so that the RUNNING flag can be used to notice cyclical dependencies.
          @flags.set!(Flags::RUNNING)
          if @version > 0 && !Core.needs_to_recompute?(self)
            @flags.unset!(Flags::RUNNING)
            return true
          end

          begin
            Core.prepare_sources(self)

            Core.with_eval_context(self) do
              value = @compute.call

              if @flags.set?(Flags::HAS_ERROR) || @value != value || @version == 0
                @value = value
                @flags.unset!(Flags::HAS_ERROR)
                @version += 1
              end
            rescue => e
              @value = e
              @flags.set!(Flags::HAS_ERROR)
              @version += 1
            end
          ensure
            Core.cleanup_sources(self)
            @flags.unset!(Flags::RUNNING)
          end

          true
        end

        def _subscribe(node)
          unless @targets
            @flags.set!(Flags::OUTDATED | Flags::TRACKING)

            # A computed signal subscribes lazily to its dependencies when the it
            # gets its first subscriber.
            node2 = @sources
            while node2
              node2.source._subscribe(node2)
              node2 = node2.next_source
            end
          end

          super(node)
        end

        def _unsubscribe(node)
          # Only run the unsubscribe step if the computed signal has any subscribers.
          if @targets
            super(node)

            # Computed signal unsubscribes from its dependencies when it loses its last subscriber.
            # This makes it possible for unreferences subgraphs of computed signals to get garbage collected.

            unless @targets
              @flags.unset!(Flags::TRACKING)

              node = @sources

              while node
                node.source._unsubscribe(node)
                node = node.next_source
              end
            end
          end
        end

        def _notify
          unless @flags.set?(Flags::NOTIFIED)
            @flags.set!(Flags::OUTDATED | Flags::NOTIFIED)

            node = @targets

            while node
              node.target._notify
              node = node.next_target
            end
          end
        end
      end

      class CycleDetectedError < StandardError
      end

      def self.cycle_detected! = raise CycleDetectedError

      def self.with_eval_context(eval_context, &) =
        Utils.with_fiber_local(:eval_context, eval_context, &)

      def self.needs_to_recompute?(target)
        # Check the dependencies for changed values. The dependency list is already
        # in order of use. Therefore if multiple dependencies have changed values, only
        # the first used dependency is re-evaluated at this point.
        node = target.sources

        while node
          # If there's a new version of the dependency before or after refreshing,
          # or the dependency has something blocking it from refreshing at all (e.g. a
          # dependency cycle), then we need to recompute.
          if node.source.version != node.version || !node.source._refresh() ||
               node.source.version != node.version
            return true
          end

          node = node.next_source
        end

        # If none of the dependencies have changed values since last recompute then
        # there's no need to recompute.
        return false
      end

      def self.prepare_sources(target)
        # 1. Mark all current sources as re-usable nodes (version: -1)
        # 2. Set a rollback node if the current node is being used in a different context
        # 3. Point 'target._sources' to the tail of the doubly-linked list, e.g:
        #
        #    { undefined <- A <-> B <-> C -> undefined }
        #                   ↑           ↑
        #                   │           └──────┐
        # target._sources = A; (node is head)  │
        #                   ↓                  │
        # target._sources = C; (node is tail) ─┘
        node = target.sources

        while node
          if rollback_node = node.source.node
            node.rollback_node = rollback_node
          end

          node.source.node = node
          node.version = -1

          unless node.next_source
            target.sources = node
            break
          end

          node = node.next_source
        end
      end

      def self.cleanup_sources(target)
        node = target.sources
        head = nil

        # At this point 'target._sources' points to the tail of the doubly-linked list.
        # It contains all existing sources + new sources in order of use.
        # Iterate backwards until we find the head node while dropping old dependencies.

        while node
          prev = node.prev_source

          # The node was not re-used, unsubscribe from its change notifications and remove itself
          # from the doubly-linked list. e.g:
          #
          # { A <-> B <-> C }
          #         ↓
          #    { A <-> C }
          if node.version == -1
            node.source._unsubscribe(node)

            prev.next_source = node.next_source if prev
            node.next_source.prev_source = prev if node.next_source
          else
            # The new head is the last node seen which wasn't removed/unsubscribed
            # from the doubly-linked list. e.g:
            #
            # { A <-> B <-> C }
            #   ↑     ↑     ↑
            #   │     │     └ head = node
            #   │     └ head = node
            #   └ head = node
            head = node
          end

          node.source.node = node.rollback_node
          node.rollback_node = nil if node.rollback_node

          node = prev
        end

        target.sources = head
      end

      def self.cleanup_effect(effect)
        cleanup = effect.cleanup
        effect.cleanup = nil

        if cleanup in Proc
          S.batch do
            # Run cleanup functions always outside of any context.
            Core.with_eval_context(nil) do
              cleanup.call
            rescue StandardError
              effect.flags.unset!(Flags::RUNNING)
              effect.flags.set!(Flags::DISPOSED)
              Core.dispose_effect(effect)
              raise
            end
          end
        end
      end

      def self.dispose_effect(effect)
        node = effect.sources

        while node
          node.source._unsubscribe(node)
          node = node.next_source
        end

        effect.compute = nil
        effect.sources = nil

        Core.cleanup_effect(effect)
      end

      class Effect
        module InspectDispose
          def inspect
            "𝙙𝙞𝙨𝙥𝙤𝙨𝙚(#{receiver.inspect})"
          end
          alias to_s inspect
        end

        def self.create(&)
          effect = new(&)

          begin
            effect._callback
          rescue StandardError
            effect._dispose
            raise
          end

          method = effect.method(:_dispose)
          method.send(:extend, InspectDispose)
          method
        end

        def initialize(&compute)
          @compute = compute
          @cleanup = nil
          @sources = nil
          @next_batched_effect = nil
          @flags = Flags.new(Flags::TRACKING)
        end

        def inspect
          @compute.source_location => [file, line]
          "𝙛𝙭[#{@flags}](#{file}:#{line})"
        end

        attr_accessor :cleanup
        attr_accessor :sources
        attr_accessor :flags
        attr_accessor :compute
        attr_accessor :next_batched_effect

        def _notify
          unless @flags.set?(Flags::NOTIFIED)
            @flags.set!(Flags::NOTIFIED)
            @next_batched_effect = Root.current.batched_effect
            Root.current.batched_effect = self
          end
        end

        def _dispose
          @flags.set!(Flags::DISPOSED)

          Core.dispose_effect(self) unless @flags.set?(Flags::RUNNING)
        end

        def _callback
          Core.cycle_detected! if @flags.set?(Flags::RUNNING)

          @flags.set!(Flags::RUNNING)
          @flags.unset!(Flags::DISPOSED)

          Core.cleanup_effect(self)
          Core.prepare_sources(self)

          S.batch do
            Core.with_eval_context(self) do
              unless @flags.set?(Flags::DISPOSED)
                @cleanup = @compute.call if @compute
              end
            ensure
              Core.cleanup_sources(self)
            end
          ensure
            @flags.unset!(Flags::RUNNING)

            Core.dispose_effect(self) if @flags.set?(Flags::DISPOSED)
          end
        end
      end
    end

    module Helpers
      def root(&) = Core::Root.create(&)

      def batch(&) = Core::Root.current.batch(&)

      def signal(value) = Core::Signal.new(value).proxy
      def computed(&) = Core::Computed.new(&).proxy
      def effect(&) = Core::Effect.create(&)
    end

    module S
      extend Helpers
    end
  end
end
