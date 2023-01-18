require "bundler/setup"
require "minitest/autorun"
require "minitest/hooks/default"
require_relative "../lib/mayu/signals"

S = Mayu::Signals::S

class Spy
  def initialize(&block)
    @block = block
    @called_times = 0
    @return_value = nil
  end

  def to_proc = method(:call).to_proc

  def called_times = @called_times
  def return_value = @return_value
  def reset_history! = @called_times = 0

  def call(...)
    @called_times += 1
    @return_value = @block.call(...)
  end
end

describe "Signals" do
  around { |&block| S.root { super(&block) } }

  describe "Signal" do
    it "should return a value" do
      v = [1, 2]
      s = S.signal(v)
      _(s.value).must_equal(v)
    end

    it "should be an instance of Signal::Proxy" do
      _(S.signal(0)).must_be_instance_of(Mayu::Signals::Core::Signal::Proxy)
    end

    it "should support .to_s" do
      s = S.signal(123)
      assert_equal("123", s.to_s)
    end

    it "should notify other listeners of changes after one listener is disposed" do
      s = S.signal(0)
      spy1 = Spy.new { s.value }
      spy2 = Spy.new { s.value }
      spy3 = Spy.new { s.value }

      S.effect(&spy1)

      dispose = S.effect(&spy2)
      S.effect(&spy3)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(1, spy3.called_times)

      dispose.call

      s.value = 1

      assert_equal(2, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(2, spy3.called_times)
    end

    describe "peek()" do
      it "should get a value" do
        s = S.signal(1)
        _(s.peek).must_equal(1)
      end

      it "should get the updated value after a value change" do
        s = S.signal(1)
        s.value = 2
        _(s.peek).must_equal(2)
      end

      it "should not make the surrounding effect depend on the signal" do
        s = S.signal(1)
        spy = Spy.new { s.peek }

        S.effect(&spy)
        assert_equal(1, spy.called_times)

        s.value = 2
        assert_equal(1, spy.called_times)
      end

      it "should not make the surrounding computed signal depend on the signal" do
        s = S.signal(1)
        spy = Spy.new { s.peek }

        d = S.computed(&spy)

        d.value
        assert_equal(1, spy.called_times)

        s.value = 2
        d.value
        assert_equal(1, spy.called_times)
      end
    end

    describe "subscribe()" do
      it "should subscribe to a signal" do
        spy = Spy.new {}
        a = S.signal(1)
        a.subscribe(&spy)
        assert(1, spy.called_times)
      end

      it "should unsubscribe from a signal" do
        spy = Spy.new {}
        a = S.signal(1)

        dispose = a.subscribe(&spy)
        dispose.call

        spy.reset_history!

        a.value = 2
        assert(0, spy.called_times)
      end

      it "should not start triggering on when a signal accessed in the callback changes" do
        spy = Spy.new {}
        a = S.signal(0)
        b = S.signal(0)

        a.subscribe do
          b.value
          spy.call
        end

        assert_equal(1, spy.called_times)
        spy.reset_history!

        b.value += 1

        assert_equal(0, spy.called_times)
      end

      it "should not cause surrounding effect to subscribe to changes to a signal accessed in the callback" do
        spy = Spy.new {}
        a = S.signal(0)
        b = S.signal(0)

        S.effect do
          a.subscribe { b.value }
          spy.call
        end

        assert_equal(1, spy.called_times)
        spy.reset_history!

        b.value += 1

        assert_equal(0, spy.called_times)
      end
    end
  end

  describe "S.effect()" do
    it "should init with value" do
      s = S.signal(123)
      spy = Spy.new {}
      a = S.signal(0)
      b = S.signal(0)

      S.effect do
        a.subscribe { b.value }
        spy.call
      end

      assert_equal(1, spy.called_times)
      spy.reset_history!

      b.value += 1

      assert_equal(0, spy.called_times)
    end

    it "should subscribe to signals" do
      s = S.signal(123)
      spy = Spy.new { s.value }
      S.effect(&spy)
      spy.reset_history!

      s.value = 42
      assert_equal(1, spy.called_times)
      assert_equal(42, spy.return_value)
    end

    it "should subscribe to multiple signals" do
      a = S.signal("a")
      b = S.signal("b")
      spy = Spy.new { a.value + " " + b.value }
      S.effect(&spy)
      spy.reset_history!

      a.value = "aa"
      b.value = "bb"
      assert_equal("aa bb", spy.return_value)
    end

    it "should dispose of subscriptions" do
      a = S.signal("a")
      b = S.signal("b")
      spy = Spy.new { a.value + " " + b.value }
      dispose = S.effect(&spy)
      spy.reset_history!

      dispose.call
      assert_equal(0, spy.called_times)

      a.value = "aa"
      b.value = "bb"

      assert_equal(0, spy.called_times)
    end

    it "should unsubscribe from signal" do
      s = S.signal(123)
      spy = Spy.new { s.value }
      unsub = S.effect(&spy)
      spy.reset_history!

      unsub.call
      s.value = 42

      assert_equal(0, spy.called_times)
    end

    it "should conditionally unsubscribe from signals" do
      a = S.signal("a")
      b = S.signal("b")
      cond = S.signal(true)

      spy = Spy.new do
        cond.value ? a.value : b.value
      end

      S.effect(&spy)
      assert_equal(1, spy.called_times)

      b.value = "bb"
      assert_equal(1, spy.called_times)

      cond.value = false
      assert_equal(2, spy.called_times)

      spy.reset_history!

      a.value = "aaa"
      assert_equal(0, spy.called_times)
    end

    # it "should batch writes" do
    #   a = S.signal("a")
    #   spy = Spy.new { a.value }
    #   S.effect(&spy)
    #   spy.reset_history!
    #
    #   S.effect do
    #     a.value = "aa"
    #     a.value = "aaa"
    #   end
    #
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should call the cleanup callback before the next run" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   S.effect do
    #     a.value
    #     return spy
    #   end
    #   assert_equal(0, spy.called_times)
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   a.value = 2
    #   expect(spy).to.be.calledTwice
    # end
    #
    # it "should call only the callback from the previous run" do
    #   spy1 = Spy.new {}
    #   spy2 = Spy.new {}
    #   spy3 = Spy.new {}
    #   a = S.signal(spy1)
    #
    #   S.effect do
    #     return a.value
    #   end
    #
    #   assert_equal(0, spy1.called_times)
    #   assert_equal(0, spy2.called_times)
    #   assert_equal(0, spy3.called_times)
    #
    #   a.value = spy2
    #   assert_equal(1, spy1.called_times)
    #   assert_equal(0, spy2.called_times)
    #   assert_equal(0, spy3.called_times)
    #
    #   a.value = spy3
    #   assert_equal(1, spy1.called_times)
    #   assert_equal(1, spy2.called_times)
    #   assert_equal(0, spy3.called_times)
    # end
    #
    # it "should call the cleanup callback function when disposed" do
    #   spy = Spy.new {}
    #
    #   dispose = S.effect do
    #     return spy
    #   end
    #   assert_equal(0, spy.called_times)
    #   dispose()
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should not recompute if the effect has been notified about changes, but no direct dependency has actually changed" do
    #   s = S.signal(0)
    #   c = S.computed do
    #     s.value
    #     return 0
    #   end
    #   spy = sinon.spy( do
    #     c.value
    #   end
    #   S.effect(&spy)
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   s.value = 1
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should not recompute dependencies unnecessarily" do
    #   spy = Spy.new {}
    #   a = S.signal(0)
    #   b = S.signal(0)
    #   c = S.computed do
    #     b.value
    #     spy()
    #   end
    #   S.effect do
    #     if a.value == 0
    #       c.value
    #     end
    #   end
    #   assert_equal(1, spy.called_times)
    #
    #   S.batch do
    #     b.value = 1
    #     a.value = 1
    #   end
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should not recompute dependencies out of order" do
    #   a = S.signal(1)
    #   b = S.signal(1)
    #   c = S.signal(1)
    #
    #   spy = Spy.new { c.value }
    #   d = computed(spy)
    #
    #   S.effect do
    #     if a.value > 0
    #       b.value
    #       d.value
    #     } else {
    #       b.value
    #     end
    #   end
    #   spy.reset_history!
    #
    #   S.batch do
    #     a.value = 2
    #     b.value = 2
    #     c.value = 2
    #   end
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   S.batch do
    #     a.value = -1
    #     b.value = -1
    #     c.value = -1
    #   end
    #   assert_equal(0, spy.called_times)
    #   spy.reset_history!
    # end
    #
    # it "should recompute if a dependency changes during computation after becoming a dependency" do
    #   a = S.signal(0)
    #   spy = sinon.spy( do
    #     if a.value == 0
    #       a.value += 1
    #     end
    #   end
    #   S.effect(&spy)
    #   expect(spy).to.be.calledTwice
    # end
    #
    # it "should run the cleanup in an implicit batch" do
    #   a = S.signal(0)
    #   b = S.signal("a")
    #   c = S.signal("b")
    #   spy = Spy.new {}
    #
    #   S.effect do
    #     b.value
    #     c.value
    #     spy(b.value + c.value)
    #   end
    #
    #   S.effect do
    #     a.value
    #     return  do
    #       b.value = "x"
    #       c.value = "y"
    #     end
    #   end
    #
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   expect(spy).to.be.calledWith("xy")
    # end
    #
    # it "should not retrigger the effect if the cleanup modifies one of the dependencies" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   S.effect do
    #     spy(a.value)
    #     return  do
    #       a.value = 2
    #     end
    #   end
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   expect(spy).to.be.calledWith(2)
    # end
    #
    # it "should run the cleanup if the effect disposes itself" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   dispose = S.effect do
    #     if a.value > 0
    #       dispose()
    #       return spy
    #     end
    #   end
    #   assert_equal(0, spy.called_times)
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   a.value = 2
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should not run the effect if the cleanup function disposes it" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   dispose = S.effect do
    #     a.value
    #     spy()
    #     return  do
    #       dispose()
    #     end
    #   end
    #   assert_equal(1, spy.called_times)
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should not subscribe to anything if first run throws" do
    #   s = S.signal(0)
    #   spy = sinon.spy( do
    #     s.value
    #     raise "test"
    #   end
    #   expect(() => S.effect(&spy)).to.throw("test")
    #   assert_equal(1, spy.called_times)
    #
    #   s.value += 1
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should reset the cleanup if the effect throws" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   S.effect do
    #     if a.value == 0
    #       return spy
    #     } else {
    #       raise "hello"
    #     end
    #   end
    #   assert_equal(0, spy.called_times)
    #   expect(() => (a.value = 1)).to.throw("hello")
    #   assert_equal(1, spy.called_times)
    #   a.value = 0
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should dispose the effect if the cleanup callback throws" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #
    #   S.effect do
    #     if a.value == 0
    #       return  do
    #         raise "hello"
    #       end
    #     } else {
    #       spy()
    #     end
    #   end
    #   assert_equal(0, spy.called_times)
    #   expect(() => a.value++).to.throw("hello")
    #   assert_equal(0, spy.called_times)
    #   a.value += 1
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should run cleanups outside any evaluation context" do
    #   spy = Spy.new {}
    #   a = S.signal(0)
    #   b = S.signal(0)
    #   c = S.computed do
    #     if a.value == 0
    #       S.effect do
    #         return  do
    #           b.value
    #         end
    #       end
    #     end
    #     return a.value
    #   end
    #
    #   S.effect do
    #     spy()
    #     c.value
    #   end
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   spy.reset_history!
    #
    #   b.value = 1
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should throw on cycles" do
    #   a = S.signal(0)
    #   i = 0
    #
    #   fn = () =>
    #     S.effect do
    #       // Prevent test suite from spinning if limit is not hit
    #       if i++ > 200
    #         raise "test failed"
    #       end
    #       a.value
    #       a.value = NaN
    #     end
    #
    #   expect(fn).to.throw(/Cycle detected/)
    # end
    #
    # it "should throw on indirect cycles" do
    #   a = S.signal(0)
    #   i = 0
    #
    #   c = S.computed do
    #     a.value
    #     a.value = NaN
    #     return NaN
    #   end
    #
    #   fn = () =>
    #     S.effect do
    #       // Prevent test suite from spinning if limit is not hit
    #       if i++ > 200
    #         raise "test failed"
    #       end
    #       c.value
    #     end
    #
    #   expect(fn).to.throw(/Cycle detected/)
    # end
    #
    # it "should allow disposing the effect multiple times" do
    #   dispose = S.effect { undefined }
    #   dispose()
    #   expect(() => dispose()).not.to.throw()
    # end
    #
    # it "should allow disposing a running effect" do
    #   a = S.signal(0)
    #   spy = Spy.new {}
    #   dispose = S.effect do
    #     if a.value == 1
    #       dispose()
    #       spy()
    #     end
    #   end
    #   assert_equal(0, spy.called_times)
    #   a.value = 1
    #   assert_equal(1, spy.called_times)
    #   a.value = 2
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should not run if it's first been triggered and then disposed in a batch" do
    #   a = S.signal(0)
    #   spy = Spy.new { a.value }
    #   dispose = S.effect(&spy)
    #   spy.reset_history!
    #
    #   S.batch do
    #     a.value = 1
    #     dispose()
    #   end
    #
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should not run if it's been triggered, disposed and then triggered again in a batch" do
    #   a = S.signal(0)
    #   spy = Spy.new { a.value }
    #   dispose = S.effect(&spy)
    #   spy.reset_history!
    #
    #   S.batch do
    #     a.value = 1
    #     dispose()
    #     a.value = 2
    #   end
    #
    #   assert_equal(0, spy.called_times)
    # end
  end

  describe "internals" do
    # Test internal behavior depended on by Preact & React integrations
    # it "should pass in the effect instance in callback's `this`" do
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #   expect(typeof e._start).to.equal("function")
    #   expect(typeof e._dispose).to.equal("function")
    # end
    #
    # it "should allow setting _callback that replaces the default functionality" do
    #   a = S.signal(0)
    #   oldSpy = Spy.new {}
    #   newSpy = Spy.new {}
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #     a.value
    #     oldSpy()
    #   end
    #   oldSpy.reset_history!
    #
    #   e._callback = newSpy
    #   a.value = 1
    #
    #   assert_equal(0, oldSpy.called_times)
    #   expect(newSpy).to.be.called
    # end
    #
    # it "should return a function for closing the effect scope from _start" do
    #   s = S.signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #
    #   done1 = e._start()
    #   s.value
    #   done1()
    #   assert_equal(0, spy.called_times)
    #
    #   s.value = 2
    #   expect(spy).to.be.called
    #   spy.reset_history!
    #
    #   done2 = e._start()
    #   done2()
    #
    #   s.value = 3
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should throw on out-of-order start1-start2-end1 sequences" do
    #   e1: any
    #   effect(function (this: any) {
    #     e1 = this
    #   end
    #
    #   e2: any
    #   effect(function (this: any) {
    #     e2 = this
    #   end
    #
    #   done1 = e1._start()
    #   done2 = e2._start()
    #   begin)
    #     expect(() => done1()).to.throw(/Out-of-order/)
    #   } finally {
    #     done2()
    #     done1()
    #   end
    # end
    #
    # it "should throw a cycle detection error when _start is called while the effect is running" do
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   done = e._start()
    #   begin)
    #     expect(() => e._start()).to.throw(/Cycle detected/)
    #   } finally {
    #     done()
    #   end
    # end
    #
    # it "should dispose the effect on _dispose" do
    #   s = S.signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #
    #   done = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done()
    #   end
    #   assert_equal(0, spy.called_times)
    #
    #   s.value = 2
    #   expect(spy).to.be.called
    #   spy.reset_history!
    #
    #   e._dispose()
    #   s.value = 3
    #   assert_equal(0, spy.called_times)
    # end
    #
    # it "should allow reusing the effect after disposing it" do
    #   s = S.signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #
    #   spy = Spy.new {}
    #   e._callback = spy
    #   e._dispose()
    #
    #   done = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done()
    #   end
    #   s.value = 2
    #   expect(spy).to.be.called
    # end
    #
    # it "should have property _sources that is undefined when and only when the effect has no sources" do
    #   s = S.signal(0)
    #
    #   e: any
    #   effect(function (this: any) {
    #     e = this
    #   end
    #   assert_nil(e._sources)
    #
    #   done1 = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done1()
    #   end
    #   expect(e._sources).not.to.be.undefined
    #
    #   done2 = e._start()
    #   done2()
    #   assert_nil(e._sources)
    #
    #   done3 = e._start()
    #   begin)
    #     s.value
    #   } finally {
    #     done3()
    #   end
    #   expect(e._sources).not.to.be.undefined
    #
    #   e._dispose()
    #   assert_nil(e._sources)
    # end
  end

  describe "S.computed()" do
    it "should return value" do
      a = S.signal("a")
      b = S.signal("b")
      c = S.computed { a.value + b.value }
      assert_equal("ab", c.value)
    end

    it "should return updated value" do
      a = S.signal("a")
      b = S.signal("b")

      c = S.computed { a.value + b.value }
      assert_equal("ab", c.value)

      a.value = "aa"
      assert_equal("aab", c.value)
    end

    it "should conditionally unsubscribe from signals" do
      a = S.signal("a")
      b = S.signal("b")
      cond = S.signal(true)

      spy = Spy.new { cond.value ? a.value : b.value }

      c = S.computed(&spy)
      assert_equal("a", c.value)
      assert_equal(1, spy.called_times)

      b.value = "bb"
      assert_equal("a", c.value)
      assert_equal(1, spy.called_times)

      cond.value = false
      assert_equal("bb", c.value)
      assert_equal(2, spy.called_times)

      spy.reset_history!

      a.value = "aaa"
      assert_equal("bb", c.value)
      assert_equal(0, spy.called_times)
    end

    it "should consider undefined value from the uninitialized value" do
      # Does this test make any sense? a is not used?
      a = S.signal(0)
      spy = Spy.new { nil }
      c = S.computed(&spy)

      assert_nil(c.value)
      a.value = 1
      assert_nil(c.value)
      assert_equal(1, spy.called_times)
    end

    it "should not leak errors raised by dependencies" do
      a = S.signal(0)
      b =
        S.computed do
          a.value
          raise
        end
      c =
        S.computed do
          b.value
        rescue StandardError
          "ok"
        end
      assert_equal("ok", c.value)
      a.value = 1
      assert_equal("ok", c.value)
    end

    it "should propagate notifications even right after first subscription" do
      a = S.signal(0)
      b = S.computed { a.value }
      c = S.computed { b.value }
      c.value

      spy = Spy.new { c.value }

      S.effect(&spy)
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = 1
      assert_equal(1, spy.called_times)
    end

    it "should get marked as outdated right after first subscription" do
      s = S.signal(0)
      c = S.computed { s.value }
      c.value

      s.value = 1
      S.effect { c.value }
      assert_equal(1, c.value)
    end

    it "should propagate notification to other listeners after one listener is disposed" do
      s = S.signal(0)
      c = S.computed { s.value }

      spy1 = Spy.new { c.value }
      spy2 = Spy.new { c.value }
      spy3 = Spy.new { c.value }

      S.effect(&spy1)
      dispose = S.effect(&spy2)
      S.effect(&spy3)

      assert_equal(1, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(1, spy3.called_times)

      dispose.call

      s.value = 1
      assert_equal(2, spy1.called_times)
      assert_equal(1, spy2.called_times)
      assert_equal(2, spy3.called_times)
    end

    it "should not recompute dependencies out of order" do
      a = S.signal(1)
      b = S.signal(1)
      c = S.signal(1)

      spy = Spy.new { c.value }
      d = S.computed(&spy)

      e =
        S.computed do
          if a.value > 0
            b.value
            d.value
          else
            b.value
          end
        end

      e.value
      spy.reset_history!

      a.value = 2
      b.value = 2
      c.value = 2
      e.value
      assert_equal(1, spy.called_times)
      spy.reset_history!

      a.value = -1
      b.value = -1
      c.value = -1
      e.value
      assert_equal(0, spy.called_times)
      spy.reset_history!
    end

    it "should not recompute dependencies unnecessarily" do
      spy = Spy.new {}
      a = S.signal(0)
      b = S.signal(0)
      c =
        S.computed do
          b.value
          spy.call
        end
      d = S.computed { c.value if a.value.zero? }
      d.value
      assert_equal(1, spy.called_times)

      S.batch do
        b.value = 1
        a.value = 1
      end
      d.value
      assert_equal(1, spy.called_times)
    end

    describe "peek()" do
      it "should get value" do
        s = S.signal(1)
        c = S.computed { s.value }
        assert_equal(1, c.peek)
      end

      # it "should refresh value if stale" do
      #   a = S.signal(1)
      #   b = S.computed { a.value }
      #   assert_equal(1, b.peek)
      #
      #   a.value = 2
      #   assert_equal(2, b.peek)
      # end
      #
      # it "should detect simple dependency cycles" do
      #   a: Signal = S.computed { a.peek }
      #   expect(() => a.peek).to.throw(/Cycle detected/)
      # end
      #
      # it "should detect deep dependency cycles" do
      #   a: Signal = S.computed { b.value }
      #   b: Signal = S.computed { c.value }
      #   c: Signal = S.computed { d.value }
      #   d: Signal = S.computed { a.peek }
      #   expect(() => a.peek).to.throw(/Cycle detected/)
      # end
      #
      # it "should not make surrounding effect depend on the computed" do
      #   s = S.signal(1)
      #   c = S.computed { s.value }
      #   spy = sinon.spy( do
      #     c.peek()
      #   end
      #
      #   S.effect(&spy)
      #   assert_equal(1, spy.called_times)
      #
      #   s.value = 2
      #   assert_equal(1, spy.called_times)
      # end
      #
      # it "should not make surrounding computed depend on the computed" do
      #   s = S.signal(1)
      #   c = S.computed { s.value }
      #
      #   spy = sinon.spy( do
      #     c.peek()
      #   end
      #
      #   d = computed(spy)
      #   d.value
      #   assert_equal(1, spy.called_times)
      #
      #   s.value = 2
      #   d.value
      #   assert_equal(1, spy.called_times)
      # end
      #
      # it "should not make surrounding effect depend on the peeked computed's dependencies" do
      #   a = S.signal(1)
      #   b = S.computed { a.value }
      #   spy = Spy.new {}
      #   S.effect do
      #     spy()
      #     b.peek()
      #   end
      #   assert_equal(1, spy.called_times)
      #   spy.reset_history!
      #
      #   a.value = 1
      #   assert_equal(0, spy.called_times)
      # end
      #
      # it "should not make surrounding computed depend on peeked computed's dependencies" do
      #   a = S.signal(1)
      #   b = S.computed { a.value }
      #   spy = Spy.new {}
      #   d = S.computed do
      #     spy()
      #     b.peek()
      #   end
      #   d.value
      #   assert_equal(1, spy.called_times)
      #   spy.reset_history!
      #
      #   a.value = 1
      #   d.value
      #   assert_equal(0, spy.called_times)
      # end
    end

    describe "garbage collection" do
      # // Skip GC tests if window.gc/global.gc is not defined.
      # before(function () {
      #   if typeof gc == "undefined"
      #     this.skip()
      #   end
      # end
      #
      # it "should be garbage collectable if nothing is listening to its changes", async  do
      #   s = S.signal(0)
      #   ref = new WeakRef(computed(() => s.value))
      #
      #   (gc as () => void)()
      #   await new Promise(resolve => setTimeout(resolve, 0))
      #   expect(ref.deref()).to.be.undefined
      # end
      #
      # it "should be garbage collectable after it has lost all of its listeners", async  do
      #   s = S.signal(0)
      #
      #   ref: WeakRef<Signal>
      #   dispose: () => void
      #   (function () {
      #     c = S.computed { s.value }
      #     ref = new WeakRef(c)
      #     dispose = S.effect { c.value }
      #   })()
      #
      #   dispose()
      #   (gc as () => void)()
      #   await new Promise(resolve => setTimeout(resolve, 0))
      #   expect(ref.deref()).to.be.undefined
      # end
    end

    describe "graph updates" do
      # it "should run computeds once for multiple dep changes", async  do
      #   a = S.signal("a")
      #   b = S.signal("b")
      #
      #   compute = sinon.spy( do
      #     // debugger
      #     return a.value + b.value
      #   end
      #   c = computed(compute)
      #
      #   assert_equal("ab", c.value)
      #   expect(compute).to.have.been.calledOnce
      #   compute.reset_history!
      #
      #   a.value = "aa"
      #   b.value = "bb"
      #   c.value
      #   expect(compute).to.have.been.calledOnce
      # end
      #
      # it "should drop A->B->A updates", async  do
      #   //     A
      #   //   / |
      #   //  B  | <- Looks like a flag doesn't it? :D
      #   //   \ |
      #   //     C
      #   //     |
      #   //     D
      #   a = S.signal(2)
      #
      #   b = S.computed { a.value - 1 }
      #   c = S.computed { a.value + b.value }
      #
      #   compute = Spy.new { "d: " + c.value }
      #   d = computed(compute)
      #
      #   // Trigger read
      #   assert_equal("d: 3", d.value)
      #   expect(compute).to.have.been.calledOnce
      #   compute.reset_history!
      #
      #   a.value = 4
      #   d.value
      #   expect(compute).to.have.been.calledOnce
      # end
      #
      # it "should only update every signal once (diamond graph)" do
      #   // In this scenario "D" should only update once when "A" receives
      #   // an update. This is sometimes referred to as the "diamond" scenario.
      #   //     A
      #   //   /   \
      #   //  B     C
      #   //   \   /
      #   //     D
      #   a = S.signal("a")
      #   b = S.computed { a.value }
      #   c = S.computed { a.value }
      #
      #   spy = Spy.new { b.value + " " + c.value }
      #   d = computed(spy)
      #
      #   assert_equal("a a", d.value)
      #   assert_equal(1, spy.called_times)
      #
      #   a.value = "aa"
      #   assert_equal("aa aa", d.value)
      #   expect(spy).to.be.calledTwice
      # end
      #
      # it "should only update every signal once (diamond graph + tail)" do
      #   // "E" will be likely updated twice if our mark+sweep logic is buggy.
      #   //     A
      #   //   /   \
      #   //  B     C
      #   //   \   /
      #   //     D
      #   //     |
      #   //     E
      #   a = S.signal("a")
      #   b = S.computed { a.value }
      #   c = S.computed { a.value }
      #
      #   d = S.computed { b.value + " " + c.value }
      #
      #   spy = Spy.new { d.value }
      #   e = computed(spy)
      #
      #   assert_equal("a a", e.value)
      #   assert_equal(1, spy.called_times)
      #
      #   a.value = "aa"
      #   assert_equal("aa aa", e.value)
      #   expect(spy).to.be.calledTwice
      # end
      #
      # it "should bail out if result is the same" do
      #   // Bail out if value of "B" never changes
      #   // A->B->C
      #   a = S.signal("a")
      #   b = S.computed do
      #     a.value
      #     return "foo"
      #   end
      #
      #   spy = Spy.new { b.value }
      #   c = computed(spy)
      #
      #   assert_equal("foo", c.value)
      #   assert_equal(1, spy.called_times)
      #
      #   a.value = "aa"
      #   assert_equal("foo", c.value)
      #   assert_equal(1, spy.called_times)
      # end
      #
      # it "should only update every signal once (jagged diamond graph + tails)" do
      #   // "F" and "G" will be likely updated twice if our mark+sweep logic is buggy.
      #   //     A
      #   //   /   \
      #   //  B     C
      #   //  |     |
      #   //  |     D
      #   //   \   /
      #   //     E
      #   //   /   \
      #   //  F     G
      #   a = S.signal("a")
      #
      #   b = S.computed { a.value }
      #   c = S.computed { a.value }
      #
      #   d = S.computed { c.value }
      #
      #   eSpy = Spy.new { b.value + " " + d.value }
      #   e = computed(eSpy)
      #
      #   fSpy = Spy.new { e.value }
      #   f = computed(fSpy)
      #   gSpy = Spy.new { e.value }
      #   g = computed(gSpy)
      #
      #   assert_equal("a a", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("a a", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   eSpy.reset_history!
      #   fSpy.reset_history!
      #   gSpy.reset_history!
      #
      #   a.value = "b"
      #
      #   assert_equal("b b", e.value)
      #   assert_equal(1, eSpy.called_times)
      #
      #   assert_equal("b b", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("b b", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   eSpy.reset_history!
      #   fSpy.reset_history!
      #   gSpy.reset_history!
      #
      #   a.value = "c"
      #
      #   assert_equal("c c", e.value)
      #   assert_equal(1, eSpy.called_times)
      #
      #   assert_equal("c c", f.value)
      #   assert_equal(1, fSpy.called_times)
      #
      #   assert_equal("c c", g.value)
      #   assert_equal(1, gSpy.called_times)
      #
      #   // top to bottom
      #   expect(eSpy).to.have.been.calledBefore(fSpy)
      #   // left to right
      #   expect(fSpy).to.have.been.calledBefore(gSpy)
      # end
      #
      # it "should only subscribe to signals listened to" do
      #   //    *A
      #   //   /   \
      #   // *B     C <- we don't listen to C
      #   a = S.signal("a")
      #
      #   b = S.computed { a.value }
      #   spy = Spy.new { a.value }
      #   computed(spy)
      #
      #   assert_equal("a", b.value)
      #   assert_equal(0, spy.called_times)
      #
      #   a.value = "aa"
      #   assert_equal("aa", b.value)
      #   assert_equal(0, spy.called_times)
      # end
      #
      # it "should only subscribe to signals listened to" do
      #   // Here both "B" and "C" are active in the beginning, but
      #   // "B" becomes inactive later. At that point it should
      #   // not receive any updates anymore.
      #   //    *A
      #   //   /   \
      #   // *B     D <- we don't listen to C
      #   //  |
      #   // *C
      #   a = S.signal("a")
      #   spyB = Spy.new { a.value }
      #   b = computed(spyB)
      #
      #   spyC = Spy.new { b.value }
      #   c = computed(spyC)
      #
      #   d = S.computed { a.value }
      #
      #   result = ""
      #   unsub = S.effect { (result = c.value })
      #
      #   assert_equal("a", result)
      #   assert_equal("a", d.value)
      #
      #   spyB.reset_history!
      #   spyC.reset_history!
      #   unsub()
      #
      #   a.value = "aa"
      #
      #   assert_equal(0, spyB.called_times)
      #   assert_equal(0, spyC.called_times)
      #   assert_equal("aa", d.value)
      # end
      #
      # it "should ensure subs update even if one dep unmarks it" do
      #   // In this scenario "C" always returns the same value. When "A"
      #   // changes, "B" will update, then "C" at which point its update
      #   // to "D" will be unmarked. But "D" must still update because
      #   // "B" marked it. If "D" isn't updated, then we have a bug.
      #   //     A
      #   //   /   \
      #   //  B     *C <- returns same value every time
      #   //   \   /
      #   //     D
      #   a = S.signal("a")
      #   b = S.computed { a.value }
      #   c = S.computed do
      #     a.value
      #     return "c"
      #   end
      #   spy = Spy.new { b.value + " " + c.value }
      #   d = computed(spy)
      #   assert_equal("a c", d.value)
      #   spy.reset_history!
      #
      #   a.value = "aa"
      #   d.value
      #   expect(spy).to.returned("aa c")
      # end
      #
      # it "should ensure subs update even if two deps unmark it" do
      #   // In this scenario both "C" and "D" always return the same
      #   // value. But "E" must still update because "A"  marked it.
      #   // If "E" isn't updated, then we have a bug.
      #   //     A
      #   //   / | \
      #   //  B *C *D
      #   //   \ | /
      #   //     E
      #   a = S.signal("a")
      #   b = S.computed { a.value }
      #   c = S.computed do
      #     a.value
      #     return "c"
      #   end
      #   d = S.computed do
      #     a.value
      #     return "d"
      #   end
      #   spy = Spy.new { b.value + " " + c.value + " " + d.value }
      #   e = computed(spy)
      #   assert_equal("a c d", e.value)
      #   spy.reset_history!
      #
      #   a.value = "aa"
      #   e.value
      #   expect(spy).to.returned("aa c d")
      # end
    end
    describe "error handling" do
      # it "should throw when writing to computeds" do
      #   a = S.signal("a")
      #   b = S.computed { a.value }
      #   fn = () => ((b as Signal).value = "aa")
      #   expect(fn).to.throw(/Cannot set property value/)
      # end
      #
      # it "should keep graph consistent on errors during activation" do
      #   a = S.signal(0)
      #   b = S.computed do
      #     raise "fail"
      #   end
      #   c = S.computed { a.value }
      #   expect(() => b.value).to.throw("fail")
      #
      #   a.value = 1
      #   assert_equal(1, c.value)
      # end
      #
      # it "should keep graph consistent on errors in computeds" do
      #   a = S.signal(0)
      #   b = S.computed do
      #     if (a.value == 1) raise "fail"
      #     return a.value
      #   end
      #   c = S.computed { b.value }
      #   assert_equal(0, c.value)
      #
      #   a.value = 1
      #   expect(() => b.value).to.throw("fail")
      #
      #   a.value = 2
      #   assert_equal(2, c.value)
      # end
      #
      # it "should support lazy branches" do
      #   a = S.signal(0)
      #   b = S.computed { a.value }
      #   c = S.computed { (a.value > 0 ? a.value : b.value })
      #
      #   assert_equal(0, c.value)
      #   a.value = 1
      #   assert_equal(1, c.value)
      #
      #   a.value = 0
      #   assert_equal(0, c.value)
      # end
      #
      # it "should not update a sub if all deps unmark it" do
      #   // In this scenario "B" and "C" always return the same value. When "A"
      #   // changes, "D" should not update.
      #   //     A
      #   //   /   \
      #   // *B     *C
      #   //   \   /
      #   //     D
      #   a = S.signal("a")
      #   b = S.computed do
      #     a.value
      #     return "b"
      #   end
      #   c = S.computed do
      #     a.value
      #     return "c"
      #   end
      #   spy = Spy.new { b.value + " " + c.value }
      #   d = computed(spy)
      #   assert_equal("b c", d.value)
      #   spy.reset_history!
      #
      #   a.value = "aa"
      #   assert_equal(0, spy.called_times)
      # end
    end
  end

  describe "batch/transaction" do
    # it "should return the value from the callback" do
    #   expect(batch() => 1)).to.equal(1)
    # end
    #
    # it "should throw errors thrown from the callback" do
    #   expect(() =>
    #     S.batch do
    #       raise "hello"
    #     end
    #   ).to.throw("hello")
    # end
    #
    # it "should throw non-errors thrown from the callback" do
    #   begin)
    #     S.batch do
    #       throw undefined
    #     end
    #     expect.fail()
    #   rescue => err
    #     assert_nil(err)
    #   end
    # end
    #
    # it "should delay writes" do
    #   a = S.signal("a")
    #   b = S.signal("b")
    #   spy = Spy.new { a.value + " " + b.value }
    #   S.effect(&spy)
    #   spy.reset_history!
    #
    #   S.batch do
    #     a.value = "aa"
    #     b.value = "bb"
    #   end
    #
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should delay writes until outermost batch is complete" do
    #   a = S.signal("a")
    #   b = S.signal("b")
    #   spy = Spy.new { a.value + ", " + b.value }
    #   S.effect(&spy)
    #   spy.reset_history!
    #
    #   S.batch do
    #     S.batch do
    #       a.value += " inner"
    #       b.value += " inner"
    #     end
    #     a.value += " outer"
    #     b.value += " outer"
    #   end
    #
    #   // If the inner batch) would have flushed the update
    #   // this spy would've been called twice.
    #   assert_equal(1, spy.called_times)
    # end
    #
    # it "should read signals written to" do
    #   a = S.signal("a")
    #
    #   result = ""
    #   S.batch do
    #     a.value = "aa"
    #     result = a.value
    #   end
    #
    #   assert_equal("aa", result)
    # end
    #
    # it "should read computed signals with updated source signals" do
    #   // A->B->C->D->E
    #   a = S.signal("a")
    #   b = S.computed { a.value }
    #
    #   spyC = Spy.new { b.value }
    #   c = computed(spyC)
    #
    #   spyD = Spy.new { c.value }
    #   d = computed(spyD)
    #
    #   spyE = Spy.new { d.value }
    #   e = computed(spyE)
    #
    #   spyC.reset_history!
    #   spyD.reset_history!
    #   spyE.reset_history!
    #
    #   result = ""
    #   S.batch do
    #     a.value = "aa"
    #     result = c.value
    #
    #     // Since "D" isn't accessed during batching, we should not
    #     // update it, only after batching has completed
    #     assert_equal(0, spyD.called_times)
    #   end
    #
    #   assert_equal("aa", result)
    #   assert_equal("aa", d.value)
    #   assert_equal("aa", e.value)
    #   assert_equal(1, spyC.called_times)
    #   assert_equal(1, spyD.called_times)
    #   assert_equal(1, spyE.called_times)
    # end
    #
    # it "should not block writes after batching completed" do
    #   // If no further writes after batch) are possible, than we
    #   // didn't restore state properly. Most likely "pending" still
    #   // holds elements that are already processed.
    #   a = S.signal("a")
    #   b = S.signal("b")
    #   c = S.signal("c")
    #   d = S.computed { a.value + " " + b.value + " " + c.value }
    #
    #   result
    #   S.effect { (result = d.value })
    #
    #   S.batch do
    #     a.value = "aa"
    #     b.value = "bb"
    #   end
    #   c.value = "cc"
    #   assert_equal("aa bb cc", result)
    # end
    #
    # it "should not lead to stale signals with .value in batch" do
    #   invokes: number[][] = []
    #   counter = S.signal(0)
    #   double = S.computed { counter.value * 2 }
    #   triple = S.computed { counter.value * 3 }
    #
    #   S.effect do
    #     invokes.push([double.value, triple.value])
    #   end
    #
    #   assert_equal([[0, 0]], invokes)
    #
    #   S.batch do
    #     counter.value = 1
    #     assert_equal(2, double.value)
    #   end
    #
    #   assert_equal([2, 3], invokes[1])
    # end
    #
    # it "should not lead to stale signals with peek() in batch" do
    #   invokes: number[][] = []
    #   counter = S.signal(0)
    #   double = S.computed { counter.value * 2 }
    #   triple = S.computed { counter.value * 3 }
    #
    #   S.effect do
    #     invokes.push([double.value, triple.value])
    #   end
    #
    #   assert_equal([[0, 0]], invokes)
    #
    #   S.batch do
    #     counter.value = 1
    #     assert_equal(2, double.peek)
    #   end
    #
    #   assert_equal([2, 3], invokes[1])
    # end
    #
    # it "should run pending effects even if the callback throws" do
    #   a = S.signal(0)
    #   b = S.signal(1)
    #   spy1 = Spy.new { a.value }
    #   spy2 = Spy.new { b.value }
    #   S.effect(&spy1)
    #   S.effect(&spy2)
    #   spy1.reset_history!
    #   spy2.reset_history!
    #
    #   expect(() =>
    #     S.batch do
    #       a.value += 1
    #       b.value += 1
    #       raise "hello"
    #     end
    #   ).to.throw("hello")
    #
    #   assert_equal(1, spy1.called_times)
    #   assert_equal(1, spy2.called_times)
    # end
    #
    # it "should run pending effects even if some effects throw" do
    #   a = S.signal(0)
    #   spy1 = Spy.new { a.value }
    #   spy2 = Spy.new { a.value }
    #   S.effect do
    #     if a.value == 1
    #       raise "hello"
    #     end
    #   end
    #   S.effect(&spy1)
    #   S.effect do
    #     if a.value == 1
    #       raise "hello"
    #     end
    #   end
    #   S.effect(&spy2)
    #   S.effect do
    #     if a.value == 1
    #       raise "hello"
    #     end
    #   end
    #   spy1.reset_history!
    #   spy2.reset_history!
    #
    #   expect(() =>
    #     S.batch do
    #       a.value += 1
    #     end
    #   ).to.throw("hello")
    #
    #   assert_equal(1, spy1.called_times)
    #   assert_equal(1, spy2.called_times)
    # end
    #
    # it "should run effect's first run immediately even inside a batch" do
    #   called_times = 0
    #   spy = Spy.new {}
    #   S.batch do
    #     S.effect(&spy)
    #     called_times = spy.called_times
    #   end
    #   assert_equal(1, called_times)
    # end
  end
end
