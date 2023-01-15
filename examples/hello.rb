# frozen_string_literal: true

require_relative "../lib/mayu/signals"

S = Mayu::Signals::S

S.root do
  a = S.signal(0)
  b = S.signal(0)
  c = S.computed { a.value + b.value }
  e = S.effect { puts "c: #{c.value}" }

  a.value += 1
  sleep 0.1
  a.value += 1
  sleep 0.1
  a.value += 1
  sleep 0.1
  b.value += 1
end
