File
  .read("signals.test.rb")
  .gsub('it(', "it ")
  .gsub(', () => {', " do")
  .gsub('() => {', " do")
  .gsub('});', "end")
  .gsub('===', "==")
  .gsub(/\}\)$/, "end")
  .gsub(/\b\}\)$/, "end")
  .gsub(/;$/, '')
  .gsub(/effect\((\w+)\)/, 'S.effect(&\1)')
  .gsub(/ effect\(\s/, ' S.effect ')
  .gsub(/ computed\(\s/, ' S.computed ')
  .gsub('batch(', 'batch')
  .gsub(".resetHistory()", ".reset_history!")
  .gsub(".peek())", ".peek)")
  .gsub("try {", "begin)")
  .gsub(/\} catch \((\w+)\) {/, 'rescue => \1')
  .gsub("try {", "begin)")
  .gsub(/expect\(([\w\.\[\]]+?)\)\.to\.be\.undefined/, 'assert_nil(\1)')
  .gsub(/expect\(([\w\.\[\]]+?)\)\.to\.equal\((.+?)\)/, 'assert_equal(\2, \1)')
  .gsub(/expect\(([\w\.\[\]]+?)\)\.to\.deep\.equal\((.+?)\)/, 'assert_equal(\2, \1)')
  .gsub(/expect\((\w+?)\)\.to\.be\.calledOnce/, 'assert_equal(1, \1.called_times)')
  .gsub(/expect\((\w+?)\)\.not\.to\.be\.called/, 'assert_equal(0, \1.called_times)')
  .gsub(/throw new Error\((".*?")\)/, 'raise \1')
  .gsub(/throw Error\((".*?")\)/, 'raise \1')
  .gsub(/if \((.*?)\) {/, 'if \1')
  .gsub(/\}$/, "end")
  .gsub(/\+\+$/, " += 1")
  .gsub(" = signal(", " = S.signal(")
  .gsub(" const ", " ")
  .gsub(" let ", " ")
  .gsub(" effect do", " S.effect do")
  .gsub(" batch do", " S.batch do")
  .gsub(/sinon\.spy\(\(\) => (.*?)\)/, 'Spy.new { \1 }')
  .gsub(/sinon\.spy\(\)/, 'Spy.new {}')
  .gsub("callCount", "called_times")
  .gsub(/ computed\(\(\) => (.*?)\)/,  ' S.computed { \1 }')
  .gsub(/ effect\(\(\) => (.*?)\)/,  ' S.effect { \1 }')
  .then { puts _1 }
