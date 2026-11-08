"""Writes the Contents section of a markdown document from its ## and ###
headings, with links the IDE's documentation viewer (RhoMarkdownViewer) and
GitHub both resolve.

    python tools/gen_contents.py doc/Axon-Language-Reference.md

The section is "## Contents" followed by a nested list; it goes before the
first other ## heading, and is replaced when the script runs again. Anchors
follow RhoHeadingSlug: the heading's rendered text in lower case, keeping
letters, digits, hyphens and underscores, with spaces turned into hyphens;
a repeated slug gets -1, -2 and so on, counted over every heading.
"""

import re
import sys

CONTENTS = '## Contents'


def plain(text):
    """The heading as rendered: code spans, emphasis and links reduced to text."""
    text = re.sub(r'`([^`]*)`', r'\1', text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'(\*\*|__|\*|_)(\S(?:.*?\S)?)\1', r'\2', text)
    return text.strip()


def slug(text):
    out = []
    for ch in text:
        if ch.isalnum():
            out.append(ch.lower())
        elif ch == ' ':
            out.append('-')
        elif ch in '-_':
            out.append(ch)
    return ''.join(out)


def main(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    # Drop an existing Contents section (up to the next ## heading).
    if CONTENTS in lines:
        start = lines.index(CONTENTS)
        end = start + 1
        while end < len(lines) and not lines[end].startswith('## '):
            end += 1
        del lines[start:end]

    entries = []
    counts = {}
    in_code = False
    for line in lines:
        if line.startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        m = re.match(r'^(#{1,6}) (.*)$', line)
        if not m:
            continue
        text = plain(m.group(2))
        s = slug(text)
        if not s:
            continue
        # Every heading counts towards repeats, as in the viewer.
        if s in counts:
            counts[s] += 1
            anchor = '%s-%d' % (s, counts[s])
        else:
            counts[s] = 0
            anchor = s
        level = len(m.group(1))
        if level in (2, 3):
            entries.append((level, text, anchor))

    toc = [CONTENTS, '']
    for level, text, anchor in entries:
        indent = '  ' if level == 3 else ''
        toc.append('%s- [%s](#%s)' % (indent, text, anchor))
    toc.append('')

    first = next(i for i, l in enumerate(lines) if l.startswith('## '))
    lines[first:first] = toc
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    print('%s: %d entries' % (path, len(entries)))


if __name__ == '__main__':
    main(sys.argv[1])
