# tests-ex-markdown [![npm module](https://img.shields.io/npm/v/tests-ex-markdown.svg?style=flat-square)][1] [![Travis CI test status](https://img.shields.io/travis/anko/tests-ex-markdown.svg?style=flat-square)][2] [![npm dependencies](https://img.shields.io/david/anko/tests-ex-markdown.svg?style=flat-square)][3]

A tool to easily test that your [Markdown][markdown] code examples actually
work!

It shows you useful information to understand test failures, including—

 - coloured output (when outputting to a terminal),
 - colour-coded diffs,
 - line numbers of where errors occurred,
 - data about how your test program failed (exit code, stdout, stderr)

Works well on its own, but is also compatible with [tools that consume
TAP](https://github.com/sindresorhus/awesome-tap).


![example failure
output](https://user-images.githubusercontent.com/5231746/78293904-a7f23a00-7529-11ea-9632-799402a0219b.png)

## Quickstart

 1. Annotate your usage examples with `!test` commands in HTML comments.

    <!-- !test program ./index.ls -->

    <!-- !test in example -->

    ```markdown
    <!-- !test program node -->

    Here's how to print to the console in [Node.js][1]:

    <!-- !test in simple example -->

        console.log("hi");

    It will print this:

    <!-- !test out simple example -->

        hi

    [1]: https://nodejs.org/
    ```

 2. Install tests-ex-markdown:

    ```bash
    npm install tests-ex-markdown
    ```

 3. Call it it in your `package.json` `test` script:

    ```bash
    txm your-file.markdown
    ```

 4. Get output in [TAP format][tap-spec]:

    <!-- !test out example -->

    ```
    TAP version 13
    1..1
    ok 1 simple example

    # 1/1 passed
    # OK
    ```

The examples in this readme are tested the same way; [see the Markdown
source](https://raw.githubusercontent.com/anko/tests-ex-markdown/master/readme.markdown)!
:ok\_hand::sparkles:

## API

### The `txm` command line tool

    txm [--series] [filename]

Tests run in parallel.  If you want sequential, pass `--series`.

If a `filename` is provided, `txm` parses it as Markdown and runs the tests
specified in it.  Otherwise, `txm` reads `stdin`.

The `txm` process will `exit` with a `0` status if all tests pass, and non-zero
in all other cases.  It outputs valid TAP even if your specified test program
fails, or if your format is wrong.

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

## FAQ

 - **How do I test `stderr` output?**

   Prepend `2>&1` to your command, to [redirect][shell-redirection-q] `stderr`
   to `stdout`.  (This is a shell feature, not a `txm` feature.)

   <details><summary>Example</summary>

   <!-- !test in redirect stderr -->

   ```md
   <!-- !test program 2>&1 node -->

   <!-- !test in print to both stdout and stderr -->

       console.error("This goes to stderr!")
       console.log("This goes to stdout!")

   <!-- !test out print to both stdout and stderr -->

       This goes to stderr!
       This goes to stdout!
   ```

   <!-- !test out redirect stderr -->

   > ```
   > TAP version 13
   > 1..1
   > ok 1 print to both stdout and stderr
   >
   > # 1/1 passed
   > # OK
   > ```
   </details>

 - **How do I test a program that exits with a non-zero status?** (which `txm`
   considers to have failed)

   Put `|| true` after it to swallow the exit code.

   <details><summary>Example</summary>

   <!-- !test in redirect stderr -->

   ```md
   <!-- !test program node || true -->

   <!-- !test in don't fail -->

       console.log("Hi before throw!")
       throw new Error("AAAAAA!")

   <!-- !test out don't fail -->

       Hi before throw!
   ```

   <!-- !test out redirect stderr -->

   > ```
   > TAP version 13
   > 1..1
   > ok 1 don't fail
   >
   > # 1/1 passed
   > # OK
   > ```
   </details>

## License

[ISC](LICENSE)

[1]: https://www.npmjs.com/package/tests-ex-markdown
[2]: https://travis-ci.org/anko/tests-ex-markdown
[3]: https://david-dm.org/anko/tests-ex-markdown
[markdown]: http://daringfireball.net/projects/markdown/syntax
[tap-spec]: https://testanything.org/tap-version-13-specification.html
[html-comments-spec]: http://www.w3.org/TR/REC-xml/#sec-comments
[shell-redirection-q]: https://superuser.com/questions/1179844/what-does-dev-null-21-true-mean-in-linux
