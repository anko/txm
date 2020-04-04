#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test
# inputs or outputs.  Run the tests and check their inputs and outputs match.

require! <[ fs os unified remark-parse async colorette ]>
sax-parser = require \parse5-sax-parser
{ exec } = require \child_process
{ each, map, fold, unwords, keys, first } = require \prelude-ls
concat = require \concat-stream
dmp = new (require \diff-match-patch)!
homepage-link = require \./package.json .homepage

exit-code =
  SUCCESS: 0
  TEST_FAILURE: 1
  FORMAT_ERROR: 2
  INTERNAL_ERROR: 3

argv = do ->

  # It hurts that I have to do this, but here we are.  When run with lsc
  # (livescript interpreter), process.argv contains [node, lsc, index.ls].
  # When run with node, it's just [node, index.js].  In other words, the number
  # of things we have to slice off depends on what interpreter we're running,
  # which is a heap of crap, but at least we can detect for it at runtime with
  # process.argv.lsc, which contains just [index.ls] when run with lsc and
  # doesn't exist if we're running with node.
  argv-to-parse =
    if process.argv.lsc?
      # Slice off main file path
      that.slice 1
    else
      # Slice off interpreter path and main file path
      process.argv.slice 2

  return-argv = { _: [] }
  for arg in argv-to-parse
    if arg is \--series
      return-argv.series = true
    else
      return-argv._.push arg

  return return-argv

format-position = (position) ->
  pos =
    start: position.start.line
    end: position.end.line
  if pos.start is pos.end then "line #{pos.start}"
  else "lines #{pos.start}-#{pos.end}"

indent = (n, text) ->
  spaces = "  " * n
  lines = text.split os.EOL .map -> if it.length then spaces + it else it
  lines.join os.EOL

format-properties = (properties, indent-level=0) ->

  text = indent indent-level, "#{colorette.dim "---"}"
  for key, value of properties
    text += "\n" + indent indent-level, "#{colorette.blue key}:"
    switch typeof! value
    case \Array
      for v in value
        text += "\n" + indent (indent-level + 1), "- #{v.to-string!}"
    case \Number
      text += " " + value.to-string!
    case \String
      if value === "" then text += " ''"
      else text += " |\n" + indent (indent-level + 1), value
    default
      text += "\n" + indent (indent-level + 1), value.to-string!
  text += "\n" + indent indent-level, "#{colorette.dim "---"}"
  return text

success-text = (index, name) ->
  "#{colorette.green "ok"} #{colorette.dim index} #name"

failure-text = (index, name, failure-reason, properties) ->
  text = "#{colorette.red "not ok"} #{colorette.dim index}"
  text += " #name#{colorette.dim ": #failure-reason"}"
  if properties
    text += "\n" + format-properties properties, 1
  return text

parsing-error = (name, failure-reason, properties) ->
  console.log colorette.dim "0..0"
  console.log failure-text 0 name, failure-reason, properties
  console.log!
  console.log ("# FAILED TO PARSE TESTS" |> colorette.bg-red |> colorette.black)
  process.exit exit-code.FORMAT_ERROR

