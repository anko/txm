#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test specs
# or rest results.  Run the tests and check that their outputs match the
# results.

require! <[ fs unified remark-parse parse5 minimist async ]>
{ exec } = require \child_process

argv = (require \minimist) (process.argv.slice 2), { +boolean }

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

        e, outputs <- async-map queue, ({ program, spec }, cb) ->
          exec program, cb
            ..stdin.end spec

        if e then throw e

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
  p = new parse5.SAXParser!
    ..on \comment -> comments.push it
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

      if state.spec-name

        name = state.spec-name
        state.spec-name := null

        if state.specs[name]
          die "Multiple inputs with name `#name`"

        state.specs[name] = node.value


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

        state.results[name] = node.value

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
    ..on \error (e) -> die e
    ..pipe concat (data) ->
      test-this data
else
  files |> each (file) ->
    e, data <- fs.read-file file
    throw e if e
    test-this data
