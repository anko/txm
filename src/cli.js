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
  .check((args) => {
    if ('jobs' in args) {
      const valueOk = Number.isInteger(args.jobs) && args.jobs >= 1
      if (!valueOk) throw Error(
        `Invalid --jobs value '${args.jobs}' (expected integer >= 1)`)
    }
    return true
  })
  .help()
  .parse(process.argv.slice(2))

const files = argv._
// No files given, read from stdin
if (files.length === 0) {
  process.stdin
    .on('error', (e) => { throw e })
    .pipe(concat((text) => parseAndRunTests(text, argv)))
} else {
  // If files, run for each of them
  files.forEach((file) => {
    fs.readFile(file, (e, text) => {
      if (e) throw e
      parseAndRunTests(text, argv)
    })
  })
}

