# tests-ex-markdown

[![npm module](https://img.shields.io/npm/v/tests-ex-markdown.svg?style=flat-square)][1]
[![Travis CI test status](https://img.shields.io/travis/anko/tests-ex-markdown.svg?style=flat-square)][2]
[![npm dependencies](https://img.shields.io/david/anko/tests-ex-markdown.svg?style=flat-square)][3]

Run your [markdown][4] code examples as unit tests.

## Use

Write code usage examples in markdown as you usually would, but annotate them
with `!test` commands within HTML comments.  Define what **program** tests
should run with, what to pass as **input** and what **output** to expect:

<!-- !test program
# Write to temporary file, ignore TAP's last newlines
F=$(mktemp); cat > "$F";
./index.ls $F | head -c -2;
rm -f "$F"
-->

<!-- !test in simple -->

```md
<!-- !test program node -->

Here's how to print without a trailing [newline][1] in [Node.js][2]:

<!-- !test in simple example -->

    process.stdout.write("hi");

It will print this:

<!-- !test out simple example -->

    hi

[1]: http://en.wikipedia.org/wiki/Newline
[2]: https://nodejs.org/
```

Run:

    txm whatever.markdown

(Or write the Markdown to `stdin`.)

Receive [Test Anything Protocol version 13][5] output.

<!-- !test out simple -->

    TAP version 13
    # simple example
    ok 1 should be equal

    1..1
    # tests 1
    # pass  1

    # ok

The comments are omitted when the Markdown is rendered (like on Github).  This
file is itself a unit test for this module. :)

## How it works

### Input/output commands

The Markdown file is parsed sequentially.  Only code blocks and HTML comments
starting "!test" are read. When an `in` command is read, the next code block
will be read as a test input.  When an `out` command is read, it will be read
as expected output.

Each `in`/`out` command has an associated identifier that associates them as
pairs.  These can be any string.  These exist to let you put matching inputs
and outputs in any order you like anywhere in the file.

### The program command

The `program` command defines the program the input is passed to, which is then
expected to produce the given output.  (That's [standard input and output][6].)

Whenever a pair of input/output commands get matched, the last encountered
program command is used.  (So you can just have the program command once if
your tests all run on the same program.)

Some tips for writing these correctly:

#### Escape double hyphens (`--`)

They're [illegal in HTML comments][7], so txm provides a way to escape them:
`\-` means the same as a hyphen.  For a literal backslash, write `\\`.

#### Modify input with shell commands

The program is run as a shell command, so it can contain arbitrary
[redirection][8].  You can use this to prepend obvious things to the input to
reduce redundancy in your example code (e.g. using `sed` to drop in a line of
`var m = require("mymodule");`) or to trim off a trailing newline from the
output (using `head -c -1`) to match the expected output, or even [burrito][9]
it for crazy code instrumentation.

## Why

Usage examples should remain up-to-date with the rest of the code.  I wanted an
automatic solution that would allow code examples written in any language to be
tested this way.

Comment annotations were chosen because they're easy to plug into an existing
file.  I didn't want to introduce a build step for readme files, because that
could cause a [chicken-and-egg dilemma][10]—you might need the readme file to
learn how to build the readme file!

* * *

The name is dumb wordplay on "[*deus ex machina*][11]".

[1]: https://www.npmjs.com/package/tests-ex-markdown
[2]: https://travis-ci.org/anko/tests-ex-markdown
[3]: https://david-dm.org/anko/tests-ex-markdown
[4]: http://daringfireball.net/projects/markdown/syntax
[5]: https://testanything.org/tap-version-13-specification.html
[6]: http://en.wikipedia.org/wiki/Standard_streams
[7]: http://www.w3.org/TR/REC-xml/#sec-comments
[8]: http://en.wikipedia.org/wiki/Redirection_(computing)
[9]: https://github.com/substack/node-burrito
[10]: http://en.wikipedia.org/wiki/Chicken_or_the_egg
[11]: http://en.wikipedia.org/wiki/Deus_ex_machina
