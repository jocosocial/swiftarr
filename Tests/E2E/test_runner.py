"""Checks route assignment and error reporting for E2E receipts."""

import unittest

from run import registered_hits


class CoverageTests(unittest.TestCase):
    inventory = """
| GET | /forum/:id |
| GET | /forum/favorites |
| POST | /forum/:id |
| GET | /public/** |
"""

    def test_verbs_literals_and_wildcards(self):
        actual = registered_hits(
            self.inventory,
            [
                ("GET", "/forum/favorites?limit=1"),
                ("GET", "/forum/42"),
                ("GET", "/forum/43"),
                ("POST", "/forum/42"),
                ("GET", "/public/guides/deck.md"),
            ],
        )
        self.assertEqual(
            actual,
            [
                "GET /forum/:id",
                "GET /forum/favorites",
                "GET /public/**",
                "POST /forum/:id",
            ],
        )

    def test_unknown_route_cannot_earn_credit(self):
        with self.assertRaises(AssertionError):
            registered_hits(self.inventory, [("DELETE", "/forum/42")])
