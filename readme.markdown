# testxmd ![](https://img.shields.io/badge/api_stability-experimental-red.svg?style=flat-square)

*Tests ex markdown*!  Use usage examples from a markdown file as unit tests.

Annotate your input markdown file with commands in HTML comments like so
(escape double-dashes in the `program` command):

```md
<!-- !test program   node \-\-stdin -->

Look ma, no hands!

<!-- !test spec 1 -->

    console.log("foot!");

<!-- !test result 1 -->

    foot!
```

`testxmd file.markdown` then passes each `spec` to the [`stdin`][1] of an
instance of the last specified `program`, and checks if the `stdout` matches
the corresponding `result`.

The output is in [Test Anything Protocol version 13][2], just like [tape][3].

[1]: http://en.wikipedia.org/wiki/Standard_streams
[2]: https://testanything.org/tap-version-13-specification.html
[3]: https://www.npmjs.com/package/tape
