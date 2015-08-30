#!/usr/bin/env lsc
{ exec-sync } = require \child_process
test = require \tape

txm-expect = (name, md-string, expected-exit, expected-stdout, expected-stderr) ->

  txm = (md-string) ->
    try
      return stdout : exec-sync "./index.ls" { input : md-string }
    catch e
      return e

  test name, (t) ->
    { stdout, status, stderr } = txm md-string

    if not expected-exit then t.not-ok status  # anything falsy
    else status `t.equals` expected-exit       # specific number
    if expected-stdout
      stdout.to-string! `t.equals` expected-stdout
    if expected-stderr
      stderr?to-string! `t.equals` expected-stderr

    t.end!

txm-expect do
  "simple cat passthrough"
  """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  0
  """
  TAP version 13
  # 1
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """


txm-expect do
  "same line comments, some irrelevant"
  """
  <!-- !test program cat --><!-- !test in 1 --><!-- something else -->

      hi

  <!-- !test out 1 --><!-- hello! -->

      hi

  """
  0
  """
  TAP version 13
  # 1
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """

txm-expect do
  "no program specified"
  """
  <!-- !test in 1 -->

      hi

  <!-- !test out 1 -->

      hi

  """
  1
  "" # No stdout
  "Input and output `1` matched, but no program given yet\n"

txm-expect do
  "input without matching output"
  """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      hi
  """
  1
  "" # No stdout
  "No matching output for input `1`\n"

txm-expect do
  "output without matching input"
  """
  <!-- !test program cat -->
  <!-- !test out 1 -->

      hi
  """
  1
  "" # No stdout
  "No matching input for output `1`\n"

txm-expect do
  "redirection in program"
  """
  # whatxml

  XML/HTML templating with [LiveScript][1]'s [cascade][2] syntax.

  <!-- !test program
  sed '1s/^/console.log("hi");/' \\
  | node \\
  | head -c -1
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
  0

txm-expect do
  "output defined before input"
  """
  <!-- !test program cat -->
  <!-- !test out 1 -->

      hi

  <!-- !test in 1 -->

      hi

  """
  0
  """
  TAP version 13
  # 1
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """
  ""

txm-expect do
  "interleaved tests"
  """
  <!-- !test program cat -->
  <!-- !test in 1 -->

      one

  <!-- !test in 2 -->

      two

  <!-- !test out 1 -->

      one

  <!-- !test out 2 -->

      two

  """
  0
  """
  TAP version 13
  # 1
  ok 1 should be equal
  # 2
  ok 2 should be equal

  1..2
  # tests 2
  # pass  2

  # ok


  """
  ""

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
  1
  "" # no stdout
  "Multiple inputs with name `1`\n"

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
  1
  "" # no stdout
  "Multiple outputs with name `1`\n"

txm-expect do
  "Long test name"
  """
  <!-- !test program cat -->
  <!-- !test in something fairly long going in here -->

      hi

  <!-- !test out something fairly long going in here -->

      hi
  """
  0
  """
  TAP version 13
  # something fairly long going in here
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


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
  0
  """
  TAP version 13
  # 本当にいいんですか
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


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
  0
  """
  TAP version 13
  # spacing
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


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
  1
  ""
  "No matching output for input `big cat`\n"


txm-expect do
  "Escaping dashes works in all commands"
  """
  <!-- !test program echo -\\-version > /dev/null ; cat -->
  <!-- !test in \\-\\- -->

      hi

  <!-- !test out -\\- -->

      hi
  """
  0
  """
  TAP version 13
  # --
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """
