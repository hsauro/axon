"""Checks the Axon Tutorial and writes its LaTeX version.

The tutorial is written once, as the IDE's help pages help/tutorial.md (the
introduction and the list of lessons) and help/tutorial-NN-*.md (one per
lesson, in the order of NN). This script

1. checks their code with axon (Win64/Release, else Win64/Debug):
   - every ```axon block is a complete program that must run without an
     error; when an ```output block follows it, the program must print
     exactly that (standard output, then standard error), and may stop with
     an error. A first line "# name.sci" saves it under that name, which
     error reports show;
   - every ```repl block is a REPL session: `axon --transcript` must
     reproduce it, from its "> " and "... " lines;
2. writes doc/tutorial/lessons/*.tex, one file per page, and
   doc/tutorial/lessons/all.tex, which inputs them in order;
   doc/tutorial/axon-tutorial.tex inputs all.tex.

    python tools/gen_tutorial.py           check, then write the LaTeX
    python tools/gen_tutorial.py --check   check only

It exits with status 1 when a check fails, and then writes nothing.

The pages use a small part of Markdown, which is all this script reads:
"#", "##" and "###" headings; paragraphs; "- " and "1. " lists (an item
continues on lines indented by two spaces); "> " notes; tables; fenced
blocks (axon, output, repl, or any other name for plain text); and inline
`code`, **bold** (a bold text with " > " in it is a menu path),
*emphasis*, <kbd>keys</kbd> and [links](target). In the LaTeX version a
paragraph made only of links to other help pages (the "Contents" and "Next"
lines) is left out, as is everything in help/tutorial.md from the heading
"## The lessons" on, which the PDF's table of contents replaces. A link
keeps only its text. Keep the text ASCII, apart from the few characters
TEXT_CHARS converts.
"""

import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELP = os.path.join(ROOT, 'help')
OUT = os.path.join(ROOT, 'doc', 'tutorial', 'lessons')


# ------------------------------------------------------------------ pages

def pages():
    """The tutorial's pages in order: the introduction, then the lessons."""
    lessons = sorted(f for f in os.listdir(HELP)
                     if re.match(r'tutorial-\d\d-.*\.md$', f))
    return ['tutorial.md'] + lessons


def read_page(name):
    with open(os.path.join(HELP, name), encoding='utf-8') as f:
        return f.read().replace('\r\n', '\n')


# ------------------------------------------------------------------ blocks

def parse(text):
    """The page as a list of blocks: (kind, data)."""
    lines = text.split('\n')
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.strip() == '':
            i += 1
            continue
        m = re.match(r'```(\S*)\s*$', line)
        if m:
            lang = m.group(1)
            body = []
            i += 1
            while i < n and not lines[i].startswith('```'):
                body.append(lines[i])
                i += 1
            i += 1
            blocks.append(('code', (lang, body)))
            continue
        m = re.match(r'(#{1,3}) (.*)$', line)
        if m:
            blocks.append(('heading', (len(m.group(1)), m.group(2).strip())))
            i += 1
            continue
        if line.startswith('|'):
            rows = []
            while i < n and lines[i].startswith('|'):
                rows.append(lines[i])
                i += 1
            blocks.append(('table', rows))
            continue
        if re.match(r'(- |\d+\. )', line):
            ordered = bool(re.match(r'\d+\. ', line))
            items = []
            while i < n:
                m = re.match(r'(- |\d+\. )(.*)$', lines[i])
                if m:
                    items.append(m.group(2))
                    i += 1
                elif lines[i].startswith('  ') and lines[i].strip() and items:
                    items[-1] += ' ' + lines[i].strip()
                    i += 1
                else:
                    break
            blocks.append(('list', (ordered, items)))
            continue
        if line.startswith('>'):
            para = []
            while i < n and lines[i].startswith('>'):
                para.append(lines[i][1:].strip())
                i += 1
            blocks.append(('note', ' '.join(para)))
            continue
        para = []
        while i < n and lines[i].strip() and not lines[i].startswith(('```', '#', '|', '>')) \
                and not re.match(r'(- |\d+\. )', lines[i]):
            para.append(lines[i].strip())
            i += 1
        blocks.append(('para', ' '.join(para)))
    return blocks


# ------------------------------------------------------------------ checks

def axon_exe():
    for config in ('Release', 'Debug'):
        exe = os.path.join(ROOT, 'Win64', config, 'axon.exe')
        if os.path.exists(exe):
            return exe
    sys.exit('gen_tutorial: build axon first (build.cmd Release)')


def normal(text):
    """Text compared line by line, without trailing spaces or blank lines."""
    lines = [l.rstrip() for l in text.replace('\r\n', '\n').split('\n')]
    while lines and lines[-1] == '':
        lines.pop()
    return lines


