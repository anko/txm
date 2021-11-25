import os from 'os'

import { unified } from 'unified'
import remarkParse from 'remark-parse'
import async from 'async'
import supportsColor from 'supports-color'
import color from 'kleur'
import { exec } from 'child_process'
import DMP from 'diff-match-patch'

import { readFileSync } from 'fs'
const homepageLink = JSON.parse(readFileSync('./package.json')).homepage

color.enabled = supportsColor.stdout

const dmp = new DMP()

const exitCode = {
  SUCCESS: 0,
  TEST_FAILURE: 1,
  FORMAT_ERROR: 2,
  INTERNAL_ERROR: 3
}

const ANY_NONZERO_EXIT_MARKER = 'nonzero'

const runTests = (queue, options) => {
  try {

    if (queue.length === 0) {
      console.log(color.yellow("1..0"))
      console.log(color.yellow("# no tests"))
      console.log(color.dim("# For help, see " + homepageLink))
      process.exit(exitCode.SUCCESS)
    }

    // Print test plan
    console.log(color.dim("1.." + queue.length));
    let nSuccesses = 0
    let nFailures = 0
    let nSkipped = 0

    // Challenge:  Results of parallel operations may arrive out-of-order, but
    // we want them to always print their results in order.
    //
    // Solution:  Every time a result arrives, if it is not next in line to
    // print, save it as waiting, by its index.  If the arriving result is next
    // in line, print it, and all consecutive-index results after it in the
    // waiting cache.
    const printsWaiting = []
    let indexThatMayPrint = 0
    const printWhenOurTurn = (index, text) => {
      if (index === indexThatMayPrint) {
        // Everything before us has been printed.  We can go ahead.
        if (text !== undefined) console.log(text)
        const nextWaiting = printsWaiting[++indexThatMayPrint]
        if (nextWaiting) printWhenOurTurn(indexThatMayPrint, nextWaiting)
      } else {
        // It's not our turn yet.  Wait in line for someone else to call us.
        printsWaiting[index] = text
      }
    }
    const succeed = (index, name, properties) => {
      ++nSuccesses
      printWhenOurTurn(index, successText(index + 1, name))
    }
    const fail = (index, name, failureReason, properties) => {
      ++nFailures
      printWhenOurTurn(index,
        failureText(index + 1, name, failureReason, properties))
    }
    const skip = (index, name) => {
      ++nSkipped
      printWhenOurTurn(index, undefined)
    }

    const normaliseTest = (t) => {
      // Turn lists of x into just x, so everything is neater.

      function getIfHas (prop) {
        return x => x[prop] && x[prop][0]
      }

      const validInput = getIfHas('input')
      const validOutput = getIfHas('output')
      const validError = getIfHas('error')
      const validCheck = getIfHas('check')
      const validProgram = (test) => test.program[0]
      const validExit = getIfHas('exit')
      const validOnly = getIfHas('only')

      const normalised = {
        name: t.name,
        program: validProgram(t),
        exit: validExit(t),
        only: validOnly(t),
      }
      let that
      if (that = validInput(t)) normalised.input = that
      if (that = validOutput(t)) normalised.output = that
      if (that = validError(t)) normalised.error = that
      if (that = validCheck(t)) normalised.check = that
      return normalised
    }

    const makeColouredDiff = (expected, actual) => {
      if (!color.enabled) return { expected, actual }

      const diff = dmp.diff_main(expected, actual)
      dmp.diff_cleanupSemantic(diff);

      const withVisibleNewlines = (text) =>
        text.replace(new RegExp(os.EOL, 'g'), (x) => `↵${x}`)

      const changeType = { NONE: 0, ADDED: 1, REMOVED: -1 }

      const highlightedExpected = diff.reduce(
        (textSoFar, [change, text]) => {
          switch (change) {
            case changeType.NONE:
              return textSoFar + text
            case changeType.ADDED:
              return textSoFar
            case changeType.REMOVED:
              return textSoFar + color.strikethrough(color.inverse(color.red(
                withVisibleNewlines(text))))
          }
        }, '')

      const highlightedActual = diff.reduce(
        (textSoFar, [change, text]) => {
          switch (change) {
            case changeType.NONE:
              return textSoFar + text
            case changeType.ADDED:
              return textSoFar + color.inverse(color.green(
                withVisibleNewlines(text)))
            case changeType.REMOVED:
              return textSoFar
          }
        }, '')
      return {
        expected: highlightedExpected,
        actual: highlightedActual,
      }
    }

    const collectAnnotationLocations = (test, annotationTypes) => {
      const locations = {}
      annotationTypes = annotationTypes
        || ['input', 'output', 'error', 'check', 'program', 'exit']

      for (let type of annotationTypes) {
        if (test[type]) {
          if (test[type].length) {
            let annotationsOfType = test[type].filter((x) => x)
            if (annotationsOfType.length > 1) {
              locations[`${type} locations`] = annotationsOfType
                .filter((x) => x)
                .map((x) => formatPosition(x.position))
            } else if (annotationsOfType.length === 1) {
              locations[`${type} location`] =
                formatPosition(annotationsOfType[0].position)
            }
          } else {
            locations[`${type} location`] = formatPosition(test[type].position)
          }
        }
      }
      return locations
    }

    const someTestsHaveOnlyMarker = queue.find(test => test.only)

    return async.eachOfLimit(queue, options.jobs, (test, index, cb) => {

      // If some tests are marked 'only', skip tests without that marker.
      if (someTestsHaveOnlyMarker) {
        if (!test.only) {
          skip(index, test.name)
          return cb()
        }
      }

      // Handle invalid 'program'
      if (!test.program[0]) {
        const debugProperties = Object.assign(
          collectAnnotationLocations(test),
          { 'how to fix':
            'Declare a test program before your test,'
            + `\nusing <!-- !test program <TEST PROGRAM HERE> -->` })

        fail(index, test.name, "no program defined", debugProperties)
        return cb()
      }

      // Handle ambiguous multiple exit codes
      if (test.exit && test.exit.length > 1) {
        fail(index, test.name, 'multiple expected exit statuses defined',
          Object.assign(
            collectAnnotationLocations(test, ['exit']), {
              'how to fix': 'Have just 1 expected exit status, before one of'
                + '\nthis test\'s \'!test\' commands.'
            }))
        return cb()
      }

      // Handle invalid combinations with 'check'
      if (test.check) {

        for (let type of ['input', 'output', 'error']) {
          if (test[type]) {
            fail(index, test.name, `defined as check, but also has ${type}`,
              Object.assign(
                collectAnnotationLocations(test, [type, 'check']),
                { 'how to fix':
                  `Remove the ${type}, or create an in/out test instead.` }))
            return cb()
          }
        }

        if (test.check.length > 1) {
          fail(index, test.name, 'multiple checks defined',
            Object.assign(
              collectAnnotationLocations(test, ['check']),
              { 'how to fix': 'Remove or rename the other checks.' }))
          return cb()
        }
      } else {
        // Handle missing 'in'
        if (!test.input || test.input.length === 0) {
          const debugProperties = collectAnnotationLocations(test, ['output'])
          debugProperties['how to fix'] =
            `Define an input for '${test.name}', using`
            + `\n\n  <!-- !test in ${test.name} -->`
            + `\n\nfollowed by a code block.`
          fail(index, test.name, 'input not defined', debugProperties)
          return cb()
        }

        const noOut = !test.output || test.output.length === 0
        const noErr = !test.error || test.error.length === 0
        if (noOut && noErr) {
          const debugProperties = collectAnnotationLocations(test, ['input'])
          debugProperties['how to fix'] =
            `Define an output or error for '${test.name}', using`
            + `\n\n  <!-- !test out ${test.name} -->`
            + `\n\nor\n\n  <!-- !test err ${test.name} -->`
            + `\n\nfollowed by a code block.`
          fail(index, test.name, 'only input defined', debugProperties)
          return cb()
        }

        if (test.input && test.input.length > 1) {
          const debugProperties = collectAnnotationLocations(test)
          debugProperties['how to fix'] = 'Remove or rename the other inputs.'

          fail(index, test.name, "multiple inputs defined", debugProperties)
          return cb()
        }

        if (test.output && test.output.length > 1) {
          const debugProperties = collectAnnotationLocations(test)
          debugProperties['how to fix'] = 'Remove or rename the other outputs.'

          fail(index, test.name, "multiple outputs defined", debugProperties)
          return cb()
        }

        if (test.error && test.error.length > 1) {
          const debugProperties = collectAnnotationLocations(test)
          debugProperties['how to fix'] = 'Remove or rename the other errors.'

          fail(index, test.name, "multiple errors defined", debugProperties)
          return cb()
        }
      }

      // Alright, we've handled all possible errors; we can now collapse the
      // test from its parsed form into its normalised form.
      test = normaliseTest(test)

      const resultCallback = (e, stdout, stderr) => {
        if (e) {
          if (
            // It's an error if one of the following is true:
            // - We want to see a nonzero exit code, but it's zero
            (test.exit && test.exit.code === ANY_NONZERO_EXIT_MARKER &&
              e.code === 0) ||
            // We want to see a specific exit code, but it's not this one
            (test.exit && test.exit.code !== e.code) ||
            // We aren't awaiting a particular one, but it's non-zero
            (!test.exit && e.code !== 0)
          ) {
            const failureData = {}
            failureData.program = test.program.code
            failureData['exit status'] = e.code
            if (test.exit) failureData['expected exit status'] = test.exit.code
            failureData.stderr = stderr,
            failureData.stdout = stdout
            let wording = 'error'
            if (test.exit) {
              if (test.exit.code === ANY_NONZERO_EXIT_MARKER) {
                wording = 'unexpected success'
              } else {
                wording = 'unexpected exit status'
              }
            }
            fail(index, test.name, `program exited with ${wording}`,
              Object.assign(failureData, collectAnnotationLocations(test)))
            return cb()
          }
        }

        if (test.check) {
          succeed(index, test.name)
          return cb()
        }

        if (('output' in test) && stdout !== test.output.text) {
          const {expected, actual} = makeColouredDiff(test.output.text, stdout)
          fail(index, test.name, 'output mismatch',
            Object.assign({
              'expected stdout': expected,
              'actual stdout': actual,
              program: test.program.code,
              'stderr': stderr,
            }, collectAnnotationLocations(test)))
          return cb()
        }

        if (('error' in test) && stderr !== test.error.text) {
          const {expected, actual} = makeColouredDiff(test.error.text, stderr)
          fail(index, test.name, 'error mismatch',
            Object.assign({
              'expected stderr': expected,
              'actual stderr': actual,
              program: test.program.code,
              'stdout': stdout,
            }, collectAnnotationLocations(test)))
          return cb()
        }

        // Got this far, must have been OK.
        succeed(index, test.name)
        return cb()
      }

      const subprocessOptions = {
        env: Object.assign({
          'TXM_INDEX': index + 1,
          'TXM_NAME': test.name,
          'TXM_INDEX_FIRST': 1,
          'TXM_INDEX_LAST': queue.length,
          'TXM_HAS_COLOR': color.enabled ? 1 : 0,
          'TXM_HAS_COLOUR': color.enabled ? 1 : 0,
        }, process.env)
      }
      if (test.input && test.input.lang)
        subprocessOptions.env['TXM_INPUT_LANG'] = test.input.lang
      else if (test.check && test.check.lang)
        subprocessOptions.env['TXM_INPUT_LANG'] = test.check.lang

      const subprocess = exec(
        test.program.code, subprocessOptions, resultCallback);
      // Swallow EPIPE errors.  These can happen when the subprocess closes its
      // stdin before we manage to write to it.  It's not a problem if it does:
      // the subprocess just doesn't want any more input.
      subprocess.stdin.on('error', (e) => {
        // Seems to be non-deterministic and normal, so it's hard to replicate
        // in tests, so ignore in coverage.
        /* c8 ignore next */
        if (e.code !== 'EPIPE') { throw e }
      })
      if (test.input) subprocess.stdin.end(test.input.text)
      else subprocess.stdin.end(test.check.text)
    }, (e) => {
      /* c8 ignore start */
      // Should never happen, but convenient for dev.
      if (e) die(e.message)
      /* c8 ignore stop */

      // Print final summary comments

      console.log()
      const colourOfState = (nFailures === 0) ? color.green : color.red
      const colourInverse = (x) => color.inverse(colourOfState(x))

      console.log(colourOfState(`# ${nSuccesses}/${queue.length} passed`))
      if (nFailures === 0){
        if (nSkipped === 0) {
          console.log(colourInverse('# OK'))
        } else {
          console.log(color.inverse(color.yellow(`# OK, SKIPPED ${nSkipped}`)))
        }
      }
      else {
        console.log(colourInverse(`# FAILED ${nFailures}`))
        process.exit(exitCode.TEST_FAILURE)
      }
    })
  } catch (e) /* c8 ignore start */ {
    // Should never happen
    die(e)
  } /* c8 ignore stop */
}

