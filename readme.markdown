# tests-ex-markdown [![npm module](https://img.shields.io/npm/v/tests-ex-markdown.svg?style=flat-square)][1] [![Travis CI test status](https://img.shields.io/travis/anko/tests-ex-markdown.svg?style=flat-square)][2] [![npm dependencies](https://img.shields.io/david/anko/tests-ex-markdown.svg?style=flat-square)][3]

A tool for testing that your [Markdown][markdown] code examples actually work!

 - **language-agnostic**: you choose how your example code is run, so this
   works with any tool or programming language
 - **clear diagnostics** (diffs, line numbers, stdout, stderr, exit code, …)
 - **non-intrustive** uses HTML comments for annotations, so your rendered
   document is unaffected
 - **TAP output**: compatible with [other
   tools](https://github.com/sindresorhus/awesome-tap) that consume
   [TAP][tap-spec]

![example failure
output](https://user-images.githubusercontent.com/5231746/78293904-a7f23a00-7529-11ea-9632-799402a0219b.png)

<!-- !test program ./index.ls -->

## Quickstart

 1. Annotate your usage examples with `!test` commands in HTML comments.

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

    Or if you develop for a different language, replace `node` with whatever
    you want, in the `!test program` annotation.

 2. Install and run tests-ex-markdown:

    - If you **are** a JavaScript developer—

      1. `npm install tests-ex-markdown` in the root of the project which files
         you want to test.
      2. Add `txm your-file.markdown` to your `package.json` `test` script.
      3. `npm test` as usual.

    - If you **are not** a JavaScript developer—

      1. [Install Node.js](https://nodejs.org/en/) if you don't have it yet.
         (You can check if you have it by trying to run its command `node`.)
      2. Install the `txm` command-line tool with `npm install -g
         tests-ex-markdown`.  (To uninstall, `npm uninstall -g
         tests-ex-markdown`.)
      3. Run `txm your-file.markdown` on the command line whenever you want to
         test a file.

 4. Get output in [TAP format][tap-spec]:

    <!-- !test out example -->

    ```
    TAP version 13
    1..1
    ok 1 simple example

    # 1/1 passed
    # OK
    ```

### Examples of various use-cases

<details><summary>Example: Testing C code with GCC</summary>

<!-- !test in C example -->

```md
<!-- !test program
cat > /tmp/program.c
gcc /tmp/program.c -o /tmp/test-program && /tmp/test-program -->

<!-- !test in printf -->

    #include <stdio.h>
    int main () {
        printf("%d\n", 42);
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

</details>


<details><summary>Example: Replacing module name with local require</summary>

Motivation:  The way users will be using your library is to call require with
the name that your package is published with as a package.  However, we would
like to actually test with the local implementation.

So let's just replace those `require` calls before passing it to `node`!

<!-- !test in require replacing example  -->

```md
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
| sed -e "s/require('$PACKAGE_NAME')/require('.\\/$LOCAL_MAIN_FILE')/" \
| node
-->

<!-- !test in use library -->

    // In our case, requiring the main file just runs the program
    require('tests-ex-markdown')

<!-- !test out use library -->

    TAP version 13
    1..0
    # no tests
    # For help, see https://github.com/anko/tests-ex-markdown
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

## API

### The `txm` command line tool

    txm [--series] [filename]

Tests run in parallel.  Their outputs are printed in order though.  If you need
tests to run in series though, pass `--series`.

If a `filename` is given, `txm` reads that file.  Otherwise, it reads `stdin`.

The `txm` process will `exit` with a `0` status if and only if all tests pass.

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
   to `stdout`.

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

   <!-- !test in don't fail on non-zero -->

   ```md
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

 - **How are the code examples in this readme tested?**

   Have a guess.  [It's very
   meta](https://raw.githubusercontent.com/anko/tests-ex-markdown/master/readme.markdown).
   :sunglasses:

## License

[ISC](LICENSE)

[1]: https://www.npmjs.com/package/tests-ex-markdown
[2]: https://travis-ci.org/anko/tests-ex-markdown
[3]: https://david-dm.org/anko/tests-ex-markdown
[markdown]: http://daringfireball.net/projects/markdown/syntax
[tap-spec]: https://testanything.org/tap-version-13-specification.html
[html-comments-spec]: http://www.w3.org/TR/REC-xml/#sec-comments
[shell-redirection-q]: https://superuser.com/questions/1179844/what-does-dev-null-21-true-mean-in-linux
