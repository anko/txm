#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test
# inputs or outputs.  Run the tests and check their inputs and outputs match.

require! <[ fs os unified remark-parse yargs async chalk ]>
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

  return yargs.parse argv-to-parse


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

  text = indent indent-level, "#{chalk.dim "---"}"
  for key, value of properties
    text += "\n" + indent indent-level, "#{chalk.blue key}:"
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
  text += "\n" + indent indent-level, "#{chalk.dim "---"}"
  return text

success-text = (index, name) ->
  "#{chalk.green "ok"} #{chalk.dim index} #name"

failure-text = (index, name, failure-reason, properties) ->
  text = "#{chalk.red "not ok"} #{chalk.dim index}"
  text += " #name#{chalk.dim ": #failure-reason"}"
  if properties
    text += "\n" + format-properties properties, 1
  return text

parsing-error = (name, failure-reason, properties) ->
  console.log chalk.dim "0..0"
  console.log failure-text 0 name, failure-reason, properties
  console.log!
  console.log chalk.red.inverse "# FAILED TO PARSE TESTS"
  process.exit exit-code.FORMAT_ERROR

run-tests = (queue) ->
  try

    if queue.length is 0
      console.log chalk.yellow "1..0"
      console.log chalk.yellow "# no tests"
      console.log chalk.dim "# For help, see #{homepage-link}"
      process.exit exit-code.SUCCESS

    console.log chalk.dim "1..#{queue.length}"

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
      result-callback = (e, stdout, stderr) ->

        unless e
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
                      previous + chalk.red.inverse.strikethrough text
                    | _  => previous
                  ""
                actual-with-highlights = diff.reduce do
                  (previous, [change, text]) ->
                    switch change
                    | 0 => previous + text
                    | 1 =>
                      text = with-visible-newlines text
                      previous + chalk.green.inverse text
                    | _ => previous
                  ""
                return
                  expected: expected-with-highlights
                  actual: actual-with-highlights

            fail index, test.name, "output mismatch",
              expected: expected
              actual: actual
              program: test.program.code
              "input location": format-position test.input.position
              "output location": format-position test.output.position
        else
          fail index, test.name, "program exited with error",
            program: test.program.code
            "exit status": e.code
            stderr: stderr
            stdout: stdout
            "input location": format-position test.input.position
            "output location": format-position test.output.position
        cb!

      exec test.program.code, result-callback
        ..stdin .on \error ->
          if it.code is \EPIPE
            void # do nothing
          else throw it

        ..stdin.end test.input.text

    if e then die e.message

    console.log!
    colour = if failures is 0 then chalk.green else chalk.red
    console.log colour "# #successes/#{queue.length} passed"
    if failures is 0
      console.log colour.inverse "# OK"
    else
      console.log colour.inverse "# FAILED #failures"
      process.exit exit-code.TEST_FAILURE
  catch e
    die e

die = (message) ->
  # For fatal errors.  We should try when possible to fail via parsing-error,
  # so that the error output is still valid TAP.
  console.error message
  process.exit exit-code.INTERNAL_ERROR

extract-html-comments = (input) ->
  comments = []
  p = new sax-parser!
    ..on \comment -> comments.push it.text
    ..end input
  return comments

# Consecutive dashes are illegal inside HTML comments, so let's allow them to
# be escaped in the "program" command.
unescape = (script) -> script.replace /\\(.)/g -> &1

test-this = (contents) ->

  console.log "TAP version 13"

  /*
    A test spec is a set of program, input, and expected output.  We maintain a
    collection of the incomplete ones indexed by name (unique identifier
    decided by the user).  Whenever new information is available for the test
    spec corresponding to a name, we add that information, and when it's
    complete, delete it from the incomplete list and queue it for running.
  */
  incomplete-test-specs = {}
  try-to-complete-test-spec = (name, property-name, value, program) !->
    test-spec = if name not of incomplete-test-specs
      { program }
    else
      incomplete-test-specs[name]
    incomplete-test-specs[name] = test-spec

    if property-name of test-spec
      parsing-error name, "duplicate #{property-name + \put}",
        { location: format-position value.position }

    test-spec[property-name] = value

    if test-spec.in? and test-spec.out?
      complete-spec =
        name: name
        program: test-spec.program
        input: test-spec.in
        output: test-spec.out
      delete incomplete-test-specs[name]
      return complete-spec

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
        | \in => fallthrough
        | \out
          parsing-error text, "'#name' command precedes first 'program' command", do
            location: format-position position
            "how to fix": """
            Declare a test program before the '#name #text' command at #{format-position position},
            using <!-- !test program <TEST PROGRAM HERE> -->"""

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

    waitingForInputText: ({ program, name }) ->
      got-text: (text, position) !->
        state-machine.now = state-machine.waitingForAnyCommand { program }
        return try-to-complete-test-spec name, \in, { text: text, position }, program
      got-command: (name, text, position) !->
        parsing-error "'#name #text'", "unexpected command (expected input text)", do
          location: format-position position
          "how to fix": """
          Check that your 'in' and 'out' commands are each followed by a block
          of code, not another test command.
          """

    waitingForOutputText: ({ program, name }) ->
      got-text: (text, position) !->
        state-machine.now = state-machine.waitingForAnyCommand { program }
        return try-to-complete-test-spec name, \out, { text: text, position }, program
      got-command: (name, text, position) !->
        parsing-error "'#name #text'", "unexpected command (expected output text)", do
          location: format-position position
          "how to fix": """
          Check that your 'in' and 'out' commands are each followed by a block
          of code, not another test command.
          """

  # Initial state:  We don't know what program to assign to new tests, so we
  # expect to see that first.
  state-machine.now = state-machine.waitingForProgramText!

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

          if first-word in <[ program in out ]>
            rest = command |> (.slice first-word.length)
                           |> (.trim!)
                           |> unescape
            state-machine.now.got-command first-word, rest, node.position
          else
            parsing-error "'#first-word'", "unknown command type", do
              location: format-position node.position
              "supported commands": <[ in out program ]>

      return []

    else if node.type is \code

      # Add a newline, because it's typical for the console output of any
      # command to end with a newline.
      #
      # In the rare cases that the test command output *doesn't* terminate with
      # a newline, it's trivial for users to put an "echo" command after it.
      # It is less trivial to trim the trailing newline from the output of
      # every normal command!
      text-content = node.value + os.EOL

      maybe-test-spec = state-machine.now.got-text text-content, node.position
      if maybe-test-spec then return [ maybe-test-spec ]
      else return []


    else if \children of node
      node.children |> map visit |> fold (++), []
    else []

  mdast-syntax-tree = unified!
    .use remark-parse
    .parse contents
  tests = visit mdast-syntax-tree

  # Any incomplete test specs being left over implies some inputs or outputs
  # couldn't be matched, which we should report as a parse error.
  for name, properties of incomplete-test-specs
    if properties.in and not properties.out
      parsing-error name, "no output defined", do
        location: format-position properties.in.position
        "how to fix": """
        Define an output for '#name', using <!-- !test out #name -->,
        followed by a code block.
        """
    if properties.out and not properties.in
      parsing-error name, "no input defined", do
        location: format-position properties.out.position
        "how to fix": """
        Define an input for '#name', using <!-- !test in #name -->,
        followed by a code block.
        """

    # This fallthrough case shouldn't happen, because to even be in the
    # incomplete-text-specs structure, either an input or output for that name
    # must have been found.
    die "Unexpected state of incomplete test spec #name: #{JSON.stringify properties}"

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
