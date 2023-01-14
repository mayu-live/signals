# Signals

This is a Ruby port of [@preact/signals-core](https://github.com/preactjs/signals).

Tests are incomplete but the ones that exist pass.
Use at your own risk!

## Installation:

There's no gem. Figure it out.

- [Guide / API](#guide--api)
  - [`root(&)`](#root)
  - [`signal(initial_value)`](#signalinitialvalue)
    - [`signal.peek`](#signalpeek)
  - [`computed(&)`](#computed)
  - [`effect(&)`](#effect)
  - [`batch(&)`](#batch)
- [License](#license)

## Guide / API

The signals library exposes five methods which are the building blocks to model any business logic you can think of.

### `root(&)`

Creates a root scope that handles updates and everything.

### `signal(initial_value)`

The `signal` method creates a new signal. A signal is a container for a value that can change over time. You can read a signal's value or subscribe to value updates by accessing its `.value` property.

```ruby
require "mayu/signals"

include Mayu::Signals::Helpers

counter = signal(0)

# Read value from signal, logs: 0
p(counter.value)

# Write to a signal
counter.value = 1
```

Writing to a signal is done by setting its `.value` property. Changing a signal's value synchronously updates every [computed](#computedfn) and [effect](#effectfn) that depends on that signal, ensuring your app state is always consistent.

#### `signal.peek`

In the rare instance that you have an effect that should write to another signal based on the previous value, but you _don't_ want the effect to be subscribed to that signal, you can read a signals's previous value via `signal.peek()`.

```ruby
counter = signal(0)
effect_ount = signal(0)

effect do
  p(counter.value)

  # Whenever this effect is triggered, increase `effectCount`.
  # But we don't want this signal to react to `effectCount`
  effect_count.value = effect_count.peek + 1
end
```

Note that you should only use `signal.peek()` if you really need it. Reading a signal's value via `signal.value` is the preferred way in most scenarios.

### `computed(&)`

Data is often derived from other pieces of existing data. The `computed` method lets you combine the values of multiple signals into a new signal that can be reacted to, or even used by additional computeds. When the signals accessed from within a computed callback change, the computed callback is re-executed and its new return value becomes the computed signal's value.

```ruby
name = signal("Jane")
surname = signal("Doe")

full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
p(full_name.value)

# Updates flow through computed, but only if someone
# subscribes to it. More on that later.
name.value = "John"
# Logs: "John Doe"
p(full_name.value)
```

Any signal that is accessed inside the `computed`'s callback method will be automatically subscribed to and tracked as a dependency of the computed signal.

### `effect(fn)`

The `effect` method is the last piece that makes everything reactive. When you access a signal inside its callback function, that signal and every dependency of said signal will be activated and subscribed to. In that regard it is very similar to [`computed(&)`](#computed). By default all updates are lazy, so nothing will update until you access a signal inside `effect`.

```ruby
name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
effect { p(full_name.value) }

# Updating one of its dependencies will automatically trigger
# the effect above, and will print "John Doe" to the console.
name.value = "John"
```

You can destroy an effect and unsubscribe from all signals it was subscribed to, by calling the returned method.

```ruby
name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
dispose = effect { p(full_name.value) }

# Destroy effect and subscriptions
dispose.call()

# Update does nothing, because no one is subscribed anymore.
# Even the computed `full_name` signal won't change, because it knows
# that no one listens to it.
surname.value = "Doe 2"
```

### `batch(fn)`

The `batch` method allows you to combine multiple signal writes into one single update that is triggered at the end when the callback completes.

```ruby
name = signal("Jane")
surname = signal("Doe")
full_name = computed { name.value + " " + surname.value }

# Logs: "Jane Doe"
effect { p full_name.value }

# Combines both signal writes into one update. Once the callback
# returns the `effect` will trigger and we'll log "Foo Bar"
batch do
  name.value = "Foo"
  surname.value = "Bar"
end
```

When you access a signal that you wrote to earlier inside the callback, or access a computed signal that was invalidated by another signal, we'll only update the necessary dependencies to get the current value for the signal you read from. All other invalidated signals will update at the end of the callback method.

```ruby
counter = signal(0)
double = computed { counter.value * 2 }
triple = computed { counter.value * 3 }

effect { p(double.value, triple.value) }

batch do
  counter.value = 1
  # Logs: 2, despite being inside batch, but `triple`
  # will only update once the callback is complete
  p double.value
end
# Now we reached the end of the batch and call the effect
```

Batches can be nested and updates will be flushed when the outermost batch call completes.

```ruby
counter = signal(0)
effect { p(counter.value) }

batch do
  batch do
    # Signal is invalidated, but update is not flushed because
    # we're still inside another batch
    counter.value = 1
  end

  # Still not updated...
end
# Now the callback completed and we'll trigger the effect.
```

## License

`MIT`, see the [LICENSE](./LICENSE) file.
