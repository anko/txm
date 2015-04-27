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

Run `testxmd file.markdown` to check the results when run with the specified
program match.
