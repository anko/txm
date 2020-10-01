# txm [![](https://img.shields.io/npm/v/txm.svg?style=flat-square)][1] [![](https://img.shields.io/travis/anko/txm/master.svg?style=flat-square)][2] [![](https://img.shields.io/coveralls/github/anko/txm?style=flat-square)][coveralls] [![](https://img.shields.io/david/anko/txm.svg?style=flat-square)][3]

### Purpose

Command-line program that verifies the correctness of code examples in a given
[Markdown][markdown] file.  It parses the file for code blocks preceded by
[HTML comments containing `!test` annotations](#use), and checks that given
inputs to the given program result in given outputs.

### Features

 - Language-agnostic.  Runs tests with any shell command.
 - [TAP][tap-spec] format output.
 - Process-level parallelism.
 - [Clear diagnostics](#screenshot) when tests fail.
 - Users retain full choice of formatting.

### Non-features

 - No compilation step.
 - No language-specific features.
 - No annotations visible in the rendered document.

# example

<!-- !test program node src/cli.js -->

<!-- !test in example -->

`README.md`:

```markdown
# console.log

The [console.log][1] function in [Node.js][2] stringifies the given arguments
and writes them to `stdout`, followed by a newline.  For example:

<!-- !test program node -->

<!-- !test in simple example -->

    console.log('a')
    console.log(42)
    console.log([1, 2, 3])

The output is:

<!-- !test out simple example -->

    a
    42
    [ 1, 2, 3 ]

[1]: https://nodejs.org/api/console.html#console_console_log_data_args
[2]: https://nodejs.org/
```

Run:

```bash
$ txm README.md
```

Output:

<!-- !test out example -->

> ```tap
> TAP version 13
> 1..1
> ok 1 simple example
>
> # 1/1 passed
> # OK
> ```

- - -

Examples of other use-cases:

<details><summary>Testing C code with <code>gcc</code></summary>

<!-- !test in C example -->

Any sequence of shell commands is a valid `!test program`, so you can e.g. cat
the test input into a file, then compile and run it:

```markdown
<!-- !test program
cat > /tmp/program.c
gcc /tmp/program.c -o /tmp/test-program && /tmp/test-program -->

Here is a simple example C program that computes the answer to life, the
universe, and everything:

<!-- !test in printf -->

    #include <stdio.h>
    int main () {
        printf("%d\n", 6 * 7);
    }

<!-- !test out printf -->

    42
```

<!-- !test out C example -->

> ```
> TAP version 13
> 1..1
> ok 1 printf
>
> # 1/1 passed
> # OK
> ```

In practice you might want to invoke `mktemp` in the `!test program` to avoid
multiple parallel tests overwrting each other's files.  Or pass `--jobs 1` to
run tests serially.

</details>


<details><summary>Replacing package imports with local file imports<br>(For example, <code>require('module-name')</code> → <code>require('./index.js')</code>)</summary>

In languages with package managers, users will likely be using your library by
importing it using its package name (e.g. `require('module-name')`.  However,
it makes sense to actually run your tests such that they use your local
implementation (e.g. `./index.js`, or whatever is listed as the `main` file in
`package.json`).

So here's a markdown file with a test program specified that loads the name of
the main file out of `./package.json`, and replaces the first `require(...)`
call with that:

<!-- !test in require replacing example  -->

```markdown
<!-- !test program
# First read stdin into a temporary file
TEMP_FILE="$(mktemp --suffix=js)"
cat > "$TEMP_FILE"

# Read the package name and main file from package.json
PACKAGE_NAME=$(node -e "console.log(require('./package.json').name)")
LOCAL_MAIN_FILE=$(node -e "console.log(require('./package.json').main)")

# Run a version of the input code where requires for the package name are
# replaced with the local file path
cat "$TEMP_FILE" \
| sed -e "s#require('$PACKAGE_NAME')#require('./$LOCAL_MAIN_FILE')#" \
| node
-->

Did you know you can also use `txm` as a module to use it programmatically?

<!-- !test in use library -->

    const parseAndRunTests = require('txm')
    parseAndRunTests(`
    # Markdown heading!

    <!-- !test program node -->
    <!-- !test check print -->

        require('assert')(true)
    `)

It produces output onto console:

<!-- !test out use library -->

    TAP version 13
    1..1
    ok 1 print

    # 1/1 passed
    # OK
```

<!-- !test out require replacing example -->

> ```
> TAP version 13
> 1..1
> ok 1 use library
>
> # 1/1 passed
> # OK
> ```

</details>

<details><summary>Redirecting <code>stderr</code>→<code>stdout</code>, to test both in the same
block</summary>

Prepending `2>&1` to a shell command [redirects][shell-redirection-q] `stderr`
to `stdout`.  This can be handy if you don't want to write separate `!test out`
and `!test err` blocks.

<!-- !test in redirect stderr -->

```markdown
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

<details><summary>Testing a program that exits non-zero</summary>

`txm` assumes that if the test program exits non-zero, it must have been
unintentional.  You can put `|| true` after the program command to make the
shell swallow the exit code and pretend to `txm` that it was `0` and everything
is fine.

<!-- !test in don't fail on non-zero -->

```markdown
<!-- !test program node || true -->

<!-- !test in don't fail -->

    console.log("Hi before throw!")
    throw new Error("AAAAAA!")

<!-- !test out don't fail -->

    Hi before throw!
```

<!-- !test out don't fail on non-zero -->

> ```
> TAP version 13
> 1..1
> ok 1 don't fail
>
> # 1/1 passed
> # OK
> ```
</details>

<details><summary>Testing examples that call <code>assert</code></summary>

If your example code calls `assert` or such (which throw an error and exit
nonzero when the assert fails), then you don't really need an output block,
because the example already documents its assumptions.

In such cases you can use use a `!test check` annotation.  This simply runs the
code, and checks that the program exits with status `0`, ignoring its output.

<!-- !test in asserting test -->

```markdown
<!-- !test program node -->

<!-- !test check laws of mathematics -->

    const assert = require('assert')
    assert(1 + 1 == 2)

```

<!-- !test out asserting test -->

> ```
> TAP version 13
> 1..1
> ok 1 laws of mathematics
>
> # 1/1 passed
> # OK
> ```
</details>

▹ [This
readme](https://raw.githubusercontent.com/anko/txm/master/readme.markdown)

# install

Requires [Node.js][nodejs].  Install with `npm install -g txm`.

# use

## `txm [--jobs <n>] [filename]`

 - `filename`: Input file (default: read from `stdin`)
 - `--jobs`: How many tests may run in parallel.(default: `os.cpus().length`)

   Results will always be shown in insertion order in the output, regardless of
   the order parallel tests complete.

 - `--version`
 - `--help`

`txm` exits `0` *if and only if* all tests pass.

Coloured output is on if outputting to a terminal, and off otherwise.  If you
want no colors ever, set the env variable `NO_COLOR=1`.  If you want to output
colour codes even when not in a TTY, set `FORCE_COLOR=1`.

Annotations (inside HTML comments):

 - #### `!test program <program>`

   The `<program>` is run as a shell command for each following matching
   input/output pair.  It gets the input on `stdin`, and is expected to produce
   the output on `stdout`.

   To use the same program for each test, just declare it once.

   The program sees these environment variables:

    - `TXM_INDEX` (1-based number of test)
    - `TXM_NAME` (name of test)
    - `TXM_INDEX_FIRST`, `TXM_INDEX_LAST` (indexes of first and last tests)
    - `TXM_INPUT_LANG` (the language tag of the input/check markdown code
      block, if applicable)

 - #### `!test in <name>` / `!test out <name>` / `!test err <name>`

   The next code block is read as given input, or expected stdout or stderr.

   These are matched by `<name>`, and may be anywhere.

 - #### `!test check <name>`

   The next code block is read as a check test.  The previously-specified
   program gets this as input, but its output is ignored.  The test passes if
   the program exits `0`.

   Use this for code examples that check their own correctness, (e.g.  by
   calling `assert`), or if your test program is a linter.

Note that 2 consecutive hyphens (`--`) inside HTML comments are [disallowed by
the HTML spec][html-comments-spec].  For this reason, `txm` lets you escape
hyphens: `#-` is automatically replaced by `-`.  If you need to write literally
`#-`, write `##-` instead, and so on.  `#` acts normally everywhere else.

# screenshot

![example failure
output](https://user-images.githubusercontent.com/5231746/78293904-a7f23a00-7529-11ea-9632-799402a0219b.png)

# license

[ISC](LICENSE)

[1]: https://www.npmjs.com/package/txm
[2]: https://travis-ci.org/anko/txm
[3]: https://david-dm.org/anko/txm
[coveralls]: https://coveralls.io/github/anko/txm
[nodejs]: https://nodejs.org/
[markdown]: http://daringfireball.net/projects/markdown/syntax
[tap-spec]: https://testanything.org/tap-version-13-specification.html
[html-comments-spec]: https://www.w3.org/TR/2011/WD-html5-20110525/syntax.html#comments
[shell-redirection-q]: https://superuser.com/questions/1179844/what-does-dev-null-21-true-mean-in-linux

