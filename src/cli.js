#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const yargs = require('yargs');
const concat = require('concat-stream');

const parseAndRunTests = require('./main.js')

// Parse arguments
const argv = yargs
  .option('jobs', {
    'desc': 'How many tests may run in parallel',
    'default': os.cpus().length,
    'defaultDescription': '# of CPU cores',
    'nargs': 1
  })
  .option('backend', {
    'desc': 'Program to run in the background during testing',
    'nargs': 1
  })
  .check((args) => {
    if (args._.length > 1)
      throw Error(`Too many files.  Expected 1 max, got ${args._.length}`)
    if ('jobs' in args) {
      const valueOk = Number.isInteger(args.jobs) && args.jobs >= 1
      if (!valueOk) throw Error(
        `Invalid --jobs value '${args.jobs}' (expected integer >= 1)`)
    }
    return true
  })
  .help()
  .parse(process.argv.slice(2))

const file = argv._[0]
// If a file was given, read that.  Else read stdin.
if (file) {
  fs.readFile(file, (e, text) => {
    if (e) throw e
    parseAndRunTests(text, argv)
  })
} else {
  process.stdin
    .on('error', (e) => { throw e })
    .pipe(concat((text) => parseAndRunTests(text, argv)))
}

