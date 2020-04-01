# tests-ex-markdown [![npm module](https://img.shields.io/npm/v/tests-ex-markdown.svg?style=flat-square)][1] [![Travis CI test status](https://img.shields.io/travis/anko/tests-ex-markdown.svg?style=flat-square)][2] [![npm dependencies](https://img.shields.io/david/anko/tests-ex-markdown.svg?style=flat-square)][3]

Test that your [Markdown][markdown] code examples actually work!

 1. Annotate your usage examples with `!test` commands in HTML comments.

    <!-- !test program ./index.ls -->

    <!-- !test in example -->

    ```md
    <!-- !test program node -->

    Here's how to print to the console in [Node.js][1]:

    <!-- !test in simple example -->

        console.log("hi");

    It will print this:

    <!-- !test out simple example -->

        hi

    [1]: https://nodejs.org/
    ```

 2. `npm install tests-ex-markdown`.

 3. Run it on your Markdown file:

    ```
    txm your-file.markdown
    ```

 4. Get output (in [TAP format][tap-spec]).

    <!-- !test out example -->

    ```
    TAP version 13
    1..1
    ok 1 simple example

    # 1/1 passed
    # OK
    ```

The above example is itself tested with this module, so I have confidence that
it is correct! :boom:

## API

### The `txm` command line tool

    txm [--series] [filename]

Tests may run in parallel by default.  If your tests need to be run
sequentially, pass `--series`.

If a `filename` is provided, `txm` parses it as Markdown and executes the tests
specified in it.  Otherwise, it reads from `stdin`.

### Annotations

#### `!test in` and `!test out`

The next code block after a `!test in <name>` or `!test out <name>` command is
read as a test input.  The `<name>` parts are used to match them.  The `<name>`
can be any text.

The input and output code blocks can be anywhere in the file, as long as they
can be matched by name.  `txm` will fail loudly if it cannot match one.

#### `!test program`

In `!test program <program>`, the `<program>` part will be run as a shell
command for any following matching input and outputs.

The `<program>` can contain arbitrary characters, including spaces and
newlines, so feel free.

If you only mean to use one test program, you only have to declare it once,
before your first test.  If you need to use a different program for some set of
tests, just declare that before the next test.  When an `in` and `out` block
are matched, the last encountered `program` command is used.

#### Hyphen quirk

2 consecutive hyphens (`--`) inside HTML comments are [not allowed by the HTML
spec][html-comments-spec].  Thankfully, `txm` lets you escape them: `\-` means
the same as a hyphen.  To write a backslash, write `\\`.

## Similar libraries

This module assumes you want to run each test as a [command-line][shell] program.
If you'd prefer something more JavaScript-focused, you might like @pjeby's
[mockdown][mockdown], or @sidorares' [mocha.md][mochamd].

## License

[ISC](LICENSE)

[1]: https://www.npmjs.com/package/tests-ex-markdown
[2]: https://travis-ci.org/anko/tests-ex-markdown
[3]: https://david-dm.org/anko/tests-ex-markdown
[markdown]: http://daringfireball.net/projects/markdown/syntax
[tap-spec]: https://testanything.org/tap-version-13-specification.html
[html-comments-spec]: http://www.w3.org/TR/REC-xml/#sec-comments
[shell]: https://en.wikipedia.org/wiki/Shell_(computing)
[mockdown]: https://github.com/pjeby/mockdown
[mochamd]: https://github.com/sidorares/mocha.md
