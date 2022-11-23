#!/usr/bin/env lsc
{ exec-sync } = require \child_process
test = require \tape
color = require \kleur
tmp = require \tmp
fs = require \fs
{ randomUUID } = require \crypto

txm-command = "node src/cli.js"

run-program = (command, input="", env={}) ->
  env = Object.assign env, process.env
  try
    # If everything goes as planned, return just an object with the stdout
    # property.
    return {
      status: 0
      stderr: ''
      stdout : exec-sync command, {
        stdio: [ null, null, null ]
        encoding: 'utf-8'
        input
        env
      }
    }
  catch e
    # If something fails, return the error object, which contains `status` and
    # `stderr` properties also.
    return e

txm-expect = (options) ->

  name = options.name
  if not name? then throw Error "No test name specified!"
  input = options.input
  if not input? then throw Error "No test input specified!"
  expect-stdout = options.expect-stdout
  expect-stderr = options.expect-stderr
  expect-exit = if options.expect-exit? then that else 0
  flags = options.flags || ""
  files = options.files || ""
  env = {}
  if options.force-color
    env.FORCE_COLOR = 1

  test name, (t) ->
    { stdout, status, stderr } = run-program "#txm-command #flags", input, env
    if not status? then status := 0
    if not stderr? then stderr := ''

    t.equals status, expect-exit, "exit #{expect-exit}"

    if options.expect-stdout?
      if options.expect-stdout instanceof RegExp
        t.ok do
          stdout .match options.expect-stdout
          "stdout matches"
      else
        t.equals stdout, options.expect-stdout, "stdout matches"
    else
      t.equals stdout, "", "stderr empty"

    if options.expect-stderr?
      t.equals stderr, options.expect-stderr, "stderr matches"
    else
      t.equals stderr, "", "stderr empty"

    t.end!

txm-expect do
  name: "no tests"
  input: """
  Some irrelevant Markdown text.
  """
  expect-stdout: """
  TAP version 13
  1..0
  # no tests
  # For help, see https://github.com/anko/txm

  """

txm-expect do
  name: "simple cat passthrough"
  input: """
  <!-- !test program cat -->
  <!-- !test in test name -->

      hi

  <!-- !test out test name -->

      hi

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "failing test"
  input: """
  <!-- !test program cat -->
  <!-- !test in test name -->

      hi

  <!-- !test out test name -->

      hello

  <!-- !test err test name -->

      hello

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 test name: output mismatch
    ---
    expected stdout: |
      hello

    actual stdout: |
      hi

    program: |
      cat
    stderr: ''
    input location: |
      line 4
    output location: |
      line 8
    error location: |
      line 12
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "stderr mismatch"
  input: """
  <!-- !test program node -->
  <!-- !test in test name -->

      console.error('hi')
      console.log('hi')

  <!-- !test err test name -->

      hello

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 test name: error mismatch
    ---
    expected stderr: |
      hello

    actual stderr: |
      hi

    program: |
      node
    stdout: |
      hi

    input location: |
      lines 4-5
    error location: |
      line 9
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "multiple errors defined"
  input: """
  <!-- !test program cat -->
  <!-- !test in test name -->

      hi

  <!-- !test err test name -->

      hello
      there

  <!-- !test err test name -->

      hello
      there

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 test name: multiple errors defined
    ---
    input location: |
      line 4
    error locations:
      - lines 8-9
      - lines 13-14
    program location: |
      line 1
    how to fix: |
      Remove or rename the other errors.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "same line comments, some irrelevant"
  input: """
  <!-- !test program cat --><!-- !test in test name --><!-- something else -->

      hi

  <!-- !test out test name --><!-- hello! -->

      hi

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "using << heredocs in comments works"
  input: """
  <!-- !test program node <<X
  console.log('YEAH')
  X -->

  <!-- !test in test name -->

      doesn't matter

  <!-- !test out test name -->

      YEAH

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "comment inside CDATA is not parsed"
  input: """
  <![CDATA[
    This would be an error if it were parsed:
    <!-- !test in whatever -->
  ]]>
  """
  expect-stdout: /1..0\n# no tests/

