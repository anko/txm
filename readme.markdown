# tests-ex-markdown ![](https://img.shields.io/badge/api_status-experimental-red.svg?style=flat-square)

Run [markdown][1] code snippets as unit tests.

## Use

Annotate your markdown with `!test` commands inside HTML comments (escape
double-dashes in the `program` command):

<!-- !test program
# Write to temporary file, ignore TAP's last newlines
F=$(mktemp); cat > "$F";
./index.ls $F | head -c -2;
rm -f "$F"
-->

<!-- !test input simple -->

```md
<!-- !test program node -->

Look ma, no hands!

<!-- !test input 1 -->

    process.stdout.write("foot!");

<!-- !test output 1 -->

    foot!
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

As you might have guessed, the above example is itself a unit test, for this
module.

## How it works

The Markdown file is parsed sequentially. Only code blocks and HTML comments
starting "!test" are read. When a `spec` command is read, the next code block
will be read as a test input. When a `result` command is read, it will become a
test result. Each `spec`/`result` has a name (`1` in the above example) that
associates them as pairs, so they can be in any order.

Whichever `program` command was last read when a `spec` and `result` with the
same name are matched together becomes the test runner for that test.

For each `program`+`spec`+`result` tuple, the program is started, the spec is
passed to its [standard input][4] and its standard output is checked for
equality to the result.

When rendered to HTML (e.g. on Github), the comments don't show up.  Works with
[GFM][5] fenced blocks too.

## Why

I constantly write usage examples in markdown files, in various languages.  I
wanted a way to automatically verify that they're still correct.

I didn't want to introduce a build step for readme files, because that could
cause a [chicken-and-egg dilemma][6], as you might need the readme file to know
how to build the readme file.  So comment annotations seemed fine.

* * *

The name is dumb wordplay on "[*deus ex machina*][7]".

[1]: http://daringfireball.net/projects/markdown/syntax
[2]: https://testanything.org/tap-version-13-specification.html
[3]: https://www.npmjs.com/package/tape
[4]: http://en.wikipedia.org/wiki/Standard_streams
[5]: https://help.github.com/articles/github-flavored-markdown/
[6]: http://en.wikipedia.org/wiki/Chicken_or_the_egg
[7]: http://en.wikipedia.org/wiki/Deus_ex_machina
