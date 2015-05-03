#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test specs
# or rest results.  Run the tests and check that their outputs match the
# results.

require! <[ fs mdast ]>
test = require \tape
{ each, map, fold, unwords, keys, first } = require \prelude-ls
{ exec-sync } = require \child_process
concat = require \concat-stream

die = (message) ->
  console.error message
  process.exit 1

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

  have-spec-or-result = -> state.spec-name? || state.result-name?

  visit = (node) ->
    if node.type is \html

      re = //
           <!--          # HTML comment start
           (?:\s+)?      # optional whitespace
           !test         # test command marker
           \s+           # whitespace
           ([\s\S]*)     # interesting commands
           -->           # HTML comment end
           //m

      [ _, command ] = (node.value .match re) || []

      if command

        command-words = command .split /\s+/

        switch first command-words

        | \program
          state.program = command |> (.slice that.length) # rest of command
                                  |> (.trim!)
                                  |> unescape
        | \in
          die "Consecutive spec or result commands" if have-spec-or-result!
          state.spec-name = command
                            .slice that.length # rest of command
                            .trim!
        | \out
          die "Consecutive spec or result commands" if have-spec-or-result!
          state.result-name = command
                              .slice that.length # rest of command
                              .trim!

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

  tests = visit mdast.parse contents.to-string!

  # Inspect state as it was left, to check for inputs and outputs that weren't
  # matched.
  state.specs |> keys |> each (k) ->
    if not state.results[k]
      die "No matching output for input `#k`"
  state.results |> keys |> each (k) ->
    if not state.specs[k]
      die "No matching input for output `#k`"


  tests |> each ({ name, program, spec, result : intended-output }) ->
    try
      test name, (t) ->
        output = exec-sync program, input : spec .to-string!
        t.equals output, intended-output
        t.end!

    catch e
      die e


[ ...files ] = process.argv.slice 2

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
