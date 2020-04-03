# tests-ex-markdown [![npm module](https://img.shields.io/npm/v/tests-ex-markdown.svg?style=flat-square)][1] [![Travis CI test status](https://img.shields.io/travis/anko/tests-ex-markdown.svg?style=flat-square)][2] [![npm dependencies](https://img.shields.io/david/anko/tests-ex-markdown.svg?style=flat-square)][3]

tool for testing your [Markdown][markdown] code examples

 - **language-agnostic** (you can run your example code with any program)
 - **clear diagnostics** (diffs, line numbers, stdout, stderr, exit code, …)
 - **non-intrusive** (reads annotations from HTML comments; the document
   renders identically!)
 - **[TAP][tap-spec] output** (neat output, compatible with [an ecosystem of
   tools](https://github.com/sindresorhus/awesome-tap)

# examples

<!-- !test program ./index.ls -->

<!-- !test in example -->

```markdown
# My beautiful readme

<!-- !test program node -->

Here's how to print to the console in [Node.js][1]:

<!-- !test in simple example -->

    console.log("hi");

It will print this:

<!-- !test out simple example -->

    hi

[1]: https://nodejs.org/
```

```bash
$ tests-ex-markdown README.md
```

<!-- !test out example -->

> ```tap
> TAP version 13
> 1..1
> ok 1 simple example
>
> # 1/1 passed
> # OK
> ```

<details><summary>Example: Testing C code with GCC</summary>

<!-- !test in C example -->

You can use whatever you want as the `!test program`:

```markdown
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


<details><summary>Example: Replacing <code>require('module-name')</code> with <code>require('./index.js')</code></summary>

Your users are using your library by calling require with its package name
(e.g. `require('module-name')`.  However, it makes sense to actually run tests
on the local implementation at `require('./index.js')`, or whatever is listed
as the `main` file in `oackage.json`.

So let's just replace those `require` calls before passing it to `node`!

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

<details><summary>Example: Testing stderr output</summary>

Prepending `2>&1` to a shell command [redirects][shell-redirection-q] `stderr`
to `stdout`.

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

<details><summary>Example: Testing a program with non-zero exit status</summary>

Put `|| true` after the program, and the shell will swallow the exit code.  If
you don't, `txm` assumes all programs that exit non-zero must have
unintentionally failed.

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

Example: [This
readme!](https://raw.githubusercontent.com/anko/tests-ex-markdown/master/readme.markdown)

# usage

## `txm [--series] [filename]`

 - `--series`: Run tests serially (default: in parallel)
 - `filename`: Input file (default: read `stdin`)

`txm` exits `0` *if and only if* all tests pass.

Annotations (inside HTML comments):

 - ### `!test in <name>` / `!test out <name>`

   The next code block after is read as an input or output.

   Inputs and outputs can be anywhere.  They are matched by `<name>`.  Errors
   are shown for mismatches.

 - ### `!test program <program>`

   The `<program>` is run as a shell command for each following matching
   input/output pair.  It gets the input on `stdin`, and is expected to produce
   the output on `stdout`.

   If you want to use the same program for all tests, just declare it once.

Note that 2 consecutive hyphens (`--`) inside HTML comments are [not allowed by
the HTML spec][html-comments-spec], so `txm` lets you escape them: `\-` means
the same as a hyphen.  To write a backslash, write `\\`.

# screenshot

![example failure
output](https://user-images.githubusercontent.com/5231746/78293904-a7f23a00-7529-11ea-9632-799402a0219b.png)

# License

[ISC](LICENSE)

[1]: https://www.npmjs.com/package/tests-ex-markdown
[2]: https://travis-ci.org/anko/tests-ex-markdown
[3]: https://david-dm.org/anko/tests-ex-markdown
[markdown]: http://daringfireball.net/projects/markdown/syntax
[tap-spec]: https://testanything.org/tap-version-13-specification.html
[html-comments-spec]: http://www.w3.org/TR/REC-xml/#sec-comments
[shell-redirection-q]: https://superuser.com/questions/1179844/what-does-dev-null-21-true-mean-in-linux
