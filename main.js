const os = require('os');
const unified = require('unified');
const remarkParse = require('remark-parse');
const async = require('async');
const color = require('colorette');
const saxParser = require('parse5-sax-parser');
const exec = require('child_process').exec;
const dmp = new (require('diff-match-patch'))();
const homepageLink = require('./package.json').homepage;

const exitCode = {
  SUCCESS: 0,
  TEST_FAILURE: 1,
  FORMAT_ERROR: 2,
  INTERNAL_ERROR: 3
};

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
        console.log(text)
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

    const getOnlyElement = (x) => x.length === 1 ? x[0] : undefined
    const checkExistsAndGetOnlyElement = (prop) =>
      (x) => x[prop] && getOnlyElement(x[prop])

    const validInput = checkExistsAndGetOnlyElement('input')
    const validOutput = checkExistsAndGetOnlyElement('output')
    const validError = checkExistsAndGetOnlyElement('error')
    const validCheck = checkExistsAndGetOnlyElement('check')
    const validProgram = (test) => {
      const nonNullPrograms = test.program.filter((x) => x !== null)
      return nonNullPrograms[nonNullPrograms.length - 1]
    }

    const normaliseTest = (t) => {
      const normalised = {
        name: t.name,
        program: validProgram(t)
      }
      let that
      if (that = validInput(t)) normalised.input = that
      if (that = validOutput(t)) normalised.output = that
      if (that = validError(t)) normalised.error = that
      if (that = validCheck(t)) normalised.check = that
      return normalised
    }

    const earlierPosition = (a, b) => {
      if (!a) return b
      if (!b) return a
      return (a.start.offset < b.start.offset) ? a : b
    }


    const addLocationProperties = (test, obj) => {
      const locationProps = {}
      if (test.check)
        locationProps['check location'] = formatPosition(test.check.position)
      if (test.input)
        locationProps['input location'] = formatPosition(test.input.position)
      if (test.output)
        locationProps['output location'] = formatPosition(test.output.position)
      if (test.error)
        locationProps['error location'] = formatPosition(test.error.position)

      const finalProps = {}
      Object.assign(finalProps, obj)
      Object.assign(finalProps, locationProps)
      return finalProps
    }

    const makeColouredDiff = (expected, actual) => {
      if (!process.stdout.isTTY) return { expected, actual }

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

    return async.eachOfLimit(queue, options.jobs, (test, index, cb) => {

      // Handle invalid 'program'
      if (!validProgram(test)) {
        const debugProperties = {}
        const input = validInput(test)
        const output = validOutput(test)
        let earliestPositionMentioned = null

        if (input) {
          debugProperties['input location'] = formatPosition(input.position)
          earliestPositionMentioned =
            earlierPosition(input.position, earliestPositionMentioned)
        }
        if (output) {
          debugProperties['output location'] = formatPosition(output.position)
          earliestPositionMentioned =
            earlierPosition(output.position, earliestPositionMentioned)
        }
        debugProperties['how to fix'] =
          `Declare a test program before`
          + ` ${formatPosition(earliestPositionMentioned)},`
          + `\nusing <!-- !test program <TEST PROGRAM HERE> -->`
        fail(index, test.name, "no program defined", debugProperties)
        return cb()
      }

      // Handle invalid combinations with 'check'
      if (test.check) {
        if (test.input) {
          fail(index, test.name, 'defined as check, but also has input', {
            'input locations':
              test.input.map((x) => formatPosition(x.position)),
            'how to fix':
              'Remove the input, or create an in/out test instead.'
          })
          return cb()
        }
        if (test.output) {
          fail(index, test.name, 'defined as check, but also has output', {
            'output locations':
              test.output.map((x) => formatPosition(x.position)),
            'how to fix':
              'Remove the output, or create an in/out test instead.'
          })
          return cb()
        }
        if (test.error) {
          fail(index, test.name, 'defined as check, but also has error', {
            'error locations':
              test.error.map((x) => formatPosition(x.position)),
            'how to fix':
              'Remove the error, or create an in/out test instead.'
          })
          return cb()
        }
        if (test.check.length > 1) {
          fail(index, test.name, "multiple checks defined", {
            "check locations":
              test.check.map((x) => formatPosition(x.position)),
            "how to fix":
              "Remove or rename the other checks."
          })
          return cb()
        }
      } else {
        // Handle missing 'in'
        if (!test.input || test.input.length === 0) {
          const debugProperties = {}
          const output = validOutput(test)
          if (output)
            debugProperties['output location'] =
              formatPosition(output.position)

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
          const debugProperties = {}

          const input = validInput(test)
          if (input)
            debugProperties['input location'] = formatPosition(input.position)

          debugProperties['how to fix'] =
            `Define an output or error for '${test.name}', using`
            + `\n\n  <!-- !test out ${test.name} -->`
            + `\n\nor\n\n  <!-- !test err ${test.name} -->`
            + `\n\nfollowed by a code block.`
          fail(index, test.name, 'only input defined', debugProperties)
          return cb()
        }

        if (test.input && test.input.length > 1) {
          const debugProperties = {}

          const output = validOutput(test)
          if (output)
            debugProperties['output location'] =
              formatPosition(output.position)

          debugProperties['input locations'] =
            test.input.map((x) =>  formatPosition(x.position))
          debugProperties['how to fix'] = 'Remove or rename the other inputs.'

          fail(index, test.name, "multiple inputs defined", debugProperties)
          return cb()
        }

        if (test.output && test.output.length > 1) {
          const debugProperties = {}

          const input = validInput(test)
          if (input)
            debugProperties['input location'] =
              formatPosition(input.position)

          debugProperties['output locations'] =
            test.output.map((x) =>  formatPosition(x.position))
          debugProperties['how to fix'] = 'Remove or rename the other outputs.'

          fail(index, test.name, "multiple outputs defined", debugProperties)
          return cb()
        }

        if (test.error && test.error.length > 1) {
          const debugProperties = {}

          const input = validInput(test)
          if (input)
            debugProperties['input location'] =
              formatPosition(input.position)

          debugProperties['error locations'] =
            test.error.map((x) =>  formatPosition(x.position))
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
          fail(index, test.name, 'program exited with error',
            addLocationProperties(test, {
              program: test.program.code,
              'exit status': e.code,
              stderr: stderr,
              stdout: stdout
            }))
          return cb()
        }

        if (test.check) {
          succeed(index, test.name)
          return cb()
        }

        if (('output' in test) && stdout !== test.output.text) {
          const {expected, actual} = makeColouredDiff(test.output.text, stdout)
          fail(index, test.name, 'output mismatch',
            addLocationProperties(test, {
              'expected stdout': expected,
              'actual stdout': actual,
              program: test.program.code
            }))
          return cb()
        }

        if (('error' in test) && stderr !== test.error.text) {
          const {expected, actual} = makeColouredDiff(test.error.text, stderr)
          fail(index, test.name, 'error mismatch',
            addLocationProperties(test, {
              'expected stderr': expected,
              'actual stderr': actual,
              program: test.program.code
            }))
          return cb()
        }

        // Got this far, must have been OK.
        succeed(index, test.name)
        return cb()
      }

      const subprocess = exec(test.program.code, resultCallback);
      subprocess.stdin.on('error', (e) => {
        // Swallow EPIPE errors
        if (e.code !== 'EPIPE') { throw e }
      })
      if (test.input) subprocess.stdin.end(test.input.text)
      else subprocess.stdin.end(test.check.text)
    }, (e) => {
      if (e) die(e.message)

      // Print final summary comments

      console.log()
      const colour = (nFailures === 0) ? color.green : color.red
      const colourInverse = (x) => color.inverse(colour(x))

      console.log(colour(`# ${nSuccesses}/${queue.length} passed`))
      if (nFailures === 0) console.log(colourInverse('# OK'))
      else {
        console.log(colourInverse(`# FAILED ${nFailures}`))
        process.exit(exitCode.TEST_FAILURE)
      }
    })
  } catch (e) { die(e) }
}