const extractHtmlComments = function(input, nodePositionInMarkdown){
  // Reference: https://html.spec.whatwg.org/#comments
  //
  // Comments are generally `<!-- stuff -->`, where `stuff` is disallowed from
  // containing the ending delimiter.  However, the comment delimiters may also
  // occur inside CDATA blocks, where we do *not* want to parse them.

  const comments = []

  const CDATA_OPENER = '<![CDATA['
  const CDATA_CLOSER = ']]>'
  const COMMENT_OPENER = '<!--'
  const COMMENT_CLOSER = '-->'
  const IN_CDATA = Symbol('parser in CDATA')
  const IN_COMMENT = Symbol('parser in comment')
  const BASE = Symbol('parser in base state')
  let state = BASE
  let nextIndex = 0
  let done = false

  while (!done) {
    const rest = input.slice(nextIndex)

    switch (state) {
      case BASE:
        // Parse the rest of whichever we see first.  CDATA "swallows"
        // comments, and vice-versa.
        const cdataIndex = rest.indexOf(CDATA_OPENER)
        const commentIndex = rest.indexOf(COMMENT_OPENER)

        if (cdataIndex === -1 && commentIndex === -1) { // No more of either; done
          done = true
        } else if (cdataIndex === -1 && commentIndex >= 0) { // Comment only
          state = IN_COMMENT
          nextIndex += commentIndex
        } else if (cdataIndex >= 0 && commentIndex === -1) { // CDATA only
          state = IN_CDATA
          nextIndex += cdataIndex
        } else { // Matched both.  Go with the earlier one.
          if (cdataIndex < commentIndex) { // CDATA earlier
            state = IN_CDATA
            nextIndex += cdataIndex
          } else { // Comment earlier
            state = IN_COMMENT
            nextIndex += commentIndex
          }
        }
        break

      case IN_COMMENT: {
        // Parse end of comment
        const closerIndex = rest.indexOf(COMMENT_CLOSER)
        if (closerIndex >= 0) {
          comments.push(rest.slice(0, closerIndex))
          nextIndex += closerIndex
          state = BASE
        } else {
          // Unterminated comment
          const openerIndex = input.slice(nextIndex)
          const line = input.slice(0, nextIndex).split('\n').length
            + nodePositionInMarkdown.start.line - 1
          parsingError(`'<!--'`, 'unterminated HTML comment', {
            location: formatPosition({ start: { line }, end: { line } }),
            'how to fix': `Terminate the comment with '-->' where appropriate.`
              + `\nCheck that '-->' doesn't occur anywhere unexpected.`
          })
        }
        break
      }

      case IN_CDATA: {
        // Parse end of CDATA
        const closerIndex = rest.indexOf(CDATA_CLOSER)
        if (closerIndex >= 0) {
          nextIndex += closerIndex
          state = BASE
        } else {
          // Unterminated CDATA
          const line = input.slice(0, nextIndex).split('\n').length
            + nodePositionInMarkdown.start.line - 1
          parsingError(`'<![CDATA['`, 'unterminated HTML CDATA section', {
            location: formatPosition({ start: { line }, end: { line } }),
            'how to fix': `Terminate the CDATA section with ']]>'`
              + ` where appropriate.`
              + `\nCheck that ']]>' doesn't occur anywhere unexpected.`
          })
        }
        break
      }
    }
  }

  return comments
};