run-tests = (queue) ->
  try

    if queue.length is 0
      console.log colorette.yellow "1..0"
      console.log colorette.yellow "# no tests"
      console.log colorette.dim "# For help, see #{homepage-link}"
      process.exit exit-code.SUCCESS

    console.log colorette.dim "1..#{queue.length}"

    # The parallel processing strategy here is to run multiple tests in
    # parallel (so their results may arrive in arbitrary order) but only
    # print each one's results when all tests before that one's index have
    # been printed.

    parallelism = if argv.series then 1 else os.cpus().length
    prints-waiting = []
    next-index-to-print = 0
    successes = 0
    failures = 0

    try-to-say = (index, text) ->
      if index is next-index-to-print
        # Everything before this index has been printed.  We can print
        # immediately.
        console.log text

        ++next-index-to-print

        # Let's also check if the text for the next index has arrived, and
        # if so, print that too.
        if prints-waiting[next-index-to-print]
          try-to-say next-index-to-print, that
      else
        # Otherwise, wait patiently in line until the indexes before us get
        # their turns.  They will call us when it's our turn.
        prints-waiting[index] = text

    succeed = (index, name, properties) ->
      ++successes
      try-to-say index, success-text (index + 1), name

    fail = (index, name, failure-reason, properties) ->
      ++failures
      text = failure-text (index + 1), name, failure-reason, properties
      try-to-say index, text

    e <- async.each-of-limit queue, parallelism, (test, index, cb) ->

      #
      # Fail out early if something is clearly wrong with this test
      #

      valid-input = (test) ->
        if test.input?length is 1 then test.input.0 else false
      valid-output = (test) ->
        if test.output?length is 1 then test.output.0 else false
      valid-check = (test) ->
        if test.check?length is 1 then test.check.0 else false
      valid-program = (test) ->
        # It's OK for there to be multiple; just use the latest
        non-null-programs = test.program .filter (?)
        return test.program[* - 1] || false

      earlier-position = (a, b) ->
        return b if not a
        return a if not b
        if a.start.offset < b.start.offset then a else b

      # No program specified
      if not valid-program test
        debug-properties = {}
        earliest-position = null
        if valid-input test
          debug-properties["input location"] = format-position that.position
          earliest-position := earlier-position do
            that.position
            earliest-position
        if valid-output test
          debug-properties["output location"] = format-position that.position
          earliest-position := earlier-position do
            that.position
            earliest-position
        debug-properties["how to fix"] = """
          Declare a test program before #{format-position earliest-position},
          using <!-- !test program <TEST PROGRAM HERE> -->"""
        fail index, test.name, "no program defined", debug-properties
        cb!; return

      if test.check
        if test.input
          fail index, test.name, "defined as check, but also has input",
            "input locations": test.input.map -> format-position it.position
            "how to fix": """
            Remove the input, or create an in/out test instead.
            """
          cb!; return
        if test.output
          fail index, test.name, "defined as check, but also has output",
            "output locations": test.output.map -> format-position it.position
            "how to fix": """
            Remove the output, or create an in/out test instead.
            """
          cb!; return
        if test.check.length > 1
          fail index, test.name, "multiple checks defined",
            "check locations": test.check.map -> format-position it.position
            "how to fix": """
            Remove or rename the other checks.
            """
          cb!; return
      else
        # No input specified
        if (not test.input?) or test.input.length is 0
          debug-properties = {}
          if valid-output test
            debug-properties["output location"] = format-position that.position
          debug-properties["how to fix"] = """
            Define an input for '#{test.name}', using

              <!-- !test in #{test.name} -->

            followed by a code block.
            """
          fail index, test.name, "input not defined", debug-properties
          cb!; return

        # No output specified
        if (not test.output?) or test.output.length is 0
          debug-properties = {}
          if valid-input test
            debug-properties["input location"] = format-position that.position
          debug-properties["how to fix"] = """
            Define an output for '#{test.name}', using

              <!-- !test out #{test.name} -->

            followed by a code block.
            """
          fail index, test.name, "output not defined", debug-properties
          cb!; return

        # Multiple inputs specified
        if test.input?length > 1
          debug-properties = {}
          if valid-output test
            debug-properties["output location"] = format-position that.position
          debug-properties["input locations"] =
            test.input.map -> format-position it.position
          debug-properties["how to fix"] = """
            Remove or rename the other inputs.
            """
          fail index, test.name, "multiple inputs defined", debug-properties
          cb!; return

        # Multiple outputs specified
        if test.output?length > 1
          debug-properties = {}
          if valid-input test
            debug-properties["input location"] = format-position that.position
          debug-properties["output locations"] =
            test.output.map -> format-position it.position
          debug-properties["how to fix"] = """
            Remove or rename the other outputs.
            """
          fail index, test.name, "multiple outputs defined", debug-properties
          cb!; return

      test =
        name: test.name
        program: valid-program test
        input: valid-input test
        output: valid-output test
        check: valid-check test

      with-location-props = (obj) ->
        location-props = {}
          if test.check
            ..["check location"] = format-position test.check.position
          if test.input
            ..["input location"] = format-position test.input.position
          if test.output
            ..["output location"] = format-position test.output.position

        props = {}
          Object.assign .., obj
          Object.assign .., location-props

      result-callback = (e, stdout, stderr) ->

        unless e

          if test.check
            succeed index, test.name
            cb! ; return

          if stdout is test.output.text
            succeed index, test.name
          else

            { expected, actual } = do ->
              if not process.stdout.isTTY
                return
                  expected: test.output.text
                  actual: stdout
              else
                # We are outputting to a terminal, so it's going to be seen
                # by a human.  Let's do a diff, and helpfully highlight
                # parts of the expected and actual output values, to make
                # it easier for the human to spot differences.

                diff = dmp.diff_main test.output.text, stdout
                dmp.diff_cleanupSemantic diff

                with-visible-newlines = ->
                  it.replace (new RegExp os.EOL, \g), (x) -> "↵#x"

                expected-with-highlights = diff.reduce do
                  (previous, [change, text]) ->
                    switch change
                    | 0  => previous + text
                    | -1 =>
                      text = with-visible-newlines text
                      previous + (text |> colorette.red
                                       |> colorette.inverse
                                       |> colorette.strikethrough)
                    | _  => previous
                  ""
                actual-with-highlights = diff.reduce do
                  (previous, [change, text]) ->
                    switch change
                    | 0 => previous + text
                    | 1 =>
                      text = with-visible-newlines text
                      previous + (text |> colorette.green
                                       |> colorette.inverse)
                    | _ => previous
                  ""
                return
                  expected: expected-with-highlights
                  actual: actual-with-highlights

            fail index, test.name, "output mismatch", with-location-props do
              expected: expected
              actual: actual
              program: test.program.code

        else
          fail index, test.name, "program exited with error", with-location-props do
            program: test.program.code
            "exit status": e.code
            stderr: stderr
            stdout: stdout
        cb!

      exec test.program.code, result-callback
        ..stdin .on \error ->
          if it.code is \EPIPE
            void # do nothing
          else throw it

        if test.input
          ..stdin.end test.input.text
        else
          ..stdin.end test.check.text

    if e then die e.message

    console.log!
    colour = if failures is 0 then colorette.green else colorette.red
    colour-inverse = colorette.inverse >> colour
    console.log colour "# #successes/#{queue.length} passed"
    if failures is 0
      console.log colour-inverse "# OK"
    else
      console.log colour-inverse "# FAILED #failures"
      process.exit exit-code.TEST_FAILURE
  catch e
    die e

