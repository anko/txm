# whatxml

XML/HTML templating with [LiveScript][1]'s [cascade][2] syntax.

<!-- !test program
sed '1s/^/require! \\whatxml;/' \
| lsc -\-stdin \
| head -c -1
-->
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
