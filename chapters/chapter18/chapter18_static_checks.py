"""Chapter 18 static checks; no Snowflake calls or credentials.

Run with Python 3.11+. Without arguments it checks the companion files only.
With --chapter /path/to/Chapter_18_*.md it also checks that every fenced block
in the manuscript appears verbatim in a companion file and runs the editorial
sweeps (block length, quotes, prose semicolons, em dashes, banned phrases,
and a cap of three X-not-Y contrasts).
Documentation review: October 2026. No placeholders.
"""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parent
BANNED = [
    'genuinely', 'actually', 'exactly', 'rather than', 'fundamental',
    'in practice', 'real-world', 'real world', 'load-bearing', 'earns its keep',
    'proves its worth', 'pays back', 'closes the loop', 'heavy lifting',
    'won or lost', 'airtight', 'bulletproof', 'rock-solid', 'mission-critical',
    'comes down to', 'boils down to', 'non-negotiable', 'table stakes',
    'leverage', 'seamless', 'robust', 'delve', 'pivotal', 'crucial',
    'The fix is', 'The rule is', 'The takeaway', 'e.g.', 'i.e.', 'etc.',
]


def check_repo():
    sql_files = sorted(ROOT.glob('*.sql'))
    for file in sql_files:
        text = file.read_text()
        assert text.startswith('-- Chapter 18'), file.name
        assert 'CREATE OR REPLACE' not in text.upper(), file.name
        assert '<REPLACE' not in text, file.name
    return len(sql_files)


def check_chapter(path):
    chapter = path.read_text()
    repo_text = '\n'.join(p.read_text() for p in ROOT.iterdir()
                          if p.is_file() and p.suffix in {'.sql', '.json', '.md', '.py'})
    blocks = re.findall(r'```(\w+)\n(.*?)```', chapter, re.S)
    for language, block in blocks:
        assert block.strip() in repo_text, 'Unmatched chapter snippet: ' + block[:70]
        assert len(block.splitlines()) <= 25, 'Block over 25 lines: ' + block[:70]
        assert not any(c in block for c in '“”‘’'), block[:70]
    prose = re.sub(r'```.*?```', '', chapter, flags=re.S)
    prose = re.sub(r'`[^`]*`', '', prose)
    prose = '\n'.join(line for line in prose.splitlines() if not line.startswith('|'))
    assert ';' not in prose, 'Prose semicolon found'
    assert '—' not in prose, 'Em dash found'
    lower = prose.lower()
    hits = [phrase for phrase in BANNED if phrase.lower() in lower]
    assert not hits, f'Banned phrases: {hits}'
    assert lower.count('production') <= 2, 'production used more than twice'
    contrasts = re.findall(r',\s+not\s|\binstead of\b|\bnot [^.]{0,80}?\bbut\b', lower)
    assert len(contrasts) <= 3, f'Too many X-not-Y contrasts: {len(contrasts)}'
    return len(blocks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--chapter', type=Path)
    args = parser.parse_args()
    print('SQL headers checked:', check_repo())
    if args.chapter:
        print('Manuscript blocks matched:', check_chapter(args.chapter))
    print('PASS')


if __name__ == '__main__':
    main()
