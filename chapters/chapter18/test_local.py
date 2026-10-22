"""Chapter 18: local tests for allocation and request validation. No Snowflake calls."""
from copy import deepcopy
from datetime import date
from decimal import Decimal
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from allocation import allocate, load_fixture
from selfservice import generate, read_request

ROOT = Path(__file__).resolve().parent
AS_OF = date(2026, 9, 14)


class AllocationTests(unittest.TestCase):
    def setUp(self):
        self.hours, self.owners = load_fixture()

    def test_known_totals_and_idle(self):
        result = allocate(self.hours, self.owners)
        self.assertEqual(result, {
            'CC_PAYMENTS': {'compute': Decimal('18'), 'idle': Decimal('4.2')},
            'CC_RISK': {'compute': Decimal('12'), 'idle': Decimal('2.8')},
        })

    def test_missing_owner(self):
        with self.assertRaises(ValueError):
            allocate(self.hours, self.owners[1:])

    def test_duplicate_metering(self):
        with self.assertRaises(ValueError):
            allocate(self.hours + self.hours[:1], self.owners)

    def test_overlapping_owner(self):
        self.owners.append(deepcopy(self.owners[0]))
        with self.assertRaises(ValueError):
            allocate(self.hours, self.owners)

    def test_invalid_measures(self):
        for value in [None, '', '-1', '99', 'NaN']:
            with self.subTest(value=value):
                hours = deepcopy(self.hours)
                hours[0]['attributed_compute'] = value
                with self.assertRaises(ValueError):
                    allocate(hours, self.owners)

    def test_bad_weights(self):
        for value in ['0', '-0.2', '1.2', 'NaN']:
            with self.subTest(value=value):
                owners = deepcopy(self.owners)
                owners[2]['allocation_share'] = value
                with self.assertRaises(ValueError):
                    allocate(self.hours, owners)

    def test_half_open_effective_boundary(self):
        self.hours[0]['usage_start'] = '2026-10-01 00:00:00'
        later = deepcopy(self.owners[0])
        later.update(cost_center='CC_NEW', valid_from='2026-10-01', valid_to='2026-11-01')
        result = allocate(self.hours, self.owners + [later])
        self.assertEqual(result['CC_NEW']['compute'], Decimal(12))
        self.assertEqual(result['CC_PAYMENTS']['compute'], Decimal(6))

    def test_account_is_part_of_key(self):
        self.hours[0]['account_key'] = 'DIFFERENT'
        with self.assertRaises(ValueError):
            allocate(self.hours, self.owners)

    def test_empty_and_mid_hour(self):
        with self.assertRaises(ValueError):
            allocate([], self.owners)
        self.owners[0]['valid_from'] = '2026-09-01 00:30:00'
        with self.assertRaises(ValueError):
            allocate(self.hours, self.owners)

    def test_sql_allocation_semantics(self):
        # Execute the manuscript's relational SELECT unchanged except table qualifiers.
        # This checks fixture arithmetic/join semantics, not Snowflake dialect acceptance.
        sql = (ROOT / 'chapter18_4_allocation.sql').read_text()
        body = sql.split('-- BLOCK: allocation;')[1].split('-- BLOCK: reconciliation;')[0]
        body = body[body.index('SELECT a.cost_center,'):]
        body = body.replace('CONTROL_DB.COST.', '')
        with sqlite3.connect(':memory:') as db:
            db.execute('CREATE TABLE WAREHOUSE_HOURS(account_key, warehouse_id, usage_start, used_compute, attributed_compute)')
            db.execute('CREATE TABLE OWNERSHIP_MAP(account_key, warehouse_id, cost_center, valid_from, valid_to, allocation_share)')
            db.executemany('INSERT INTO WAREHOUSE_HOURS VALUES(?,?,?,?,?)', [list(r.values()) for r in self.hours])
            db.executemany('INSERT INTO OWNERSHIP_MAP VALUES(?,?,?,?,?,?)', [list(r.values()) for r in self.owners])
            rows = db.execute(body).fetchall()
        self.assertEqual([r[0] for r in rows], ['CC_PAYMENTS', 'CC_RISK'])
        for row, expected in zip(rows, [(18, 4.2), (12, 2.8)]):
            self.assertAlmostEqual(row[1], expected[0])
            self.assertAlmostEqual(row[2], expected[1])


