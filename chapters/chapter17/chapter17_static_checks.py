"""Chapter 17 local validation; no Snowflake calls or credentials.

Run with Python 3.10+ using --chapter /path/to/canonical/chapter.md to include
snippet/editorial checks. Tests relational fixture behavior with SQLite and
arithmetic with stdlib. These do not validate Snowflake privileges or APIs.
Documentation review: October 2026. No reader-specific placeholders here.
"""

from pathlib import Path
import argparse
import base64
import hashlib
import json
import re
import sqlite3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--chapter', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    results = {}
    setup = (root / 'chapter17_0_provider_setup.sql').read_text()
    product = (root / 'chapter17_1_product.sql').read_text()
    rows = re.search(r'INSERT INTO .*? VALUES\s*(.*?);', setup, re.S)[1]
    projection = re.search(r'CREATE SECURE VIEW\s+\S+ AS\s*(.*?);', product, re.S)[1]
    projection = projection.replace('SOURCE_DB.PRIVATE.MERCHANT_DAILY', 'source')
    with sqlite3.connect(':memory:') as conn:
        conn.execute('CREATE TABLE source (merchant_id INTEGER, settlement_date TEXT, '
                     'currency TEXT, net_settled_amount NUMERIC, operational_note TEXT)')
        conn.execute('INSERT INTO source VALUES ' + rows)
        conn.execute('CREATE VIEW product AS ' + projection)
        cursor = conn.execute('SELECT * FROM product')
        output = cursor.fetchall()
        assert len(output) == 2
        assert {r[0] for r in output} == {101}
        assert {r[2] for r in output} == {'USD'}
        assert sum(r[3] for r in output) == 250
        assert [c[0] for c in cursor.description] == [
            'merchant_id', 'settlement_date', 'currency', 'net_settled_amount']
        duplicates = ('SELECT merchant_id, settlement_date, currency, COUNT(*) '
                      'FROM product GROUP BY merchant_id, settlement_date, currency '
                      'HAVING COUNT(*) > 1')
        assert conn.execute(duplicates).fetchall() == []
        conn.execute('INSERT INTO source SELECT * FROM source WHERE merchant_id = 101 LIMIT 1')
        assert len(conn.execute(duplicates).fetchall()) == 1
        results['relational_fixture_and_duplicate_detection'] = 'PASS (SQLite semantics only)'

    def identities(start, stop, prefix='person-'):
        return {base64.b64encode(hashlib.sha256(
            f'{prefix}{n}@example.invalid'.encode()).digest()).decode()
            for n in range(start, stop + 1)}

    owner, partner = identities(1, 60), identities(41, 100)
    assert len(owner) == len(partner) == 60
    assert len(owner & partner) == 20
    small = identities(1, 5, 'small-')
    assert len(small & small) == 5 and len(small & small) < 10
    results['clean_room_expected_overlap'] = {'normal': 20, 'small': 5,
                                             'live_policy_enforcement': 'NOT_RUN'}
    assert 20 * 500 - (2000 + 600 + 1500 + 400) == 5500
    results['illustrative_contribution'] = 5500
    all_files = list(root.glob('*.sql'))
    for file in all_files:
        data = file.read_text()
        assert data.startswith('-- Chapter 17:'), file.name
        # Every header states its validation: not executed, or the live-run date.
        assert ('not executed in Snowflake' in data
                or 'executed in Snowflake on 20' in data), file.name
        assert 'CREATE OR REPLACE' not in data.upper(), file.name
        assert '1.1.84' not in data, file.name
    results['sql_headers_and_no_replacement_ddl'] = len(all_files)
    # Every share that backs a listing is created in exactly one script.
    for share in ('PARTNER_LISTING_SHARE', 'MARKETPLACE_LISTING_SHARE', 'INTERNAL_LISTING_SHARE'):
        creators = [f.name for f in all_files if f'CREATE SHARE {share};' in f.read_text()]
        assert len(creators) == 1, (share, creators)
    inventory = (root / 'product_inventory.csv').read_text()
    assert 'CH17_' not in inventory
    results['listing_shares_and_inventory'] = 'PASS'

    if args.chapter:
        chapter = args.chapter.read_text()
        blocks = re.findall(r'```(\w+)\n(.*?)```', chapter, re.S)
        repo_text = '\n'.join(p.read_text() for p in root.iterdir() if p.is_file())
        for language, block in blocks:
            assert block in repo_text, 'Unmatched chapter snippet: ' + block[:70]
            assert len(block.splitlines()) <= 25
            assert not any(c in block for c in '“”‘’')
        main = re.findall(r'^## (.+)$', chapter, re.M)
        assert len(main) == 7 and main[0] == 'Technical Requirements' and main[-1] == 'Summary'
        topics = re.findall(r'^- (.+)$', chapter.split('## Technical Requirements')[0], re.M)
        assert topics == main[1:-1]
        headings = re.findall(r'^### (.+)$', chapter, re.M)
        assert len(headings) == 14, len(headings)
        assert all(re.match(r'\d+\.\d+ [A-Z]', h) for h in headings)
        assert all(':' not in h and '—' not in h for h in main + headings)
        intro = chapter.split('In this chapter, we will cover')[0].split('\n\n')[1:]
        assert len(' '.join(intro).split()) < 150
        summary = chapter.split('## Summary\n\n')[1].strip().split('\n\n')
        assert 5 <= len(summary) <= 7
        assert all('we' in para.lower() for para in summary)
        assert chapter.count('> **WARNING**') == 2
        prose = re.sub(r'```.*?```', '', chapter, flags=re.S)
        banned = ['exactly', 'genuinely', 'fundamental', 'delve', 'leverage',
                  'in practice', 'real-world', 'earns its keep', 'does the heavy lifting',
                  'rather than', 'actually', 'Cortex Code', 'At the time of writing']
        hits = [word for word in banned if re.search(r'\b' + re.escape(word) + r'\b', prose, re.I)]
        assert not hits, hits
        assert '—' not in chapter
        assert '](http' not in chapter, 'markdown hyperlink present'
        no_inline = re.sub(r'`[^`]*`', '', prose)
        semicolon_lines = [l for l in no_inline.splitlines() if ';' in l and not l.startswith('|')]
        assert not semicolon_lines, semicolon_lines[:3]
        expect_openers = len(re.findall(r'^Expect ', prose, re.M))
        assert expect_openers <= 3, expect_openers
        results['chapter_alignment'] = {'blocks': len(blocks), 'main_sections': 5,
                                         'subsections': len(headings),
                                         'words': len(chapter.split()),
                                         'voice_and_structure': 'PASS'}
    results['snowflake_live_execution'] = 'NOT_RUN'
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
