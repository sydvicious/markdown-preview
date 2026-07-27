# Markdown Preview by Syd Polk

Version {{VERSION}} (build {{BUILD}})\
Copyright ©2026 Syd Polk

Welcome to MarkdownPreview, an application designed to work like Apple's Preview app, but for Markdown files.
MarkdownPreview has the following features:

- Supports standard Markdown features:
  * Text styling, such as bold and italic
  * Unordered and ordered lists
  * Headers
  * Block quotes
  * Inline code
  * Fenced code blocks
  * Local and remote images
  * Tables
- Supports macOS 26.0+, iOS 26.0+, and iPadOS 26.0+
- Finding text in individual documents or across all of them
- Full support for copying to the clipboard

If you don't want to see this file again, you can remove it from the list of files:

#### Mac

Control-click it in the file list and choose "Remove from List," or select it and press ⌘⌫.

#### iOS

On iPhone the document fills the screen. Tap the chevron (‹) at the top left to go back to the file list, then swipe left on this file and tap Delete.

#### iPadOS

Swipe left on it in the file list and tap Delete.

For support, please contact [support@sydpolk.com](mailto://support@sydpolk.com).

# Markdown Preview — Feature Sample

This document exercises everything the renderer supports. Open it in the app to
see each feature rendered, or switch to Source to compare against the markup.

## Headings

Headings come in six levels, written with leading hashes.

### Third level

#### Fourth level

##### Fifth level

###### Sixth level

Setext headings are written by underlining the text instead
=============================================================

That heading's text spans two source lines. The underline may be any length.

Level two looks like this
---

## Paragraphs and line breaks

Every line ending is honored. A newline inside a paragraph renders as a line
break, so what you type is what you see — no trailing spaces or other markup
required. That keeps things that belong on their own lines together, such as a
mailing address:

MarkdownPreview
1 Markdown Way
Cupertino, CA

or a sign-off:

Thanks,
Syd
Sent from MarkdownPreview

A *blank* line does something different: it starts a new paragraph, set apart
with more vertical space than a single line break.

This is one paragraph.

This is a second, separated from the first by a blank line — notice the wider
gap above than between the address lines.

Ending a line with two trailing spaces, or with a trailing backslash,\
is still an explicit hard break. Now that every newline already breaks the line,
these are rarely needed, but they remain valid.

## Emphasis

Text can be *emphasized* with asterisks or _underscores_, made **strong** with
two of either, or ***both at once***. Emphasis can contain *nested **strong**
text* as well.

Underscores are ignored inside a word, so identifiers like snake_case_name and
`MAX_BUFFER_SIZE` survive intact. Asterisks have no such restriction, so
mid*word*emphasis does apply.

## Code

Inline `code spans` are written with backticks. A span written with double
backticks can contain a literal backtick, like `` git log --format=%h ``.

Fenced code blocks can name a language:

```swift
struct MarkdownSample {
    let title: String

    func describe() -> String {
        "Sample: \(title)"
    }
}
```

Tilde fences work too, and the content is never interpreted as markdown:

~~~
*this stays literal*  &amp;  <not a tag>
~~~

## Lists

A tight bulleted list:

- First item
- Second item
- Third item

Lists nest to any depth, and the nesting does not depend on how many spaces you
use — two spaces, four spaces, or a tab all indent one level:

- Top level
  - Second level
    - Third level
      - Fourth level
  - Back to second
- Back to top

Numbered lists work the same way:

1. First
2. Second
   1. Second, part one
   2. Second, part two
3. Third

Numbering is preserved exactly as written, which is useful when steps are
referenced by number elsewhere:

1. Step one
1. Also written as "1." but rendered as two
5. Deliberately jumps to five

A numbered list can be nested inside a bulleted one, and the reverse:

- Prerequisites
  1. Install the toolchain
  2. Clone the repository
- Build steps
  1. Open the project
  2. Press Cmd-R

Items separated by blank lines form a *loose* list, whose items are spaced
further apart:

- Loose lists put each item in its own paragraph.

- Which gives them more room to breathe.

Task lists track state, and nest like any other list:

- [x] Write the parser
- [x] Write the conformance suite
- [ ] Ship it
  - [x] Fix the nested list bug
  - [ ] Fix everything else

Ordered lists may use a parenthesis instead of a period:

1) First
2) Second

## Block quotes

> Block quotes hold real block structure rather than plain text.
>
> They can span several paragraphs.

Quotes nest:

> The outer quote says this.
>
> > And the inner quote answers.

They can also contain other blocks — headings, lists, and code:

> ### A heading inside a quote
>
> - with a list
> - of two items
>
> ```
> and a code block
> ```

## Links and images

A plain [link to the CommonMark spec](https://spec.commonmark.org/0.31.2/), and
one [with a title](https://commonmark.org "CommonMark home page") that appears
on hover. Destinations containing spaces are written in angle brackets, like
[this one](</some path/file.md>). Link text can be *formatted* too, as in
[**this bold link**](https://example.com).

Images use the same syntax as links, with a leading exclamation mark. They come
in two kinds.

**A local image** is written as a path relative to this document, and is read
from disk beside it:

```
![A photograph of Syd](lilsyd.JPG "Lil Syd")
```

![A photograph of Syd](lilsyd.JPG "Lil Syd")

**A remote image** is written as an `http` or `https` URL and is fetched over the
network, so it needs a connection. This is the very same picture, served from
this project's repository:

```
![The same photograph, fetched over https](https://raw.githubusercontent.com/sydvicious/markdown-preview/main/Samples/lilsyd.JPG "Lil Syd, remotely")
```

![The same photograph, fetched over https](https://raw.githubusercontent.com/sydvicious/markdown-preview/main/Samples/lilsyd.JPG "Lil Syd, remotely")

If the two above look identical, both paths are working. If only the first
appears, the network fetch failed; if only the second, the local file could not
be read.

Alt text is plain text even when the description contains markup, so the
emphasis in `![a *very* good dog](dog.png)` contributes its words and nothing
else.

## Tables

| Feature      | Supported | Notes                        |
| ------------ | --------- | ---------------------------- |
| Headings     | Yes       | Six levels, plus setext      |
| Lists        | Yes       | Nested, mixed, loose, tasks  |
| Block quotes | Yes       | Nested, with block content   |

Columns can be aligned left, center, or right:

| Left | Center | Right |
| :--- | :----: | ----: |
| a    |   b    |     c |
| 1    |   22   |   333 |

Cells can contain `inline code`, *emphasis*, and escaped pipes (`\|`):

| Expression | Meaning         |
| ---------- | --------------- |
| `a \| b`   | *a* or *b*      |
| `x && y`   | **both** of them |

## Thematic breaks

Three or more dashes, asterisks, or underscores make a horizontal rule. Spaces
between them are allowed.

---

***

_____

* * *

## Escapes and entities

A backslash makes a punctuation character literal, so \*this is not emphasized\*
and \[this is not a link](). To write a backslash itself, use two: \\

Named and numeric HTML entities are decoded: &amp; &lt; &gt; &copy; &mdash;
&hellip; &#8734; &#x2764;

## Not currently supported

These are recognized markdown elsewhere but render as literal text here:

- Reference-style links, written as `[text][label]` with a definition elsewhere
- Autolinks, written as `<https://example.com>` or as a bare URL
- Strikethrough, written as `~~text~~`
- Raw inline or block HTML, which is always escaped and shown as text
- Indented (four-space) code blocks — use a fenced block instead

---

*Copyright ©2026 Syd Polk. All Rights Reserved.*
