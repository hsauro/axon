"""Writes the macOS deployment entries of ide/AxonIDE.dproj.

The IDE runs `axon` from its own folder and reads stdlib/, examples/ and help/
next to it (Contents/MacOS in the app bundle). On Windows axon.dproj's
post-build step copies those files; on macOS PAServer deploys only the files
listed in the project's Deployment section, one entry per file. This script
replaces the entries it owns (Class="File" on OSXARM64 with a LocalName from
the lists below) with the current files, so rerun it after adding or removing
an example, help page or stdlib file:

    python tools/gen_mac_deploy.py

Close the project in RAD Studio first (or reload it afterwards), since the IDE
rewrites the .dproj when it saves.
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DPROJ = os.path.join(ROOT, 'ide', 'AxonIDE.dproj')


def files():
    """(local name relative to ide/, remote dir, remote name, executable, config)."""
    out = []
    for cfg in ('Debug', 'Release'):
        out.append(('..\\OSXARM64\\%s\\axon' % cfg, 'Contents\\MacOS\\', 'axon', True, cfg))
    # Native libraries (libopenblas.dylib, ...) go next to axon, where it
    # looks first.
    for path in sorted(glob.glob(os.path.join(ROOT, 'lib', 'macos', '*.dylib'))):
        name = os.path.basename(path)
        for cfg in ('Debug', 'Release'):
            out.append(('..\\lib\\macos\\' + name, 'Contents\\MacOS\\', name, False, cfg))
    groups = [
        ('stdlib', ['stdlib/*.sci', 'stdlib/package.toml']),
        ('examples', ['examples/*.sci']),
        ('help', ['help/*.md', 'doc/Axon-Language-Reference.md', 'doc/Axon-White-Paper.md']),
    ]
    for remote, patterns in groups:
        for pattern in patterns:
            for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
                rel = os.path.relpath(path, ROOT).replace('/', '\\')
                name = os.path.basename(path)
                for cfg in ('Debug', 'Release'):
                    out.append(('..\\' + rel, 'Contents\\MacOS\\%s\\' % remote, name, False, cfg))
    return out


def entry(local, remote_dir, remote_name, executable, cfg):
    op = '1' if executable else '0'
    return ('                <DeployFile LocalName="%s" Configuration="%s" Class="File">\n'
            '                    <Platform Name="OSXARM64">\n'
            '                        <RemoteDir>%s</RemoteDir>\n'
            '                        <RemoteName>%s</RemoteName>\n'
            '                        <Operation>%s</Operation>\n'
            '                        <Overwrite>true</Overwrite>\n'
            '                    </Platform>\n'
            '                </DeployFile>\n') % (local, cfg, remote_dir, remote_name, op)


def owned(local):
    return (re.match(r'\.\.\\OSXARM64\\(Debug|Release)\\axon$', local) is not None or
            local.startswith(('..\\lib\\macos\\', '..\\stdlib\\', '..\\examples\\', '..\\help\\', '..\\doc\\')))


def main():
    with open(DPROJ, 'rb') as f:
        raw = f.read()
    bom = raw.startswith(bytes([0xEF, 0xBB, 0xBF]))
    text = raw.decode('utf-8-sig')
    # Drop the entries this script wrote before.
    block = re.compile(r'[ \t]*<DeployFile LocalName="([^"]*)"[^>]*Class="File">.*?</DeployFile>\r?\n',
                       re.S)
    removed = 0

    def drop(m):
        nonlocal removed
        if owned(m.group(1)):
            removed += 1
            return ''
        return m.group(0)

    text = block.sub(drop, text)
    new = ''.join(entry(*f) for f in files())
    end = text.index('            </Deployment>')
    newline = '\r\n' if '\r\n' in text else '\n'
    text = text[:end] + new.replace('\n', newline) + text[end:]
    with open(DPROJ, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
        f.write(text)
    print('%s: %d entries (replaced %d)' % (os.path.relpath(DPROJ, ROOT), len(files()), removed))


if __name__ == '__main__':
    main()
