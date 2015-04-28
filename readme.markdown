# tests-ex-markdown ![](https://img.shields.io/badge/api_status-getting_there-yellow.svg)

Run [markdown][1] code snippets as unit tests.

## Use

Annotate your markdown with `!test` commands within HTML comments:

<!-- !test program
# Write to temporary file, ignore TAP's last newlines
F=$(mktemp); cat > "$F";
./index.ls $F | head -c -2;
rm -f "$F"
-->

<!-- !test input simple -->

```md
<!-- !test program node -->

I'm now doing to demonstrate how to print things in
[Node.js](https://nodejs.org/):

<!-- !test input 1 -->

    process.stdout.write("hi");

You can expect that to produce this:

<!-- !test output 1 -->

    hi
```

Run:

    txm whatever.markdown

Receive [Test Anything Protocol version 13][2] output (through [tape][3]):

<!-- !test output simple -->

    TAP version 13
    # testxmd test
    ok 1 should be equal

    1..1
    # tests 1
    # pass  1

    # ok

The HTML comments remain invisible, but your code examples are now testable.

As you might guess, the above example is itself a unit test for this module.

## How it works

### Input/output commands

The Markdown file is parsed sequentially. Only code blocks and HTML comments
starting "!test" are read. When an `input` command is read, the next code block
will be read as a test input. When an `output` command is read, it will be read
as expected output.

Each `input`/`output` command has an associated identifier that associates them
as pairs.  These can be any string.  These exist to let you put matching inputs
and outputs in any order wherever you like.

### The program command

The `program` command defines the program the input is passed to, which is then
expected to produce the given output.  (That's [standard input and output][4].)

Whenever a pair of input/output commands get matched, the last encountered
program command is used.  (So you can just have the program command once if
your tests all run on the same program.)

Some tips for writing these correctly:

#### Escape double hyphens (`--`)

They're [illegal in HTML comments][5], so txm provides a way to escape them:
`\-` means the same as a hyphen.  For a literal backslash, do `\\`.

#### Modify input with shell commands

The program is run as a shell command, so it can contain arbitrary
[redirection][6].  You can use this to prepend obvious things to the input to
reduce redundancy in your example code (e.g. `var m = require("mymodule");"`)
or to trim off a trailing newline from the output (using `head -c -1`).

## Why

I constantly write usage examples in markdown files, in various languages.  I
wanted a way to automatically verify that they're still correct.

I didn't want to introduce a build step for readme files, because that could
cause a [chicken-and-egg dilemma][7], as you might need the readme file to know
how to build the readme file.  So comment annotations seemed fine.

* * *

The name is dumb wordplay on "[*deus ex machina*][8]".

[1]: http://daringfireball.net/projects/markdown/syntax
[2]: https://testanything.org/tap-version-13-specification.html
[3]: https://www.npmjs.com/package/tape
[4]: http://en.wikipedia.org/wiki/Standard_streams
[5]: http://www.w3.org/TR/REC-xml/#sec-comments
[6]: http://en.wikipedia.org/wiki/Redirection_(computing)
[7]: http://en.wikipedia.org/wiki/Chicken_or_the_egg
[8]: http://en.wikipedia.org/wiki/Deus_ex_machina
