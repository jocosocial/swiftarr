"""Check how the HTTP profile treats representative Swiftarr response differences."""

import json
import re
import unittest
from pathlib import Path

HERE = Path(__file__).parent


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile = json.loads((HERE / "http-profile.json").read_text())

    def test_preserves_replay_mappings(self):
        raw = json.loads((HERE / "seamail-profile.json").read_text())
        self.assertEqual(self.profile["mappings"], raw["mappings"])

    def test_only_clock_and_fixture_file_dates_are_dropped(self):
        drops = [
            rule["match_conditions"]
            for rule in self.profile["delta_filters"]["rules"]
            if rule["action"]["type"] == "drop"
        ]
        self.assertEqual(len(drops), 2)
        for match in drops:
            self.assertEqual(match["methods"], ["GET"])
            if match["location_type"] == ["body"]:
                self.assertEqual(match["delta_type"], ["response_body_difference"])
                self.assertTrue(re.search(match["path_pattern"], "$.serverTime"))
                self.assertFalse(re.search(match["path_pattern"], "$.startTime"))
                self.assertFalse(re.search(match["url_pattern"], "/api/v3/events"))
            else:
                self.assertEqual(match["header_name"], "last-modified")
                self.assertEqual(match["delta_type"], ["response_header_difference"])
                self.assertFalse(re.search(match["url_pattern"], "/login"))
                self.assertFalse(
                    re.search(match["url_pattern"], "/api/v3/image/full/other.png")
                )

    def test_script_urls_stay_visible_for_review(self):
        rule = next(
            r
            for r in self.profile["delta_filters"]["rules"]
            if r["name"] == "HTML script source changed"
        )
        self.assertEqual(
            rule["action"], {"type": "label", "labels": ["script-source-change"]}
        )
        path = rule["match_conditions"]["path_pattern"]
        self.assertTrue(re.fullmatch(path, "/html/body[2]/script[4]/@src"))
        self.assertFalse(re.fullmatch(path, "/html/body[2]/img[4]/@src"))