/*
  Consecutive dashes ("--") are illegal inside HTML comments, so let's allow
  them to be escaped with the sequence "\-".  We treat "\-" like a single token
  that can be escaped ("\\-") to get a literal "\-".  This way, users can still
  write "\" in other contexts (which is common in shell scripts for the
  "program" command) without entering backslash hell.
*/
const unescape = (x) => x.replace(/#-/g, '-')

const parseAndRunTests = (text, options={jobs: 1}) => {

  // TAP header
  console.log('TAP version 13')

  /*
    A test spec is a set of program, input, and expected output.  We maintain a
    collection of the incomplete ones indexed by name (unique identifier
    decided by the user).  Whenever new information is available for the test
    spec corresponding to a name, we add that information, and when it's
    complete, delete it from the incomplete list and queue it for running.
  */
  const testSpecs = {}
  const addToTestSpec = (name, key, value) => {
    const testSpec = name in testSpecs ? testSpecs[name] : {}
    testSpecs[name] = testSpec

    const testSpecArrayForKey = testSpec[key] || []
    testSpec[key] = testSpecArrayForKey
    testSpec[key].push(value)
  }
  const setFieldInTestSpec = (name, key, value) => {
    // We can assume it exists already
    const testSpec = testSpecs[name]
    testSpecs[name] = testSpec
    testSpec[key] = [value]
  }

  const howToFixUnexpectedCommandExplanation = `Check that your`
    + ` 'in' / 'out' / 'err' / 'check'`
    + ` commands are each followed`
    + `\nby a block of code, not another test command.`

  /*
    This state machine describes the state that the parser is in.  The 'now'
    property holds its current state.  States are represented by constructor
    functions take parameters, through which data is passed when transitioning
    between states.

    Each state can react to texts (i.e. code blocks) or commands (i.e. HTML
    comments containing "!test" commands) in whatever way is appropriate for
    that state.
  */
  const parseStateMachine = {
    waitingForAnyCommand: ({program, exit, only}) => {
      return {
        gotText: () => {},
        gotCommand: (name, text, position) => {
          switch (name) {
            case 'program':
              parseStateMachine.now = parseStateMachine.waitingForAnyCommand(
                { program: { code: text, position: position }, exit, only })
              break
            case 'exit':
              text = text.trim()
              if (text.match(/[0-9]+/)) {
                const code = Number.parseInt(text)
                parseStateMachine.now = parseStateMachine.waitingForAnyCommand(
                  { exit: { code, position: position }, program, only })
              } else if (text === 'nonzero') {
                parseStateMachine.now =
                  parseStateMachine.waitingForAnyCommand({
                    exit: {
                      code: ANY_NONZERO_EXIT_MARKER,
                      position: position },
                    program,
                    only,
                  })
              } else {
                parsingError(`'${name} ${text}'`,
                  `bad exit code specified`, {
                    location: formatPosition(position),
                    'how to fix': 'Use an integer >=0, or the word'
                      + ' \'nonzero\',\nto accept any non-zero exit code'
                  })
              }
              break
            case 'only':
              parseStateMachine.now = parseStateMachine.waitingForAnyCommand(
                { program, exit, only: { position } })
              break
            case 'in':
              parseStateMachine.now = parseStateMachine.waitingForInputText(
                { program, exit, only, name: text })
              break
            case 'out':
              parseStateMachine.now = parseStateMachine.waitingForOutputText(
                { program, exit, only, name: text })
              break
            case 'err':
              parseStateMachine.now = parseStateMachine.waitingForErrorText(
                { program, exit, only, name: text })
              break
            case 'check':
              parseStateMachine.now = parseStateMachine.waitingForCheckText(
                { program, exit, only, name: text })
              break
          }
        }
      }
    },
  }

  const capitalise = (text) => text.replace(/./, (x) => x.toUpperCase())

  // Construct state-machine states for each of the states where we're
  // expecting to next see a code block.
  for (let annotationType of ['input', 'output', 'error', 'check']) {
    parseStateMachine[`waitingFor${capitalise(annotationType)}Text`] =
      ({program, name, exit, only}) => {
        return {
          gotText: (text, position, lang) => {
            // The exit code only applies to this test, not continuously, so
            // don't pass it back to the `waitingForAnyCommand` state.
            parseStateMachine.now =
              parseStateMachine.waitingForAnyCommand({ program })
            addToTestSpec(name, annotationType, {text, position, lang})
            setFieldInTestSpec(name, 'program', program)
            if (exit) addToTestSpec(name, 'exit', exit)
            if (only) addToTestSpec(name, 'only', only)
          },
          gotCommand: (name, text, position) => {
            parsingError(`'${name} ${text}'`,
              `unexpected command (expected ${annotationType} text)`, {
                location: formatPosition(position),
                'how to fix': howToFixUnexpectedCommandExplanation
              })
          }
        }
      }
  }
  // Initial state
  parseStateMachine.now =
    parseStateMachine.waitingForAnyCommand({ program: null })

  const visitMarkdownNode = (node) => {

    if (node.type === 'html') {
      extractHtmlComments(node.value, node.position).forEach((comment) => {

        // Optional whitespace, followed by '!test', more optional whitespace,
        // then the commands we actually care about.
        const re = /(?:\s+)?!test\s+([\s\S]*)/m;
        const match = comment.trim().match(re)
        if (match) {
          const [, command] = match
          const commandWords = command.split(/\s+/)
          const firstWord = commandWords[0]
          const supportedCommands = [
            'program', 'in', 'out', 'err', 'check', 'exit', 'only'
          ]
          if (supportedCommands.includes(firstWord)) {
            const rest = unescape(command.slice(firstWord.length).trim())
            parseStateMachine.now.gotCommand(firstWord, rest, node.position)
          } else {
            parsingError(`'${firstWord}'`, 'unknown command type', {
              location: formatPosition(node.position),
              'supported commands': supportedCommands
            })
          }
        }
      })
    } else if (node.type === 'code') {
      const text = node.value + os.EOL
      parseStateMachine.now.gotText(text, node.position, node.lang)
    } else if ('children' in node) {
      node.children.forEach(visitMarkdownNode)
    }
  }

  const mdastSyntaxTree = unified().use(remarkParse).parse(text)
  visitMarkdownNode(mdastSyntaxTree)

  const tests = []
  for (let name in testSpecs) {
    const test = Object.assign({name}, testSpecs[name])
    tests.push(test)
  }
  runTests(tests, options)
}

//
// Helpers
//

var type = (obj) => Object.prototype.toString.call(obj).slice(8, -1)

const repeatString = (str, n) => {
  let out = ''
  while (n-- > 0) out += str
  return out
}

/* c8 ignore start */
function die (message) {
  // For fatal errors.  When possible, fail through 'parsingError', since that
  // still outputs valid TAP.
  console.error(message)
  process.exit(exitCode.INTERNAL_ERROR)
}
/* c8 ignore stop */

const formatPosition = (position) => {
  const pos = {
    start: position.start.line,
    end: position.end.line
  }
  return (pos.start === pos.end)
    ? `line ${pos.start}` : `lines ${pos.start}-${pos.end}`
}
const indent = (n, text) => {
  const spaces = repeatString('  ', n)
  return text
    .split(os.EOL)
    .map((line) => line.length ? `${spaces}${line}` : line)
    .join(os.EOL)
}
const formatProperties = (properties, indentLevel=0) => {
  const horizontalRule = indent(indentLevel, color.dim("---"))
  let text = horizontalRule

  for (let [key, value] of Object.entries(properties)) {
    text += '\n' + indent(indentLevel, `${color.blue(key)}:`)
    switch (type(value)) {
      case 'Array':
        for (let v of value)
          text += '\n' + indent(indentLevel + 1, `- ${v.toString()}`)
        break
      case 'Number':
        text += ' ' + value.toString();
        break;
      case 'String':
        if (value === '') text += " ''"
        else text += ' |\n' + indent(indentLevel + 1, value)
        break
      /* c8 ignore start */
      // Should never happen, but this is convenient while developing.
      default:
        throw Error(`Unexpected property type ${type(value)}:`
          + `${JSON.stringify(value)}`)
      /* c8 ignore stop */
    }
  }
  text += "\n" + horizontalRule
  return text
}
const successText = (index, name) =>
  `${color.green('ok')} ${color.dim(index)} ${name}`
const failureText = (index, name, failureReason, properties) => {
  let text = `${color.red('not ok')} ${color.dim(index)} ${name}`
    + color.dim(`: ${failureReason}`)
  if (properties) text += "\n" + formatProperties(properties, 1)
  return text
}

const parsingError = (name, failureReason, properties) => {
  console.log(color.dim('0..0'))
  console.log(failureText(0, name, failureReason, properties))
  console.log()
  console.log(color.black(color.bgRed('# FAILED TO PARSE TESTS')))
  process.exit(exitCode.FORMAT_ERROR)
}

export default parseAndRunTests
