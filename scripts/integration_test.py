#!/usr/bin/env python3
"""Integration tests for the mix_safe Mix plugin.

Runs `mix safe` commands in fixture projects and verifies outputs.

Usage:
    python3 scripts/integration_test.py        # run all tests
    python3 scripts/integration_test.py -v     # verbose
"""

import os
import shutil
import subprocess
import sys
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
FIXTURES_DIR = os.path.join(PROJECT_ROOT, "fixtures")
FIXTURES = ["single_app", "umbrella"]


def mix_safe(fixture_name, *args, timeout=180):
    """Run `mix safe <args>` in a fixture directory.

    Returns (exit_code, combined_output).
    """
    fixture_dir = os.path.join(FIXTURES_DIR, fixture_name)
    cmd = ["mix", "safe"] + list(args)
    result = subprocess.run(
        cmd,
        cwd=fixture_dir,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    output = result.stdout + result.stderr
    return result.returncode, output


def cleanup_build(fixture_name):
    """Remove _build directory from a fixture."""
    build_dir = os.path.join(FIXTURES_DIR, fixture_name, "_build")
    if os.path.isdir(build_dir):
        shutil.rmtree(build_dir)


def clean_fingerprint(fixture_name):
    """Remove fingerprint.json from a fixture."""
    fingerprint_path = os.path.join(FIXTURES_DIR, fixture_name, "fingerprint.json")
    if os.path.isfile(fingerprint_path):
        os.remove(fingerprint_path)


def setUpModule():
    """Compile plugin and install deps for all fixtures."""
    for fixture in FIXTURES:
        cleanup_build(fixture)
        clean_fingerprint(fixture)

    print("Fetching mix_safe dependencies...")
    result = subprocess.run(
        ["mix", "deps.get"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        raise RuntimeError("Plugin dep fetch failed")

    print("Compiling mix_safe plugin...")
    result = subprocess.run(
        ["mix", "compile"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        raise RuntimeError("Plugin compilation failed")

    for fixture in FIXTURES:
        fixture_dir = os.path.join(FIXTURES_DIR, fixture)
        print(f"Installing deps for fixture: {fixture}")
        result = subprocess.run(
            ["mix", "deps.get"],
            cwd=fixture_dir,
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode != 0:
            print(result.stdout + result.stderr, file=sys.stderr)
            raise RuntimeError(f"Fixture {fixture!r} dep fetch failed")

        print(f"Compiling fixture: {fixture}")
        result = subprocess.run(
            ["mix", "compile"],
            cwd=fixture_dir,
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode != 0:
            print(result.stdout + result.stderr, file=sys.stderr)
            raise RuntimeError(f"Fixture {fixture!r} compilation failed")


def tearDownModule():
    """Clean up build dirs and fingerprint files for all fixtures."""
    for fixture in FIXTURES:
        cleanup_build(fixture)
        clean_fingerprint(fixture)


# ---------------------------------------------------------------------------
# Common tests
# ---------------------------------------------------------------------------
class TestCommon(unittest.TestCase):
    fixture = "single_app"

    def test_help(self):
        code, output = mix_safe(self.fixture, "help")
        self.assertEqual(0, code, output)
        self.assertIn("SAFE security vulnerability scan", output)

    def test_no_subcommand(self):
        code, output = mix_safe(self.fixture)
        self.assertNotEqual(0, code, output)
        self.assertIn("No subcommand specified", output)

    def test_unrecognised_subcommand(self):
        code, output = mix_safe(self.fixture, "foobar")
        self.assertNotEqual(0, code, output)
        self.assertIn("Unrecognised subcommand", output)


# ---------------------------------------------------------------------------
# single_app tests
# ---------------------------------------------------------------------------
class TestSingleApp(unittest.TestCase):
    fixture = "single_app"

    def setUp(self):
        clean_fingerprint(self.fixture)

    def test_fingerprint(self):
        fingerprint_path = os.path.join(FIXTURES_DIR, self.fixture, "fingerprint.json")
        self.assertFalse(
            os.path.isfile(fingerprint_path),
            "fingerprint.json should not exist before fingerprinting",
        )

        code, output = mix_safe(self.fixture, "fingerprint")
        self.assertEqual(0, code, output)
        self.assertIn("fingerprint complete", output.lower())
        self.assertTrue(
            os.path.isfile(fingerprint_path),
            "fingerprint.json should exist after fingerprinting",
        )

    def test_analyse(self):
        code, output = mix_safe(self.fixture, "analyse")

        # Exit 0: success (no vulns). Exit 2: vulns found. Exit 1: error (e.g. no license).
        self.assertIn(code, [0, 1, 2], output)
        if code == 0:
            self.assertIn("SAFE analysis complete", output)
        else:
            self.assertTrue(len(output) > 0, "Expected output on non-zero exit")


# ---------------------------------------------------------------------------
# umbrella tests
# ---------------------------------------------------------------------------
class TestUmbrella(unittest.TestCase):
    fixture = "umbrella"

    def setUp(self):
        clean_fingerprint(self.fixture)

    def test_fingerprint(self):
        fingerprint_path = os.path.join(FIXTURES_DIR, self.fixture, "fingerprint.json")
        self.assertFalse(
            os.path.isfile(fingerprint_path),
            "fingerprint.json should not exist before fingerprinting",
        )

        code, output = mix_safe(self.fixture, "fingerprint")
        self.assertEqual(0, code, output)
        self.assertIn("fingerprint complete", output.lower())
        self.assertTrue(
            os.path.isfile(fingerprint_path),
            "fingerprint.json should exist after fingerprinting",
        )

    def test_analyse(self):
        code, output = mix_safe(self.fixture, "analyse")

        self.assertIn(code, [0, 1, 2], output)
        if code == 0:
            self.assertIn("SAFE analysis complete", output)
        else:
            self.assertTrue(len(output) > 0, "Expected output on non-zero exit")


if __name__ == "__main__":
    unittest.main()