txm-expect do
  name: "CDATA only, no comments"
  input: """
  <![CDATA[
    stuff
  ]]>
  """
  expect-stdout: /1..0\n# no tests/


txm-expect do
  name: "multiple CDATA, multiple comments"
  input: """
  <![CDATA[
    This would be an error if it were parsed:
    <!-- !test in whatever
  ]]>
  <![CDATA[
    This would be an error if it were parsed:
    <!-- !test in whatever
  ]]>
  <!--
    This would be an error if it were parsed:
    <![CDATA[ blah
  -->
  <!--
    This would be an error if it were parsed:
    <![CDATA[ blah
  -->
  """
  expect-stdout: /1..0\n# no tests/

txm-expect do
  name: "unterminated comment"
  expect-exit: 2
  input: """
  <!-- !test check whatever

    true

  """
  expect-stdout: /unterminated HTML comment[\s\S]*line 1/

txm-expect do
  name: "unterminated CDATA section"
  expect-exit: 2
  input: """
  other stuff
  <![CDATA[
  <!-- !test check whatever -->

      true

  """
  expect-stdout: /unterminated HTML CDATA[\s\S]*line 2/

txm-expect do
  name: "no program specified"
  input: """
  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: no program defined
    ---
    input location: |
      line 3
    output location: |
      line 7
    how to fix: |
      Declare a test program before your test,
      using <!-- !test program <TEST PROGRAM HERE> -->
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "no program specified and has multiple inputs"
  input: """
  <!-- !test in 1 -->

      hi

  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  expect-exit: 1
  # The "no program" error takes precedence
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: no program defined
    ---
    input locations:
      - line 3
      - line 7
    output location: |
      line 11
    how to fix: |
      Declare a test program before your test,
      using <!-- !test program <TEST PROGRAM HERE> -->
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "input without matching output"
  input: """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: only input defined
    ---
    input location: |
      line 4
    how to fix: |
      Define an output or error for '1', using

        <!-- !test out 1 -->

      or

        <!-- !test err 1 -->

      followed by a code block.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "output without matching input"
  input: """
  <!-- !test program cat -->
  <!-- !test out 1 -->

      hi
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: input not defined
    ---
    output location: |
      line 4
    how to fix: |
      Define an input for '1', using

        <!-- !test in 1 -->

      followed by a code block.
    ---

  # 0/1 passed
  # FAILED 1

  """
txm-expect do
  name: "another input command before first resolves"
  input: """
  <!-- !test program cat -->
  <!-- !test in 1 -->
  <!-- !test in 2 -->

      hi

  <!-- !test out 1 -->

      hi

  <!-- !test out 2 -->

      hi
  """
  expect-exit: 2
  expect-stdout: """
  TAP version 13
  0..0
  not ok 0 'in 2': unexpected command (expected input text)
    ---
    location: |
      line 3
    how to fix: |
      Check that your 'in' / 'out' / 'err' / 'check' commands are each followed
      by a block of code, not another test command.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  name: "another output command before first resolves"
  input: """
  <!-- !test program cat -->
  <!-- !test out 1 -->
  <!-- !test out 2 -->

      hi

  <!-- !test in 1 -->

      hi

  <!-- !test in 2 -->

      hi
  """
  expect-exit: 2
  expect-stdout: """
  TAP version 13
  0..0
  not ok 0 'out 2': unexpected command (expected output text)
    ---
    location: |
      line 3
    how to fix: |
      Check that your 'in' / 'out' / 'err' / 'check' commands are each followed
      by a block of code, not another test command.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  name: "another error command before first resolves"
  input: """
  <!-- !test program cat -->
  <!-- !test err 1 -->
  <!-- !test err 2 -->

      hi

  <!-- !test in 1 -->

      hi

  <!-- !test in 2 -->

      hi
  """
  expect-exit: 2
  expect-stdout: """
  TAP version 13
  0..0
  not ok 0 'err 2': unexpected command (expected error text)
    ---
    location: |
      line 3
    how to fix: |
      Check that your 'in' / 'out' / 'err' / 'check' commands are each followed
      by a block of code, not another test command.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  name: "another command before 'check' resolves"
  input: """
  <!-- !test program cat -->
  <!-- !test check 1 -->
  <!-- !test check 2 -->

      hi

  """
  expect-exit: 2
  expect-stdout: """
  TAP version 13
  0..0
  not ok 0 'check 2': unexpected command (expected check text)
    ---
    location: |
      line 3
    how to fix: |
      Check that your 'in' / 'out' / 'err' / 'check' commands are each followed
      by a block of code, not another test command.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  name: "redirection in program"
  input: """
  # whatxml

  XML/HTML templating with [LiveScript][1]'s [cascade][2] syntax.

  <!-- !test program
  sed '1s/^/console.log("hi");/' \\
  | node
  -->

  <!-- !test in 1 -->

  ```ls
  console.log("yo");
  ```

  To get this:

  <!-- !test out 1 -->

  ```html
  hi
  yo
  ```
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 1

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "output defined before input"
  input: """
  <!-- !test program cat -->
  <!-- !test out test name -->

      hi

  <!-- !test in test name -->

      hi

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "interleaved tests"
  input: """
  <!-- !test program cat -->
  <!-- !test in test one -->

      one

  <!-- !test in test two -->

      two

  <!-- !test out test one -->

      one

  <!-- !test out test two -->

      two

  """
  expect-stdout: """
  TAP version 13
  1..2
  ok 1 test one
  ok 2 test two

  # 2/2 passed
  # OK

  """

txm-expect do
  name: "Multiple inputs with conflicting id"
  input: """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      one

  <!-- !test in 1 -->

      two

  <!-- !test out 1 -->

      one

  <!-- !test in 1 -->

      two

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: multiple inputs defined
    ---
    input locations:
      - line 4
      - line 8
      - line 16
    output location: |
      line 12
    program location: |
      line 1
    how to fix: |
      Remove or rename the other inputs.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "Multiple outputs with conflicting id"
  input: """
  <!-- !test program cat -->
  <!-- !test out 1 -->

      one

  <!-- !test out 1 -->

      two

  <!-- !test in 1 -->

      one

  <!-- !test out 1 -->

      two

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 1: multiple outputs defined
    ---
    input location: |
      line 12
    output locations:
      - line 4
      - line 8
      - line 16
    program location: |
      line 1
    how to fix: |
      Remove or rename the other outputs.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "Long test name"
  input: """
  <!-- !test program cat -->
  <!-- !test in something fairly long going in here -->

      hi

  <!-- !test out something fairly long going in here -->

      hi
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 something fairly long going in here

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "Test name in Unicode"
  input: """
  <!-- !test program cat -->
  <!-- !test in 本当にいいんですか -->

      hi

  <!-- !test out 本当にいいんですか -->

      hi
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 本当にいいんですか

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "Whitespace at ends is ignored when matching inputs and outputs"
  input: """
  <!-- !test program cat -->
  <!-- !test in           spacing         -->

      hi

  <!-- !test out spacing-->

      hi
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 spacing

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "Whitespace inside input/output name is significant"
  input: """
  <!-- !test program cat -->
  <!-- !test in big cat -->

      hi

  <!-- !test out big  cat -->

      hello

  <!-- !test out big cat -->

      hi

  <!--!test in big  cat -->

      hello

  """
  expect-stdout: """
  TAP version 13
  1..2
  ok 1 big cat
  ok 2 big  cat

  # 2/2 passed
  # OK

  """


