"""Chapter 18 independent Decimal allocation checks for the synthetic fixture.

Python 3.11+, standard library, no network. CSV inputs mirror the SQL fixture.
Not a general invoice reconciler. Rejects unavailable idle attribution.
"""
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_fixture():
    with (ROOT / 'warehouse_hours.csv').open(newline='') as f:
        hours = list(csv.DictReader(f))
    with (ROOT / 'ownership_map.csv').open(newline='') as f:
        owners = list(csv.DictReader(f))
    return hours, owners


def number(value):
    if value is None or value == '':
        raise ValueError('unavailable measure')
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError('non-finite measure')
    return result


def allocate(hours, owners):
    if not hours:
        raise ValueError('no metering records; not evidence of zero spend')
    normalized = []
    for row in owners:
        start, end = (datetime.fromisoformat(row[k]) for k in ['valid_from', 'valid_to'])
        if start >= end or any(t.minute or t.second or t.microsecond for t in (start, end)):
            raise ValueError('ownership intervals must be ordered and hour-aligned')
        share = number(row['allocation_share'])
        if not 0 < share <= 1 or not row['cost_center']:
            raise ValueError('invalid ownership share or cost center')
        for previous, a, b, _ in normalized:
            key = ('account_key', 'warehouse_id', 'cost_center')
            if all(row[k] == previous[k] for k in key) and start < b and end > a:
                raise ValueError('overlapping ownership for a cost center')
        normalized.append((row, start, end, share))
    seen = set()
    result = defaultdict(lambda: {'compute': Decimal(0), 'idle': Decimal(0)})
    source_compute, source_idle = Decimal(0), Decimal(0)
    for hour in hours:
        key = tuple(hour[k] for k in ('account_key', 'warehouse_id', 'usage_start'))
        if key in seen:
            raise ValueError('duplicate metering key')
        seen.add(key)
        when = datetime.fromisoformat(hour['usage_start'])
        if when.minute or when.second or when.microsecond:
            raise ValueError('metering must use UTC hour boundaries')
        used, attributed = number(hour['used_compute']), number(hour['attributed_compute'])
        if used < 0 or attributed < 0 or attributed > used:
            raise ValueError('invalid compute or attribution measure')
        matches = [(r, share) for r, a, b, share in normalized
                   if r['account_key'] == hour['account_key']
                   and r['warehouse_id'] == hour['warehouse_id'] and a <= when < b]
        if sum((share for _, share in matches), Decimal(0)) != 1:
            raise ValueError('missing or incomplete allocation')
        if len(matches) != len({r['cost_center'] for r, _ in matches}):
            raise ValueError('duplicate cost-center assignment')
        for row, share in matches:
            result[row['cost_center']]['compute'] += used * share
            result[row['cost_center']]['idle'] += (used - attributed) * share
        source_compute += used
        source_idle += used - attributed
    if sum(r['compute'] for r in result.values()) != source_compute:
        raise ValueError('compute reconciliation failed')
    if sum(r['idle'] for r in result.values()) != source_idle:
        raise ValueError('idle reconciliation failed')
    return dict(result)


if __name__ == '__main__':
    for owner, amounts in sorted(allocate(*load_fixture()).items()):
        print(owner, 'compute=', amounts['compute'], 'idle=', amounts['idle'])