def check_page(name, blocks, exe, work):
    """The problems found in one page's code, as a list of messages."""
    problems = []
    env = dict(os.environ)
    env['AXON_SHOW_DIR'] = os.path.join(work, 'show')   # no image viewer
    os.makedirs(env['AXON_SHOW_DIR'], exist_ok=True)
    count = 0
    for k, (kind, data) in enumerate(blocks):
        if kind != 'code':
            continue
        lang, body = data
        if lang == 'axon':
            count += 1
            # A first line "# name.sci" names the file (error reports show it).
            m = re.match(r'#\s*(\w+\.sci)\b', body[0]) if body else None
            path = os.path.join(work, m.group(1) if m else 'block%d.sci' % count)
            with open(path, 'w', encoding='utf-8', newline='\n') as f:
                f.write('\n'.join(body) + '\n')
            # Run by its name from its folder, as the IDE does, so error
            # reports name the file as the reader sees it.
            r = subprocess.run([exe, os.path.basename(path)], cwd=work, env=env,
                               capture_output=True, text=True, encoding='utf-8', timeout=120)
            got = r.stdout + r.stderr
            expected = None
            if k + 1 < len(blocks) and blocks[k + 1][0] == 'code' and blocks[k + 1][1][0] == 'output':
                expected = '\n'.join(blocks[k + 1][1][1])
            where = '%s: program %d (%s...)' % (name, count, body[0][:40] if body else '')
            if expected is None:
                if r.returncode != 0:
                    problems.append('%s stopped with an error:\n%s' % (where, got))
            elif normal(got) != normal(expected):
                problems.append('%s printed\n%s\ninstead of\n%s' % (where, got, expected))
        elif lang == 'repl':
            count += 1
            path = os.path.join(work, 'session%d.repl' % count)
            with open(path, 'w', encoding='utf-8', newline='\n') as f:
                f.write('\n'.join(body) + '\n')
            r = subprocess.run([exe, '--transcript', path], cwd=work, env=env,
                               capture_output=True, text=True, encoding='utf-8', timeout=120)
            if normal(r.stdout) != normal('\n'.join(body)):
                problems.append('%s: REPL session %d gave\n%s\ninstead of\n%s'
                                % (name, count, r.stdout, '\n'.join(body)))
    return problems


# ------------------------------------------------------------------ LaTeX

TEXT_CHARS = {
    '\\': r'\textbackslash{}', '&': r'\&', '%': r'\%', '$': r'\$', '#': r'\#',
    '_': r'\_', '{': r'\{', '}': r'\}', '~': r'\textasciitilde{}',
    '^': r'\textasciicircum{}', '"': r'\textquotedbl{}', '<': r'\textless{}',
    '>': r'\textgreater{}', '\u2026': r'\ldots{}', '\u2014': '---', '\u2013': '--',
    '\u00d7': r'\texttimes{}', '\u2192': r'$\rightarrow$', '\u2212': r'$-$',
}


def esc(text):
    return ''.join(TEXT_CHARS.get(c, c) for c in text)


def prose(text):
    """Plain text of a paragraph: a pair of straight quotes becomes `` ''."""
    parts = re.split(r'"([^"]*)"', text)
    out = []
    for k, part in enumerate(parts):
        out.append("``" + esc(part) + "''" if k % 2 else esc(part))
    return ''.join(out)


def code_inline(code, verbatim):
    """Inline code: verbatim (\\code) where it may be, else \\texttt."""
    if not verbatim:
        return r'\texttt{' + esc(code) + '}'
    for d in '|!@+=;:':
        if d not in code:
            return r'\code' + d + code + d
    return r'\texttt{' + esc(code) + '}'


INLINE = re.compile(r'`([^`]+)`|<kbd>(.*?)</kbd>|\*\*(.+?)\*\*|\*(.+?)\*'
                    r'|\[([^\]]+)\]\(([^)]+)\)')


def inline(text, verbatim=True):
    out = []
    pos = 0
    for m in INLINE.finditer(text):
        out.append(prose(text[pos:m.start()]))
        code, key, bold, emph, link, target = m.groups()
        if code is not None:
            out.append(code_inline(code, verbatim))
        elif key is not None:
            out.append(r'\key{' + esc(key) + '}')
        elif bold is not None:
            if ' > ' in bold:
                out.append(r'\menu{' + esc(bold) + '}')
            else:
                out.append(r'\textbf{' + inline(bold, False) + '}')
        elif emph is not None:
            out.append(r'\emph{' + inline(emph, False) + '}')
        else:
            if target.startswith('http'):
                out.append(r'\href{' + target.replace('%', r'\%').replace('#', r'\#') +
                           '}{' + inline(link, False) + '}')
            else:
                out.append(inline(link, verbatim))
        pos = m.end()
    out.append(prose(text[pos:]))
    return ''.join(out)