txm-expect do
  name: "Escaping hyphens with backslash works in all commands"
  input: """
  <!-- !test program
  printf "Literal hyphen: -\n"
  printf "Escaped hyphen: #-\n"
  printf "Single octothorpe: #\n"
  printf "Escaped hyphen-escape: ##-\n"
  printf "Escaped hyphen-escape-escape: ###-\n"
  -->

  <!-- !test in #-#- -->

      irrelevant

  <!-- !test out -#- -->

      Literal hyphen: -
      Escaped hyphen: -
      Single octothorpe: #
      Escaped hyphen-escape: #-
      Escaped hyphen-escape-escape: ##-
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 --

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "tests continue when test program fails"
  input: """
  <!-- !test program echo stdout hello; >&2 echo stderr hello; exit 1 -->
  <!-- !test in x -->

      hi

  <!-- !test out x -->

      hi

  <!-- !test in y -->

      hi
      there

  <!-- !test out y -->

      hi
      there
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..2
  not ok 1 x: program exited with error
    ---
    program: |
      echo stdout hello; >&2 echo stderr hello; exit 1
    exit status: 1
    stderr: |
      stderr hello

    stdout: |
      stdout hello

    input location: |
      line 4
    output location: |
      line 8
    program location: |
      line 1
    ---
  not ok 2 y: program exited with error
    ---
    program: |
      echo stdout hello; >&2 echo stderr hello; exit 1
    exit status: 1
    stderr: |
      stderr hello

    stdout: |
      stdout hello

    input location: |
      lines 12-13
    output location: |
      lines 17-18
    program location: |
      line 1
    ---

  # 0/2 passed
  # FAILED 2

  """

txm-expect do
  name: "unknown command"
  input: """
  <!-- !test program cat -->
  <!-- !test something x -->

      hi

  <!-- !test out x -->

      hi
  """
  expect-exit: 2
  expect-stdout: """
  TAP version 13
  0..0
  not ok 0 'something': unknown command type
    ---
    location: |
      line 2
    supported commands:
      - program
      - in
      - out
      - err
      - check
      - exit
      - only
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  name: "empty stdout and stderr are rendered in YAML as empty string"
  input: """
  <!-- !test program exit 1 -->
  <!-- !test in my test -->

      hi

  <!-- !test out my test -->

      hi
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: program exited with error
    ---
    program: |
      exit 1
    exit status: 1
    stderr: ''
    stdout: ''
    input location: |
      line 4
    output location: |
      line 8
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "succeeding test specified with 'check' command"
  input: """
  <!-- !test program exit 0 -->

  The check command doesn't need a corresponding output

  <!-- !test check my test -->

      hi

  """
  expect-exit: 0
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 my test

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "failing test specified with 'check' command"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  exit 1 -->

  <!-- !test check my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: program exited with error
    ---
    program: |
      >&2 echo stderr here
      echo stdout here
      exit 1
    exit status: 1
    stderr: |
      stderr here

    stdout: |
      stdout here

    check location: |
      line 8
    program location: |
      lines 1-4
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "check test with input (invalid)"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  exit 1 -->

  <!-- !test check my test -->

      hi

  <!-- !test in my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: defined as check, but also has input
    ---
    input location: |
      line 12
    check location: |
      line 8
    how to fix: |
      Remove the input, or create an in/out test instead.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "check test with output (invalid)"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  exit 1 -->

  <!-- !test check my test -->

      hi

  <!-- !test out my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: defined as check, but also has output
    ---
    output location: |
      line 12
    check location: |
      line 8
    how to fix: |
      Remove the output, or create an in/out test instead.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "check test with error (invalid)"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  exit 1 -->

  <!-- !test check my test -->

      hi

  <!-- !test err my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: defined as check, but also has error
    ---
    error location: |
      line 12
    check location: |
      line 8
    how to fix: |
      Remove the error, or create an in/out test instead.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "multiple checks defined (invalid)"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  exit 1 -->

  <!-- !test check my test -->

      hi

  <!-- !test check my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: multiple checks defined
    ---
    check locations:
      - line 8
      - line 12
    how to fix: |
      Remove or rename the other checks.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "check test program gets input"
  input: """
  <!-- !test program cat ; exit 1 -->
  <!-- !test check my test -->

      hi

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: program exited with error
    ---
    program: |
      cat ; exit 1
    exit status: 1
    stderr: ''
    stdout: |
      hi

    check location: |
      line 4
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "test with err block"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  -->
  <!-- !test in my test -->

      irrelevant

  <!-- !test err my test -->

      stderr here

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 my test

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "test with both out and err blocks"
  input: """
  <!-- !test program
  >&2 echo stderr here
  echo stdout here
  -->
  <!-- !test in my test -->

      irrelevant

  <!-- !test out my test -->

      stdout here

  <!-- !test err my test -->

      stderr here

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 my test

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "expected exit status command"
  input: """
  <!-- !test program node -->
  <!-- !test exit 1 -->
  <!-- !test in my test -->

      console.log('output')
      process.exit(1)

  <!-- !test out my test -->

      output

  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 my test

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "expected exit status command with check"
  input: """
  <!-- !test program node -->
  <!-- !test exit 1 -->
  <!-- !test check my test -->

      console.log('output')
      process.exit(1)
  """
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 my test

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "'exit': wrong exit code"
  input: """
  <!-- !test program node -->
  <!-- !test exit 2 -->
  <!-- !test check my test -->

      console.log('output')
      process.exit(1)
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: program exited with unexpected exit status
    ---
    program: |
      node
    exit status: 1
    expected exit status: 2
    stderr: ''
    stdout: |
      output

    check location: |
      lines 5-6
    program location: |
      line 1
    exit location: |
      line 2
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "'exit': expect fail, get success"
  input: """
  <!-- !test program node -->
  <!-- !test exit 1 -->
  <!-- !test check my test -->

      console.log('output')
      process.exit(0)
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: program exited with unexpected success
    ---
    program: |
      node
    exit status: 0
    expected exit status: 1
    stderr: ''
    stdout: |
      output

    check location: |
      lines 5-6
    program location: |
      line 1
    exit location: |
      line 2
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "'exit': expect nonzero"
  input: """
  <!-- !test program node -->
  <!-- !test exit nonzero -->
  <!-- !test check test 1 -->

      console.log('output')
      process.exit(1)

  <!-- !test exit nonzero -->
  <!-- !test check test 2 -->

      console.log('output')
      process.exit(2)
  """
  expect-stdout: """
  TAP version 13
  1..2
  ok 1 test 1
  ok 2 test 2

  # 2/2 passed
  # OK

  """

