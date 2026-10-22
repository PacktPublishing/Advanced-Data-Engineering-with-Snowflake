#!/usr/bin/env python3
"""Offline scope and manuscript checks; does NOT claim Snowflake execution."""
import argparse
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
TOKEN = re.compile(r"--[^\n]*|/\*[\s\S]*?\*/|'(?:''|\\.|[^'])*'|\"(?:\"\"|[^\"])*\"|[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|\S")

def tokens(text):
    # Preserve case and content inside literals/quoted identifiers. Ignore only
    # comments and whitespace outside them; a changed policy string must fail.
    return [t if t.startswith(("'", '"')) else t.lower()
            for t in TOKEN.findall(text) if not t.startswith(('--', '/*'))]

def contains(haystack, needle):
    return any(haystack[i:i+len(needle)] == needle
               for i in range(len(haystack)-len(needle)+1))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manuscript', type=Path)
    args = ap.parse_args()
    failures = []
    def check(condition, message):
        if not condition: failures.append(message)
    names = ['chapter15_0_setup.sql', 'chapter15_1_tagging.sql',
             'chapter15_2_masking.sql', 'chapter15_3_row_security.sql',
             'chapter15_4_quality.sql', 'chapter15_5_documentation.sql',
             'chapter15_teardown.sql', 'chapter15_live_checks.sql',
             'chapter15_coco_audit.sql']
    for name in names + ['README.md', 'VALIDATION.md']:
        check((HERE/name).is_file(), f'Missing {name}')
    files = {n:(HERE/n).read_text() for n in names if (HERE/n).is_file()}
    clean = {n:' '.join(tokens(s)) for n,s in files.items()}
    for n,s in clean.items():
        check(not re.search(r'(?:alter|drop|truncate|insert into|delete from|update|merge into) (?:table |schema |database |view )?gold_db\b', s), f'{n}: writes shared GOLD_DB')
        check('drop all row access policies' not in s, f'{n}: blanket policy removal')
        check(not re.search(r'grant role pii_reader to role', s), f'{n}: unmask role inherited by parent')
        check('exception when other' not in s, f'{n}: catch-all hides cleanup failures')
        check('use secondary roles none' in s, f'{n}: missing explicit role isolation')
    setup = clean['chapter15_0_setup.sql']
    check(setup.index('show databases') < setup.index('create role'), 'Database collision guard must precede creation')
    check(setup.index('show roles') < setup.index('create role'), 'Role collision guard must precede creation')
    check(' clone ' not in setup, 'CTAS fixture must not inherit RELY constraints through CLONE')
    teardown = clean['chapter15_teardown.sql']
    check(teardown.index('show roles') < teardown.index('drop database'), 'Teardown must check every reserved role before dropping data')
    check("'Chapter 15 isolated governance lab v3'" in teardown, 'Missing teardown ownership marker')
    quality = clean['chapter15_4_quality.sql']
    check('freshness on ( )' in quality, 'FRESHNESS must use the documented table-modification form')
    before = quality.index('await_orphan_result ( true )')
    deletion = quality.index('delete from')
    after = quality.index('await_orphan_result ( false )')
    check(before < deletion < after, 'Incident deletion must follow failure wait and precede recovery wait')
    for condition in ('scheduled_time > : boundary', 'measurement_time > : boundary',
                      "metric_schema = 'QUALITY'", "expectation_name = 'NO_ORPHAN_MERCHANTS'"):
        check(condition in quality, f'Wait lacks correlation condition {condition}')
    check("'MINUTE' , 30" in quality and 'raise timed_out' in quality, 'Wait must time out explicitly')
    check("'use_table_data' : false" in clean['chapter15_5_documentation.sql'], 'Description generation must be metadata-only')
    if args.manuscript:
        text = args.manuscript.read_text()
        script_tokens = [tokens(s) for s in files.values()]
        prompt_text = ' '.join(line[2:].strip() for line in files['chapter15_5_documentation.sql'].splitlines() if line.startswith('--'))
        blocks = re.findall(r'```(\w+)\n(.*?)```', text, re.S)
        for lang,block in blocks:
            first = block.strip().splitlines()[0]
            if lang == 'sql':
                check(any(contains(t, tokens(block)) for t in script_tokens), f'Manuscript SQL drift: {first}')
            elif lang == 'text':
                check(' '.join(block.split()) in ' '.join(prompt_text.split()), f'Prompt drift: {first}')
            check(len(block.strip().splitlines()) <= 27, f'Overlong code block: {first}')
        for line in text.splitlines():
            if line.startswith('## '): check(not re.match(r'## \d',line), f'Numbered main heading: {line}')
            if line.startswith('### '): check(bool(re.match(r'### \d+\.\d+ ',line)), f'Missing subsection number: {line}')
        body = text.split('## Tagging and classifying',1)[-1]
        check(not re.search(r'chapter15_[\w]+\.(?:sql|py|md)', body), 'Companion filename in chapter body')
        intro = text.split('In this chapter, we will cover')[0].split('\n',1)[1]
        check(len(intro.split()) < 150, 'Opening exceeds Packt 150-word limit')
        check('—' not in text, 'Em dash in manuscript')
        print(f'Manuscript: {len(text.split()):,} words; {len(blocks)} fenced blocks.')
    if failures:
        print('\n'.join('FAIL: '+f for f in failures)); return 1
    print('PASS: offline scope, incident ordering, and requested manuscript alignment checks.')
    print('Live SQL execution and behavior remain separate evidence in VALIDATION.md.')
    return 0

if __name__ == '__main__': sys.exit(main())