def only_page_links(text):
    """True for a paragraph of nothing but links to help pages (navigation)."""
    rest = re.sub(r'\[[^\]]*\]\([^)]*\.md[^)]*\)', '', text)
    rest = re.sub(r'\b(Next|Previous|Back|Contents|Tutorial)\b', '', rest)
    return rest.strip(' |:\u00b7-') == ''


def listing(lang, body, after_program):
    """A fenced block as a listing. Output sits close under the program it
    comes from (axonout); after anything else it is spaced as a REPL
    session (axonrepl), which has the same look."""
    env = {'axon': 'axon', 'output': 'axonout', 'repl': 'axonrepl'}.get(lang, 'shell')
    if env == 'axonout' and not after_program:
        env = 'axonrepl'
    text = '\n'.join(body)
    if env in ('axonout', 'axonrepl'):
        text = text.replace('\u00d7', r'(*@\texttimes@*)')
    return '\\begin{%s}\n%s\n\\end{%s}\n' % (env, text, env)


def table(rows):
    cells = [[c.strip() for c in r.strip().strip('|').split('|')] for r in rows]
    cells = [r for r in cells if not all(re.match(r'^:?-+:?$', c) for c in r)]
    ncols = len(cells[0])
    long = any(len(c) > 30 for r in cells for c in r)
    if long and ncols > 1:
        width = 0.6 / (ncols - 1)
        spec = '@{}l' + ('p{%.2f\\linewidth}' % width) * (ncols - 1) + '@{}'
    else:
        spec = '@{}' + 'l' * ncols + '@{}'
    out = ['\\begin{longtable}{%s}' % spec, '\\toprule',
           ' & '.join(inline(c) for c in cells[0]) + ' \\\\',
           '\\midrule']
    for r in cells[1:]:
        out.append(' & '.join(inline(c) for c in r) + ' \\\\')
    out += ['\\bottomrule', '\\end{longtable}', '']
    return '\n'.join(out)


def to_latex(name, blocks):
    out = ['%% Written by tools/gen_tutorial.py from help/%s: edit that page, not this file.\n'
           % name]
    intro = name == 'tutorial.md'
    number = re.match(r'tutorial-(\d\d)-', name)
    for k, (kind, data) in enumerate(blocks):
        if kind == 'heading':
            level, title = data
            if intro and level == 2 and title == 'The lessons':
                break
            title = re.sub(r'^Lesson \d+: ', '', title)
            if level == 1:
                if intro:
                    out.append('\\chapter*{%s}\n\\addcontentsline{toc}{chapter}{%s}\n'
                               % (inline(title, False), inline(title, False)))
                else:
                    out.append('\\chapter{%s}\\label{lesson:%s}\n'
                               % (inline(title, False), number.group(1)))
            elif level == 2:
                out.append('\\section%s{%s}\n' % ('*' if intro else '', inline(title, False)))
            else:
                out.append('\\subsection*{%s}\n' % inline(title, False))
        elif kind == 'para':
            if only_page_links(data):
                continue
            out.append(inline(data) + '\n')
        elif kind == 'note':
            out.append('\\begin{quote}\n%s\n\\end{quote}\n' % inline(data))
        elif kind == 'list':
            ordered, items = data
            env = 'enumerate' if ordered else 'itemize'
            out.append('\\begin{%s}\n%s\n\\end{%s}\n'
                       % (env, '\n'.join('\\item ' + inline(it) for it in items), env))
        elif kind == 'table':
            out.append(table(data))
        elif kind == 'code':
            after = k > 0 and blocks[k - 1][0] == 'code' and blocks[k - 1][1][0] == 'axon'
            out.append(listing(data[0], data[1], after))
    return '\n'.join(out)


# ------------------------------------------------------------------ main

def main():
    check_only = '--check' in sys.argv[1:]
    exe = axon_exe()
    names = pages()
    parsed = {name: parse(read_page(name)) for name in names}
    problems = []
    with tempfile.TemporaryDirectory(prefix='axon-tutorial-') as work:
        for name in names:
            problems += check_page(name, parsed[name], exe, work)
    for p in problems:
        print(p)
        print()
    if problems:
        print('gen_tutorial: %d problem(s) in the tutorial\'s code' % len(problems))
        return 1
    print('gen_tutorial: the code in %d page(s) runs as shown' % len(names))
    if check_only:
        return 0
    os.makedirs(OUT, exist_ok=True)
    inputs = []
    for name in names:
        base = name[:-3]
        with open(os.path.join(OUT, base + '.tex'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(to_latex(name, parsed[name]))
        inputs.append('\\input{lessons/%s}' % base)
    with open(os.path.join(OUT, 'all.tex'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('% Written by tools/gen_tutorial.py: the tutorial\'s pages in order.\n' +
                '\n'.join(inputs) + '\n')
    print('gen_tutorial: wrote doc/tutorial/lessons')
    return 0


if __name__ == '__main__':
    sys.exit(main())