txm-expect do
  name: "'exit' bad error code"
  input: """
  <!-- !test program node -->
  <!-- !test exit blah blah -->
  <!-- !test check my test -->

      process.exit(0)

  """
  expect-exit: 2
  expect-stdout: /bad exit code/

txm-expect do
  name: "multiple expected exit status commands"
  input: """
  <!-- !test program node -->
  <!-- !test exit 1 -->
  <!-- !test in my test -->

      console.log('output')
      process.exit(1)

  <!-- !test exit 1 -->
  <!-- !test out my test -->

      output
  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 my test: multiple expected exit statuses defined
    ---
    exit locations:
      - line 2
      - line 8
    how to fix: |
      Have just 1 expected exit status, before one of
      this test's '!test' commands.
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "'only' test skips others"
  input: """
  <!-- !test program node -->
  <!-- !test check my test 1 -->

      process.exit(0)

  <!-- !test only -->
  <!-- !test check my test 2 -->

      process.exit(0)

  <!-- !test check my test 3 -->

      process.exit(1)
  """
  expect-stdout: """
  TAP version 13
  1..3
  ok 2 my test 2

  # 1/3 passed
  # OK, SKIPPED 2

  """


txm-expect do
  name: "test program sees metadata as env variables"
  input: """
  <!-- !test program
  echo "index: $TXM_INDEX"
  echo "name: $TXM_NAME"
  echo "first index: $TXM_INDEX_FIRST"
  echo "last index: $TXM_INDEX_LAST"
  echo "lang: $TXM_INPUT_LANG"
  echo "color: $TXM_HAS_COLOR"
  echo "colour: $TXM_HAS_COLOUR"
  -->
  <!-- !test in test name -->

  ```js
  whatever
  ```

  <!-- !test out test name -->

      index: 1
      name: test name
      first index: 1
      last index: 1
      lang: js
      color: 0
      colour: 0

  """
  expect-exit: 0
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "test program sees colour env variables if colour enabled"
  input: """
  <!-- !test program
  echo "color: $TXM_HAS_COLOR"
  echo "colour: $TXM_HAS_COLOUR"
  -->
  <!-- !test in test name -->

  ```js
  whatever
  ```

  <!-- !test out test name -->

      color: 1
      colour: 1

  """
  force-color: true
  expect-exit: 0
  expect-stdout: /ok.*1.*test name/

txm-expect do
  name: "lang env variable in check test"
  input: """
  <!-- !test program
  [ "$TXM_INPUT_LANG" = "languageTag" ] && exit 0
  exit 1
  -->
  <!-- !test check test name -->

  ```languageTag
  whatever
  ```

  """
  expect-exit: 0
  expect-stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  name: "tests finishing out of order"
  input: """
  <!-- !test program
  # If this is the first test, have a little sleep while waiting letting the
  # second one finish first.
  if [ "$TXM_INDEX" == "1" ]; then
    sleep 0.5
  fi
  -->
  <!-- !test check 1 -->

      hi

  <!-- !test check 2 -->

      hi

  """
  expect-exit: 0
  # Outputs are still in the right order
  expect-stdout: """
  TAP version 13
  1..2
  ok 1 1
  ok 2 2

  # 2/2 passed
  # OK

  """

txm-expect do
  name: "stdout diff containing control characters"
  input: """
  <!-- !test program node -->

  <!-- !test in name -->

      process.stdout.write("line 1\\r\\0\\nline 2")

  <!-- !test out name -->

      line 1
      line 2

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 name: output mismatch
    ---
    expected stdout: |
      line 1
      line 2␊

    actual stdout: |
      line 1␍␀
      line 2
    invisible characters in diff: |
      ␊ represents Line Feed ("\\n") [U+000a]
      ␍ represents Carriage Return ("\\r") [U+000d]
      ␀ represents Null ("\\0") [U+0000]
    program: |
      node
    stderr: ''
    input location: |
      line 5
    output location: |
      lines 9-10
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  name: "stderr diff containing control characters"
  input: """
  <!-- !test program node -->

  <!-- !test in name -->

      process.stderr.write("line 1\\r\\0\\nline 2")

  <!-- !test err name -->

      line 1
      line 2

  """
  expect-exit: 1
  expect-stdout: """
  TAP version 13
  1..1
  not ok 1 name: error mismatch
    ---
    expected stderr: |
      line 1
      line 2␊

    actual stderr: |
      line 1␍␀
      line 2
    invisible characters in diff: |
      ␊ represents Line Feed ("\\n") [U+000a]
      ␍ represents Carriage Return ("\\r") [U+000d]
      ␀ represents Null ("\\0") [U+0000]
    program: |
      node
    stdout: ''
    input location: |
      line 5
    error location: |
      lines 9-10
    program location: |
      line 1
    ---

  # 0/1 passed
  # FAILED 1

  """