const extractHtmlComments = function(input){
  var comments, x$, p;
  comments = [];
  x$ = p = new saxParser();
  x$.on('comment', function(it){
    return comments.push(it.text);
  });
  x$.end(input);
  return comments;
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
    waitingForProgramText: () => {
      return {
        gotText: () => {},
        gotCommand: (name, text, position) => {
          if (name === 'program') {
            parseStateMachine.now = parseStateMachine.waitingForAnyCommand(
              { program: { code: text, position: position } })
          }
        }
      }
    },
    waitingForAnyCommand: ({program}) => {
      return {
        gotText: () => {},
        gotCommand: (name, text, position) => {
          switch (name) {
            case 'program':
              parseStateMachine.now = parseStateMachine.waitingForAnyCommand(
                { program: { code: text, position: position } })
              break
            case 'in':
              parseStateMachine.now = parseStateMachine.waitingForInputText(
                { program: program, name: text })
              break
            case 'out':
              parseStateMachine.now = parseStateMachine.waitingForOutputText(
                { program: program, name: text })
              break
            case 'err':
              parseStateMachine.now = parseStateMachine.waitingForErrorText(
                { program: program, name: text })
              break
            case 'check':
              parseStateMachine.now = parseStateMachine.waitingForCheckText(
                { program: program, name: text })
          }
        }
      };
    },
    waitingForInputText: ({program, name}) => {
      return {
        gotText: (text, position) => {
          parseStateMachine.now =
            parseStateMachine.waitingForAnyCommand({program})
          addToTestSpec(name, 'input', { text, position })
          addToTestSpec(name, 'program', program)
        },
        gotCommand: (name, text, position) => {
          parsingError(`'${name} ${text}'`,
            'unexpected command (expected input text)', {
              location: formatPosition(position),
              'how to fix': howToFixUnexpectedCommandExplanation
            })
        }
      }
    },
    waitingForOutputText: ({program, name}) => {
      return {
        gotText: (text, position) => {
          parseStateMachine.now =
            parseStateMachine.waitingForAnyCommand({ program })
          addToTestSpec(name, 'output', {text, position})
          addToTestSpec(name, 'program', program)
        },
        gotCommand: (name, text, position) => {
          parsingError(`'${name} ${text}'`,
            'unexpected command (expected output text)', {
              location: formatPosition(position),
              'how to fix': howToFixUnexpectedCommandExplanation
            })
        }
      };
    },

    waitingForErrorText: ({program, name}) => {
      return {
        gotText: (text, position) => {
          parseStateMachine.now =
            parseStateMachine.waitingForAnyCommand({ program })
          addToTestSpec(name, 'error', {text, position})
          addToTestSpec(name, 'program', program)
        },
        gotCommand: (name, text, position) => {
          parsingError(`'${name} ${text}'`,
            'unexpected command (expected error text)', {
              location: formatPosition(position),
              'how to fix': howToFixUnexpectedCommandExplanation
            })
        }
      };
    },

    waitingForCheckText: ({program, name}) => {
      return {
        gotText: (text, position) => {
          parseStateMachine.now =
            parseStateMachine.waitingForAnyCommand({ program })
          addToTestSpec(name, 'check', {text, position})
          addToTestSpec(name, 'program', program)
        },
        gotCommand: (name, text, position) => {
          parsingError(`'${name} ${text}'`,
            'unexpected command (expected check text)', {
              location: formatPosition(position),
              'how to fix': howToFixUnexpectedCommandExplanation
            })
        }
      };
    }
  }
  // Initial state
  parseStateMachine.now =
    parseStateMachine.waitingForAnyCommand({ program: null })

  const visitMarkdownNode = (node) => {

    if (node.type === 'html') {
      extractHtmlComments(node.value).forEach((comment) => {

        // Optional whitespace, followed by '!test', more optional whitespace,
        // then the commands we actually care about.
        const re = /(?:\s+)?!test\s+([\s\S]*)/m;
        const match = comment.trim().match(re)
        if (match) {
          const [, command] = match
          const commandWords = command.split(/\s+/)
          const firstWord = commandWords[0]
          const supportedCommands = ['program', 'in', 'out', 'err', 'check']
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
      parseStateMachine.now.gotText(text, node.position)
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

const die = (message) => {
  // For fatal errors.  When possible, fail through 'parsingError', since that
  // still outputs valid TAP.
  console.error(message)
  process.exit(exitCode.INTERNAL_ERROR)
}

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
  var i$, len$, v;

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
      default:
        text += '\n' + indent(indentLevel + 1, value.toString())
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

module.exports = parseAndRunTests