class RequestTests(unittest.TestCase):
    def setUp(self):
        self.request = read_request(ROOT / 'request.json')

    def test_plan_is_deterministic_and_unapproved(self):
        a = generate(self.request, AS_OF)
        self.assertEqual(a, generate(self.request, AS_OF))
        self.assertEqual(a[1]['approval_status'], 'NOT_APPROVED')
        self.assertEqual(a[1]['deployment_status'], 'NOT_DEPLOYED')
        self.assertNotIn(' TO USER ', a[0])
        self.assertIn('WITH MANAGED ACCESS', a[0])
        self.assertIn('DROP SCHEMA SS_PAYMENTS_SANDBOX.PUBLIC;', a[0])
        self.assertIn("COMMENT = 'cost_center=CC_PAYMENTS'", a[0])
        self.assertIn('SET RESOURCE_MONITOR =', a[0])
        self.assertIn('GRANT OWNERSHIP ON DATABASE SS_PAYMENTS_SANDBOX\n'
                      '  TO ROLE SS_PAYMENTS_SANDBOX_ADMIN', a[0])
        # The team ADMIN role, not SYSADMIN, must create the managed schemas.
        admin_part = a[0].split('USE ROLE SS_PAYMENTS_SANDBOX_ADMIN;')[1]
        self.assertIn('CREATE SCHEMA SS_PAYMENTS_SANDBOX.WORK WITH MANAGED ACCESS;',
                      admin_part.split('USE ROLE ACCOUNTADMIN;')[0])

    def test_committed_sample_plan_matches_generator(self):
        plan = generate(self.request, AS_OF)[0]
        self.assertEqual((ROOT / 'sample_plan.sql').read_text(), plan)

    def test_limit_and_expiry_boundaries(self):
        for quota in (1, 100):
            for expiry in ('2026-09-15', '2026-10-14'):
                r = dict(self.request, monthly_credit_limit=quota, expires_on=expiry)
                generate(r, AS_OF)
        for quota in (0, 101, 200, True, 1.5, '20', None):
            with self.subTest(quota=quota), self.assertRaises(ValueError):
                generate(dict(self.request, monthly_credit_limit=quota), AS_OF)
        for expiry in ('2026-09-14', '2026-10-15', 'invalid'):
            with self.subTest(expiry=expiry), self.assertRaises(ValueError):
                generate(dict(self.request, expires_on=expiry), AS_OF)

    def test_registry_types_and_extra_fields(self):
        cases = [dict(self.request, cost_center='CC_OTHER'),
                 dict(self.request, team="PAYMENTS; DROP DATABASE X"),
                 dict(self.request, warehouse_size='LARGE'),
                 dict(self.request, environment='PROD'),
                 dict(self.request, extra='ignored?'), dict(self.request, team=[])]
        for r in cases:
            with self.subTest(request=r), self.assertRaises(ValueError):
                generate(r, AS_OF)

    def test_request_hash_changes(self):
        a = generate(self.request, AS_OF)[1]
        b = generate(dict(self.request, monthly_credit_limit=21), AS_OF)[1]
        self.assertNotEqual(a['request_sha256'], b['request_sha256'])
        self.assertNotEqual(a['plan_sha256'], b['plan_sha256'])

    def test_duplicate_json_key(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'bad.json'
            path.write_text('{"team":"PAYMENTS","team":"RISK"}')
            with self.assertRaises(ValueError):
                read_request(path)

    def test_cli_rejects_without_writing_and_protects_existing_output(self):
        with tempfile.TemporaryDirectory() as temp:
            request = Path(temp) / 'request.json'
            output = Path(temp) / 'output'
            request.write_text(json.dumps(dict(self.request, monthly_credit_limit=200)))
            command = [sys.executable, str(ROOT / 'selfservice.py'), str(request),
                       '--as-of', AS_OF.isoformat(), '--out', str(output)]
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.exists())
            request.write_text(json.dumps(self.request))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            original = (output / 'plan.sql').read_bytes()
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertEqual((output / 'plan.sql').read_bytes(), original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