die = (message) ->
  # For fatal errors.  When possible, we should fail by writing out valid TAP,
  # by e.g. calling the parsing-error function.
  console.error message
  process.exit exit-code.INTERNAL_ERROR

extract-html-comments = (input) ->
  comments = []
  p = new sax-parser!
    ..on \comment -> comments.push it.text
    ..end input
  return comments

/*
  Consecutive dashes ("--") are illegal inside HTML comments, so let's allow
  them to be escaped with the sequence "\-".  We treat "\-" like a single token
  that can be escaped ("\\-") to get a literal "\-".  This way, users can still
  write "\" in other contexts (which is common in shell scripts for the
  "program" command) without entering backslash hell.
*/
unescape = (script) -> script.replace /(?<!\\)\\-/g, '-'

test-this = (contents) ->

  console.log "TAP version 13"

  /*
    A test spec is a set of program, input, and expected output.  We maintain a
    collection of the incomplete ones indexed by name (unique identifier
    decided by the user).  Whenever new information is available for the test
    spec corresponding to a name, we add that information, and when it's
    complete, delete it from the incomplete list and queue it for running.
  */
  test-specs = {}
  add-to-test-spec = (name, key, value) !->
    test-spec = if name of test-specs then test-specs[name] else {}
    test-specs[name] = test-spec

    test-spec.[][key] .push value

  /*
    This state machine describes the state that the parser is in.  The 'now'
    property holds its current state.  States are represented by constructor
    functions take parameters, through which data is passed when transitioning
    between states.

    Each state can react to texts (i.e. code blocks) or commands (i.e. HTML
    comments containing "!test" commands) in whatever way is appropriate for
    that state.
  */
  state-machine =
    waitingForProgramText: ->
      got-text: !-> # ignore
      got-command: (name, text, position) !->
        switch name
        | \program =>
          state-machine.now = state-machine.waitingForAnyCommand do
            program: { code: text, position: position }

    waitingForAnyCommand: ({ program }) ->
      got-text: !-> # Ignore
      got-command: (name, text, position) !->
        switch name
        | \program =>
          state-machine.now = state-machine.waitingForAnyCommand do
            program: { code: text, position: position }
        | \in  =>
          state-machine.now = state-machine.waitingForInputText { program, name: text }
        | \out =>
          state-machine.now = state-machine.waitingForOutputText { program, name: text }
        | \check =>
          state-machine.now = state-machine.waitingForCheckText { program, name: text }

    waitingForInputText: ({ program, name }) ->
      got-text: (text, position) !->
        state-machine.now = state-machine.waitingForAnyCommand { program }
        add-to-test-spec name, \input, { text: text, position }
        add-to-test-spec name, \program, program
      got-command: (name, text, position) !->
        parsing-error "'#name #text'", "unexpected command (expected input text)", do
          location: format-position position
          "how to fix": """
          Check that your 'in' / 'out' / 'check' commands are each followed by
          a block of code, not another test command.
          """

    waitingForOutputText: ({ program, name }) ->
      got-text: (text, position) !->
        state-machine.now = state-machine.waitingForAnyCommand { program }
        add-to-test-spec name, \output, { text: text, position }
        add-to-test-spec name, \program, program
      got-command: (name, text, position) !->
        parsing-error "'#name #text'", "unexpected command (expected output text)", do
          location: format-position position
          "how to fix": """
          Check that your 'in' / 'out' / 'check' commands are each followed by
          a block of code, not another test command.
          """

    waitingForCheckText: ({ program, name }) ->
      got-text: (text, position) !->
        state-machine.now = state-machine.waitingForAnyCommand { program }
        add-to-test-spec name, \check, { text: text, position }
        add-to-test-spec name, \program, program
      got-command: (name, text, position) !->
        parsing-error "'#name #text'", "unexpected command (expected check input text)", do
          location: format-position position
          "how to fix": """
          Check that your 'in' / 'out' / 'check' commands are each followed by
          a block of code, not another test command.
          """

  # Initial state:  We don't know what program to assign to new tests, so we
  # expect to see that first.
  state-machine.now = state-machine.waitingForAnyCommand { program: null }

  visit = (node) ->
    if node.type is \html

      extract-html-comments node.value .for-each (comment) ->

        re = //
             (?:\s+)?      # optional whitespace
             !test         # test command marker
             \s+           # whitespace
             ([\s\S]*)     # interesting commands
             //m

        [ _, command ] = (comment .trim! .match re) || []

        if command
          command-words = command .split /\s+/
          first-word    = first command-words

          if first-word in <[ program in out check ]>
            rest = command |> (.slice first-word.length)
                           |> (.trim!)
                           |> unescape
            state-machine.now.got-command first-word, rest, node.position
          else
            parsing-error "'#first-word'", "unknown command type", do
              location: format-position node.position
              "supported commands": <[ program in out check ]>

    else if node.type is \code

      # Add a newline, because it's typical for the console output of any
      # command to end with a newline.
      #
      # In the rare cases that the test command output *doesn't* terminate with
      # a newline, it's trivial for users to put an "echo" command after it.
      # It is less trivial to trim the trailing newline from the output of
      # every normal command!
      text-content = node.value + os.EOL

      state-machine.now.got-text text-content, node.position

    else if \children of node
      node.children |> each visit

  mdast-syntax-tree = unified!
    .use remark-parse
    .parse contents
  visit mdast-syntax-tree

  tests = []
  for name, properties of test-specs
    test = { name }
    for k, v of properties
      test[k] = v
    tests.push test

  run-tests tests

files = argv._

if files.length is 0
  # Read from stdin
  process.stdin
    ..on \error (e) -> die e.message
    ..pipe concat (data) ->
      test-this data
else
  files |> each (file) ->
    e, data <- fs.read-file file
    throw e if e
    test-this data
