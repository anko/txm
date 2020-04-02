#!/usr/bin/env lsc
{ exec-sync } = require \child_process
test = require \tape

txm-expect = (name, md-string, expected={}) ->

  txm = (md-string) ->
    try
      # If everything goes as planned, return just an object with the stdout
      # property.
      return {
        stdout : exec-sync "lsc index.ls --format=tap" {
          input : md-string
          stdio: [ null, null, null ]
        }
      }
    catch e
      # If something fails, return the error object, which contains `status`
      # and `stderr` properties also.
      return e

  test name, (t) ->
    { stdout, status, stderr } = txm md-string
    if not status? then status := 0
    if not stderr? then stderr := ''

    if expected.exit?
      t.equals do
        status
        expected.exit
        "exit code is #{expected.exit}"

    if expected.stdout?
      t.equals do
        stdout.to-string!
        expected.stdout
        "stdout matches"
    else
      t.equals do
        stdout.to-string!
        ""
        "stdout empty"

    if expected.stderr?
      t.equals do
        stderr.to-string!
        expected.stderr
        "stderr matches"
    else
      t.equals do
        stderr.to-string!
        ""
        "stderr empty"

    t.end!

txm-expect do
  "no tests"
  """
  Some irrelevant Markdown text.
  """
  exit: 0
  stdout: """
  TAP version 13
  1..0
  # no tests
  # For help, see https://github.com/anko/tests-ex-markdown

  """

txm-expect do
  "simple cat passthrough"
  """
  <!-- !test program cat -->
  <!-- !test in test name -->

      hi

  <!-- !test out test name -->

      hi

  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  "failing test"
  """
  <!-- !test program cat -->
  <!-- !test in test name -->

      hi

  <!-- !test out test name -->

      hello
      there

  """
  exit: 1
  stdout: """
  TAP version 13
  1..1
  not ok 1 test name: output mismatch
    ---
    expected: |
      hello
      there

    actual: |
      hi

    program: |
      cat
    input location: |
      line 4
    output location: |
      lines 8-9
    ---

  # 0/1 passed
  # FAILED 1

  """

txm-expect do
  "same line comments, some irrelevant"
  """
  <!-- !test program cat --><!-- !test in test name --><!-- something else -->

      hi

  <!-- !test out test name --><!-- hello! -->

      hi

  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """

txm-expect do
  "no program specified"
  """
  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 1: 'in' command precedes first 'program' command
    ---
    location: |
      line 1
    how to fix: |
      Declare a test program before the 'in 1' command at line 1,
      using <!-- !test program <TEST PROGRAM HERE> -->
    ---

  # FAILED TO PARSE TESTS

  """
  stderr: ""

txm-expect do
  "input without matching output"
  """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi
  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 1: no output defined
    ---
    location: |
      line 4
    how to fix: |
      Define an output for '1', using <!-- !test out 1 -->,
      followed by a code block.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  "output without matching input"
  """
  <!-- !test program cat -->
  <!-- !test out 1 -->

      hi
  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 1: no input defined
    ---
    location: |
      line 4
    how to fix: |
      Define an input for '1', using <!-- !test in 1 -->,
      followed by a code block.
    ---

  # FAILED TO PARSE TESTS

  """


txm-expect do
  "another output command before first resolves"
  """
  <!-- !test program cat -->
  <!-- !test out 1 -->
  <!-- !test out 2 -->

      hi

  <!-- !test in 1 -->

      hi

  <!-- !test in 2 -->

      hi
  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 'out 2': unexpected command (expected output text)
    ---
    location: |
      line 3
    how to fix: |
      Check that your 'in' and 'out' commands are each followed by a block
      of code, not another test command.
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  "redirection in program"
  """
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
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 1

  # 1/1 passed
  # OK

  """

txm-expect do
  "output defined before input"
  """
  <!-- !test program cat -->
  <!-- !test out test name -->

      hi

  <!-- !test in test name -->

      hi

  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 test name

  # 1/1 passed
  # OK

  """
  stderr: ""

txm-expect do
  "interleaved tests"
  """
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
  exit: 0
  stdout: """
  TAP version 13
  1..2
  ok 1 test one
  ok 2 test two

  # 2/2 passed
  # OK

  """
  stderr: ""

txm-expect do
  "Multiple inputs with conflicting id"
  """
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
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 1: duplicate input
    ---
    location: |
      line 8
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  "Multiple outputs with conflicting id"
  """
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
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 1: duplicate output
    ---
    location: |
      line 8
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  "Long test name"
  """
  <!-- !test program cat -->
  <!-- !test in something fairly long going in here -->

      hi

  <!-- !test out something fairly long going in here -->

      hi
  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 something fairly long going in here

  # 1/1 passed
  # OK

  """

txm-expect do
  "Test name in Unicode"
  """
  <!-- !test program cat -->
  <!-- !test in 本当にいいんですか -->

      hi

  <!-- !test out 本当にいいんですか -->

      hi
  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 本当にいいんですか

  # 1/1 passed
  # OK

  """

txm-expect do
  "Whitespace at ends is ignored when matching inputs and outputs"
  """
  <!-- !test program cat -->
  <!-- !test in           spacing         -->

      hi

  <!-- !test out spacing-->

      hi
  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 spacing

  # 1/1 passed
  # OK

  """

txm-expect do
  "Whitespace inside input/output name is significant"
  """
  <!-- !test program cat -->
  <!-- !test in big cat -->

      hi

  <!-- !test out big               cat -->

      hi
  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 big cat: no output defined
    ---
    location: |
      line 4
    how to fix: |
      Define an output for 'big cat', using <!-- !test out big cat -->,
      followed by a code block.
    ---

  # FAILED TO PARSE TESTS

  """


txm-expect do
  "Escaping dashes works in all commands"
  """
  <!-- !test program echo -\\-version > /dev/null ; cat -->
  <!-- !test in \\-\\- -->

      hi

  <!-- !test out -\\- -->

      hi
  """
  exit: 0
  stdout: """
  TAP version 13
  1..1
  ok 1 --

  # 1/1 passed
  # OK

  """

txm-expect do
  "tests continue when test program fails"
  """
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
  exit: 1
  stdout: """
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
    ---

  # 0/2 passed
  # FAILED 2

  """

txm-expect do
  "unknown command"
  """
  <!-- !test program cat -->
  <!-- !test something x -->

      hi

  <!-- !test out x -->

      hi
  """
  exit: 2
  stdout: """
  TAP version 13
  0..0
  not ok 0 'something': unknown command type
    ---
    location: |
      line 2
    supported commands:
      - in
      - out
      - program
    ---

  # FAILED TO PARSE TESTS

  """

txm-expect do
  "empty stdout and stderr are rendered in YAML as empty string"
  """
  <!-- !test program exit 1 -->
  <!-- !test in my test -->

      hi

  <!-- !test out my test -->

      hi
  """
  exit: 1
  stdout: """
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
    ---

  # 0/1 passed
  # FAILED 1

  """
