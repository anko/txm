#!/usr/bin/env lsc
{ exec-sync } = require \child_process
test = require \tape

txm = (md-string) ->
  try
    return stdout : exec-sync "./index.ls" { input : md-string }
  catch e
    return e

# Asserts that the given markdown's tests should PASS in txm.
passes = (name, md-string, expected-stdout, expected-stderr) ->
  test name, (t) ->
    { stdout, status, stderr } = txm md-string

    t.not-ok status, "Error code indicates success"

    if expected-stdout
      stdout.to-string! `t.equals` expected-stdout
    if expected-stderr
      stderr?to-string! `t.equals` expected-stderr

    t.end!

# Asserts that the given markdown's tests should FAIL in txm.
fails = (name, md-string, expected-stdout, expected-stderr) ->
  test name, (t) ->
    { stdout, status, stderr } = txm md-string

    t.ok status, "Error code indicates error happened"

    if expected-stdout
      stdout.to-string! `t.equals` expected-stdout
    if expected-stderr
      stderr?to-string! `t.equals` expected-stderr

    t.end!

#
# These tests are so meta.
#

passes do
  "simple cat passthrough"
  """
  <!-- !test program cat -->
  <!-- !test input 1 -->

      hi

  <!-- !test output 1 -->

      hi

  """
  """
  TAP version 13
  # testxmd test
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """

fails do
  "no program specified"
  """
  <!-- !test input 1 -->

      hi

  <!-- !test output 1 -->

      hi

  """
  "" # No stdout
  "Input and output `1` matched, but no program given yet\n"

fails do
  "input without matching output"
  """
  <!-- !test program cat -->
  <!-- !test input 1 -->

      hi
  """
  "" # No stdout
  "No matching output for input `1`\n"

fails do
  "output without matching input"
  """
  <!-- !test program cat -->
  <!-- !test output 1 -->

      hi
  """
  "" # No stdout
  "No matching input for output `1`\n"

passes do
  "redirection in program"
  """
  # whatxml

  XML/HTML templating with [LiveScript][1]'s [cascade][2] syntax.

  <!-- !test program
  sed '1s/^/console.log("hi");/' \\
  | node \\
  | head -c -1
  -->

  <!-- !test input 1 -->
  ```ls
  console.log("yo");
  ```

  To get this:

  <!-- !test output 1 -->
  ```html
  hi
  yo
  ```
  """

passes do
  "output defined before input"
  """
  <!-- !test program cat -->
  <!-- !test output 1 -->

      hi

  <!-- !test input 1 -->

      hi

  """
  """
  TAP version 13
  # testxmd test
  ok 1 should be equal

  1..1
  # tests 1
  # pass  1

  # ok


  """
  ""
