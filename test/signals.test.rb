require "bundler/setup"
require "minitest/autorun"
require "minitest/hooks/default"
require_relative "../lib/mayu/signals"

S = Mayu::Signals::S

class Spy < Proc
  def initialize(...)
    super
    @called_times = 0
    @return_value = nil
  end

  def called_times = @called_times
  def return_value = @return_value
  def reset_history! = @called_times = 0

  def call(...)
    @called_times += 1
    super.tap { @return_value = _1 }
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
    end
  end
end
