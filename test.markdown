# whatxml

XML/HTML templating with [LiveScript][1]'s [cascade][2] syntax.

[![npm package](https://img.shields.io/npm/v/whatxml.svg?style=flat-square)](https://www.npmjs.com/package/whatxml)
&emsp;
[![Build status](https://img.shields.io/travis/anko/whatxml.svg?style=flat-square)](https://travis-ci.org/anko/whatxml)
&emsp;
[![npm dependencies](https://img.shields.io/david/anko/whatxml.svg?style=flat-square)](https://david-dm.org/anko/whatxml)

<!-- !test program
sed '1s/^/require! \\whatxml;/' | lsc \-\-stdin
-->
<!-- !test before -->
<!-- !test spec 1 -->
```ls
x = whatxml \html
  .. \head
    .. \title ._ "My page"
    ..self-closing \link rel : \stylesheet type : \text/css href : \main.css
  .. \body
    .. \p ._ (.content)

console.log x.to-string { content : "Here's a paragraph." }
```

To get this:

<!-- !test result 1 -->
```html
<html><head><title>My page</title><link rel="stylesheet" type="text/css" href="main.css" /></head><body><p>Here&#x27;s a paragraph.</p></body></html>
```

You can pass a function to any setter, which decides the final value based on
what's passed in to the `to-string` call. (It's a lot like [D3][3]'s `.attr`.)

## API summary

 - `.. <string> [<attr-object>]` adds a tag (with optional attributes)
 - `..self-closing <string> [<attr-object>]` same, but a self-closing tag
 - `.. <object>` sets attributes
 - `.._ <string>` adds text
 - `..raw <string>` adds text (without escaping it)
 - `..comment <string>` adds a comment

`to-string` recursively renders that tag's tree.

## API tutorial

### Basics

Create a root tag, call it with a `string` to create child tags, with an
`object` to add attributes or call `_` to add text between the tags.

```ls
gandalf = whatxml \person      # Create a root tag.
  .. { profession : \wizard }  # Set an attribute.
  .. \name                     # Add a child node.
    .._ "Gandalf"              # Put text in it.
console.log gandalf.to-string!
```
```xml
<person profession="wizard"><name>Gandalf</name></person>
```

Handy shortcut:  When creating a tag, pass attributes as an object.

```ls
t = whatxml \tower lean : "3.99"
  .. \place city : "Pisa", country : "Italy"
console.log t.to-string!
```
```xml
<tower lean="3.99"><place city="Pisa" country="Italy"></place></tower>
```

Add self-closing tags and comments.

```ls
x = whatxml \a
  ..self-closing \b
  ..comment "what"
```
```xml
<a><b /><!--what--></a>
```

You can have stand-alone attributes without a value by setting them to `true`.
([It's invalid XML][4], but fine in HTML.)

```ls
whatxml \input { +selected }
  ..to-string! |> console.log
```
```ls
<input selected></input>
```

Strings and `true` are acceptable attribute values (also functions; see
*Templating* below). Setting attributes again overwrites the previous value.
Setting attributes to `false`, `null` or `undefined` removes that attribute, if
present.

Text is escaped automatically, but you can bypass that if you have
ready-escaped text (e.g. from a generator like [`marked`][5]).

```ls
greeting = whatxml \p
  .._ "What's up <3"
console.log greeting.to-string!

x = whatxml \p
  ..raw "<em>I know this is properly escaped already</em>"
console.log x.to-string!
```

```xml
<p>What&#39;s up &#60;3</p>
<p><em>I know this is properly escaped already</em></p>
```

You can have multiple top-level tags (useful for calling whatxml inside a
template).

```ls
x = whatxml!
  .. \a
  .. \b
console.log x.to-string!
```

```xml
<a></a><b></b>
```

### Templating

To generate content based on data, you can pass a function to any setter call.
When a tag's `to-string` is called, the functions passed to its setters before
are called with its arguments to produce the final value.

```ls
link = whatxml \a href : (.href)
  .._ (.name.to-upper-case!)

console.log link.to-string name : \google    href : "https://google.com"
console.log link.to-string name : \runescape href : "http://runescape.com"
```

```xml
<a href="https://google.com">GOOGLE</a>
<a href="http://runescape.com">RUNESCAPE</a>
```

## Limitations

If you're going to add XML comments, check that they're [valid by the XML
spec][6]: They may not contain two consecutive hyphens (`--`). For performance
reasons, `whatxml` doesn't check.

[`CDATA`-sections][7] and XML declarations (`<?xml version="1.0"?>` and such)
aren't supported, but you can happily add them using `raw`.

## Related libraries

This library aims to be a serious general-purpose templating engine for
[LiveScript][8].

Existing attempts have their flaws:

 - [`live-templ`][9] came closest to my goals, but its
   objects-in-nested-arrays base is too rigid to handle comments, raw text data
   or self-closing tags. It also provides no way to combine a template with
   input data.
 - [`create-xml-ls`][10] is object-based, so it can't represent two tags with
   the same name on the same level of nesting…
 - [`htmls`][11] supports only the base HTML tag set and treats template code as
   strings which are later parsed and transformed to actual code, then
   `eval`'d.


[1]: http://livescript.net/
[2]: http://livescript.net/#property-access-cascades
[3]: http://d3js.org/
[4]: http://stackoverflow.com/questions/6926442/is-an-xml-attribute-without-value-valid
[5]: https://github.com/chjj/marked
[6]: http://www.w3.org/TR/2006/REC-xml11-20060816/#sec-comments
[7]: http://en.wikipedia.org/wiki/CDATA
[8]: http://livescript.net/
[9]: https://www.npmjs.org/package/live-tmpl
[10]: https://www.npmjs.org/package/create-xml-ls
[11]: https://www.npmjs.org/package/htmls
