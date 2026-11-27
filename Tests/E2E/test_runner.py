"""Checks route assignment and error reporting for E2E receipts."""

import unittest

from run import registered_hits, route_coverage


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

    def test_coverage_distinguishes_workflows_from_login_requirements(self):
        coverage = route_coverage(
            self.inventory,
            {
                "forum": ["GET /forum/:id"],
                "signed-out": ["GET /forum/:id", "POST /forum/:id"],
            },
        )
        self.assertEqual(coverage["signed_out_only"], ["POST /forum/:id"])
        self.assertEqual(coverage["feature_routes"], ["GET /forum/:id"])
        self.assertEqual(
            coverage["missing_http"], ["GET /forum/favorites", "GET /public/**"]
        )
        self.assertEqual(coverage["registered"], 4)
