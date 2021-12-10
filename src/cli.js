#!/usr/bin/env node
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { readFileSync } from 'fs'
import { fileURLToPath } from 'node:url'

import parseAndRunTests from './main.js'

const thisFilePath = fileURLToPath(import.meta.url)
const rootDir = path.resolve(path.dirname(thisFilePath), '..')

const packageMetadata = JSON.parse(readFileSync(
  path.join(rootDir, 'package.json')))
const { version } = packageMetadata

// Determine program name for use in usage help text.  We can parse
// `package.json` metadata to keep it the "single source of truth".
const programName = (() => {
  for (let [name, binPath] of Object.entries(packageMetadata.bin)) {
    const binPathAbsolute = path.resolve(rootDir, binPath)
    if (binPathAbsolute === thisFilePath) return name
  }
  /* c8 ignore next */
  throw Error('No package.json bin matches this file!')
})()

// The possible properties here:
//
// • describe: a function outputting a string array [usage_summary, description,
//   default_value].
// • defaultValue: self-explanatory (optional)
// • eat: a function that parses the option's value(s) out of the arguments
//   array at the given index
const possibleOptions = {
  '--jobs': {
    describe: (name, defaultValue) =>
      [ `${name} <n>`,
        'How many tests may run in parallel',
        `# of CPU cores; here ${defaultValue}` ],
    defaultValue: os.cpus().length,
    eat: (args, index, name) => {
      const value = JSON.parse(args[++index])
      if (Number.isInteger(value) && value >= 1) {
        return { ok: true, value, index }
      } else {
        return {
          ok: false,
          value: `Invalid '${name}' value '${value}' (expected integer >= 1)`
        }
      }
    }
  },
  '--version': {
    describe: name => [name, 'Show version number'],
    eat: () => {
      console.log(version)
      process.exit(0)
    }
  },
  '--help': {
    describe: name => [name, 'Show help'],
    eat: () => {
      printUsageHint(process.stdout)
      process.exit(0)
    }
  },
}

// Parse files and option flags out of the script arguments, according to those
// specified in the `possibleOptions` object.
const { files, options } = (() => {
  const args = process.argv.slice(2) // strip 'node' and '<script-name>.js'

  const files = []
  const options = Object.entries(possibleOptions)
    .reduce((options, [k, v]) => {
      options[k] = v.defaultValue
      return options
    }, {})

  for (let i = 0; i < args.length; ++i) {
    const name = args[i]
    const spec = possibleOptions[name]
    if (spec) {
      const { ok, value, index } = spec.eat(args, i, name)
      if (ok) {
        options[name] = value
        i = index
      } else {
        process.stderr.write(`${value}\n`)
        process.exit(2)
      }
    } else {
      files.push(name)
    }
  }

  // Check we have just 1 file.  Getting 0 files is fine; we will fall back to
  // reading stdin.
  if (files.length > 1) {
    console.error(`Too many files given.  Expected 1 max, got ${files.length}:`
      + `\n${files.map(f => `• ${f}`).join('\n')}\n`)
    printUsageHint(process.stderr)
    process.exit(2)
  }

  return { files, options }
})()

// Convert options to main function's expected format.
const cleanOptions = { jobs: options['--jobs'] }
const [ file ] = files
// If a file was given, read that.  Else read stdin.
if (file) {
  fs.readFile(file, (e, text) => {
    if (e) {
      process.stderr.write(e.message)
      process.exit(2)
    }
    parseAndRunTests(text, cleanOptions)
  })
} else {
  const text = await stringifyStream(process.stdin)
  parseAndRunTests(text, cleanOptions)
}

function printUsageHint (stream = process.stdout) {
  stream.write(`${programName} [flags] [<file>]\n`)
  stream.write('  If no <file> given, reads stdin.\n')
  stream.write('Options:\n')

  const descriptions = Object.entries(possibleOptions)
    .map(([ name, {describe, defaultValue}]) => describe(name, defaultValue))

  // Fetch the attributes of each option into separate arrays, so we can pad
  // them with spaces to make them line up neatly.
  let names = descriptions.map(x => x[0])
  let explanations = descriptions.map(x => x[1])
  let defaultValues = descriptions.map(x => x[2])

  names = padTo(names, maxLengthOf(names))
  explanations = padTo(explanations, maxLengthOf(explanations))
  defaultValues = padTo(defaultValues, maxLengthOf(defaultValues))

  for (let i = 0; i < names.length; ++i) {
    const n = names[i]
    const e = explanations[i]
    const d = defaultValues[i] ? `  (default: ${defaultValues[i]})` : ''
    stream.write(`  ${n} ${e}${d}\n`)
  }

  function maxLengthOf (strings) {
    // Answers "What is the length of the longest of these strings?"
    let max = 0
    for (let s of strings) {
      if (!s || !s.length) continue
      max = Math.max(max, s.length)
    }
    return max
  }

  function padTo (strings, length) {
    // Add spaces until every string is as long as the longest.
    return strings.map(s => {
      if (!s) return s
      const nToAdd = length - s.length
      for (let _ = 0; _ < nToAdd; ++_) {
        s += ' '
      }
      return s
    })
  }
}

function stringifyStream (stream) {
  const chunks = []
  return new Promise((resolve, reject) => {
    stream
      .on('data', chunk => chunks.push(Buffer.from(chunk)))
      .on('error', e => reject(e))
      .on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
  })
}