txm-expect do
  name: "success colours work"
  force-color: true
  input: """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  expect-exit: 0
  expect-stdout: new RegExp(color.green('ok').replace(/\[/g, '\\['))

txm-expect do
  name: "failure colours work"
  force-color: true
  input: """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi there

  <!-- !test out 1 -->

      replaced text

  """
  expect-exit: 1
  expect-stdout: new RegExp(color.red('not ok').replace(/\[/g, '\\['))

test "user failing check test emitted colours included" (t) ->
  input = """
  <!-- !test program node -->
  <!-- !test check 1 -->

      const c = require('kleur')
      c.enabled = true
      console.log(c.red('hi from stdout'))
      console.error(c.red('hi from stderr'))
      process.exit(1)
  """
  { stdout, status, stderr } = run-program txm-command, input
  t.notEqual status, 0
  t.notEqual stdout.indexOf(color.red('hi from stdout')), -1
  t.notEqual stdout.indexOf(color.red('hi from stderr')), -1
  t.end!

test "file passed as argument" (t) ->
  tmp.file (err, path, fd, cleanup) ->
    fs.writeFileSync do
      fd
      """
      <!-- !test program cat -->
      <!-- !test in 1 -->

          hi

      <!-- !test out 1 -->

          hi

      """
    { stdout, status, stderr } = run-program "#txm-command #path"
    t.equal status, 0
    t.equal stdout, """
      TAP version 13
      1..1
      ok 1 1

      # 1/1 passed
      # OK

      """
    cleanup!
    t.end!

test "more than 1 file shows an error" (t) ->
  tmp.file (err, path, fd, cleanup) ->
    tmp.file (err, path2, fd2, cleanup2) ->
      { stdout, status, stderr } = run-program "#txm-command #path #path2"
      t.equal status, 2
      t.ok stderr.match /Expected 1.*got 2/

      cleanup!
      cleanup2!
      t.end!

test "--version option" (t) ->
    { stdout, status, stderr } = run-program "cat | #txm-command --version"
    t.equal status, 0
    t.ok stdout.match require('./package.json').version
    t.end!

test "--help option" (t) ->
    { stdout, status, stderr } = run-program "cat | #txm-command --help"
    t.equal status, 0
    t.ok stdout.match /--jobs/
    t.ok stdout.match /--version/
    t.ok stdout.match /--help/
    t.end!

test "--jobs option is recognised" (t) ->
  tmp.file (err, path, fd, cleanup) ->
    fs.writeSync fd, """
    <!-- !test program cat -->
    <!-- !test in 1 -->

        hi

    <!-- !test out 1 -->

        hi
    """
    { stdout, status, stderr } = run-program "#txm-command --jobs 1 #path"
    t.equal status, 0
    t.ok stdout.match /ok 1 1/

    cleanup!
    t.end!

test "bad --jobs option" (t) ->
  tmp.file (err, path, fd, cleanup) ->
    fs.writeSync fd, """
    <!-- !test program cat -->
    <!-- !test in 1 -->

        hi

    <!-- !test out 1 -->

        hi
    """
    { stdout, status, stderr } = run-program "#txm-command --jobs -1 #path"
    t.equal status, 2
    lines = stderr.split \\n
    t.ok lines.0.match /--jobs.*expected/

    cleanup!
    t.end!

test "attempting to open nonexistent file" (t) ->
  uuid = randomUUID!
  path = "./#uuid.md" # This doesn't exist
  { stdout, status, stderr } = run-program "#txm-command #path"
  t.equal status, 2
  lines = stderr.split \\n
  t.ok lines.0.match new RegExp "ENOENT.*#uuid"

  t.end!

test "running txm from some other directory" (t) ->
  # chdir to somewhere distant, and try to run txm from over there
  tmp.dir (err, path, cleanup) ->
    const previousCwd = process.cwd()
    process.chdir(path)

    # Create test file
    fs.writeFileSync do
      't.js'
      """
      <!-- !test program cat -->
      <!-- !test in 1 -->

          hi

      <!-- !test out 1 -->

          hi

      """

    { stdout, status, stderr } =
      run-program "node #previousCwd/src/cli.js t.js"
    t.equal(status, 0)

    process.chdir(previousCwd)
    cleanup!
    t.end!
