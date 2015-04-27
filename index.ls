#!/usr/bin/env lsc
# Parse a markdown file and check for code blocks that are marked as test specs
# or rest results.  Run the tests and check that their outputs match the
# results.

require! <[ fs mdast ]>
{ flip, each, map, fold, words } = require \prelude-ls

[ ...files ] = process.argv.slice 2

process.exit 0 unless files.length

die = (message) ->
  console.error message
  process.exit 1

# Consecutive dashes are illegal inside HTML comments, so let's allow them to
# be escaped in the "program" command.
unescape = (script) ->
  script.replace /\\(.)/g -> &1

file <- (flip each) files
e, contents <- fs.read-file file

state =
  program     : null
  spec-name   : null
  result-name : null
  specs       : {}
  results     : {}

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

      w = command .split /\s+/

      switch w.0

      | \program =>

        program = command
                  |> (.slice w.0.length)
                  |> (.trim!)
                  |> unescape

        state.program = program

      | \spec
        if state.spec-name or state.result-name
          die "Consecutive spec or result commands"
        state.spec-name = w.1

      | \result
        if state.spec-name or state.result-name
          die "Consecutive spec or result commands"
        state.result-name = w.1

    return []

  else if node.type is \code
    if state.program


      if state.spec-name

        name = state.spec-name

        state.specs[name] = node.value

        if state.results[name] # corresponding result has been found
          return [
            {
              program   : state.program
              spec      : state.specs[name]
              result    : state.results[name]
            }
          ]

        state.spec-name := null


      else if state.result-name

        name = state.result-name

        state.results[name] = node.value

        if state.results[name] # corresponding spec has been found
          return [
            {
              program   : state.program
              spec      : state.specs[name]
              result    : state.results[name]
            }
          ]

        state.result-name := null

    return []

  else if \children of node
    node.children |> map visit |> fold (++), []
  else []


if e
  console.error e
  process.exit 1

tests = visit mdast.parse contents.to-string!
tests |> each ({ program, spec, result }) ->
  console.log program
  console.log spec
  console.log result
