#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test specs
# or rest results.  Run the tests and check that their outputs match the
# results.

require! <[ fs os unified remark-parse yargs async ]>
sax-parser = require \parse5-sax-parser
{ exec } = require \child_process

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

{ queue-test, run-tests } =
  switch argv.format
  | \tap => fallthrough
  | otherwise =>
    test = require \tape

    queue = []

    queue-test : -> queue.push it
    run-tests : ->
      try

        async-map = if argv.series then async.map-series else async.map

        e, outputs <- async-map queue, ({ name, program, spec }, cb) ->
          errored-out = false
          result-callback = (e, output) ->
            unless e then cb ...
            else
              e.message = "Error in '#name':\n#{e.message}"
              cb e
          exec program, result-callback
            ..stdin .on \error ->
              if it.code is \EPIPE
                void # do nothing
              else throw it

            unless errored-out
              ..stdin.end spec

        if e then die e.message

        queue.for-each (queued-test, index) ->

          output = outputs[index]

          test queued-test.name, (t) ->
            t.equals do
              output.to-string!
              queued-test.result
            t.end!

      catch e
        die e

{ each, map, fold, unwords, keys, first } = require \prelude-ls
concat = require \concat-stream

die = (message) ->
  console.error message
  process.exit 1

extract-html-comments = (input) ->
  comments = []
  p = new sax-parser!
    ..on \comment ->
      # TODO use it.sourceCodeLocation for better error reporting?
      comments.push it.text
    ..end input
  return comments

# Consecutive dashes are illegal inside HTML comments, so let's allow them to
# be escaped in the "program" command.
unescape = (script) -> script.replace /\\(.)/g -> &1

test-this = (contents) ->

  state =
    program     : null
    spec-name   : null
    result-name : null
    specs       : {}
    results     : {}

  die-if-have-spec-or-result = ->
    if state.spec-name? or state.result-name?
      die "Consecutive spec or result commands"

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

          actions =
            program : -> state.program := it
            in      : -> die-if-have-spec-or-result! ; state.spec-name   := it
            out     : -> die-if-have-spec-or-result! ; state.result-name := it

          command-words = command .split /\s+/
          first-word    = first command-words

          if actions[first-word]
            rest = command |> (.slice first-word.length)
                           |> (.trim!)
                           |> unescape
            that rest

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

      if state.spec-name

        name = state.spec-name
        state.spec-name := null

        if state.specs[name]
          die "Multiple inputs with name `#name`"

        state.specs[name] = text-content


        if state.results[name] # corresponding result has been found
          if not state.program
            die "Input and output `#name` matched, but no program given yet"
          return [
            {
              name      : name
              program   : state.program
              spec      : state.specs[name]
              result    : state.results[name]
            }
          ]


      else if state.result-name

        name = state.result-name
        state.result-name := null

        if state.results[name]
          die "Multiple outputs with name `#name`"

        state.results[name] = text-content

        if state.specs[name] # corresponding spec has been found
          if not state.program
            die "Input and output `#name` matched, but no program given yet"
          return [
            {
              name      : name
              program   : state.program
              spec      : state.specs[name]
              result    : state.results[name]
            }
          ]

      return []

    else if \children of node
      node.children |> map visit |> fold (++), []
    else []

  mdast-syntax-tree = unified!
    .use remark-parse
    .parse contents
  tests = visit mdast-syntax-tree

  # Inspect state as it was left, to check for inputs and outputs that weren't
  # matched.
  state.specs |> keys |> each (k) ->
    if not state.results[k]
      die "No matching output for input `#k`"
  state.results |> keys |> each (k) ->
    if not state.specs[k]
      die "No matching input for output `#k`"


  tests |> each queue-test

  run-tests!

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
