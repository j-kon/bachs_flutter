#!/usr/bin/env python3
"""Fail-closed OSV Pub lock audit and redacted tracked-file secret checks.

Uses only Python's standard library. Lock parsing intentionally accepts the
canonical `pub` generated layout; unexpected hosted entries fail the audit.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
LOCKS = ('pubspec.lock', 'server/pubspec.lock', 'example/pubspec.lock')


def pub_packages(text):
    if not re.search(r'^packages:\s*$', text, re.M):
        raise ValueError('Missing packages mapping')
    packages = []
    blocks = re.split(r'^  ([A-Za-z0-9_]+):\s*$', text, flags=re.M)
    for name, body in zip(blocks[1::2], blocks[2::2]):
        source = re.search(r'^    source: (\w+)\s*$', body, re.M)
        version = re.search(r'^    version: "([^"\n]+)"\s*$', body, re.M)
        if not source or not version:
            raise ValueError(f'Unsupported lock entry: {name}')
        if source[1] == 'hosted':
            if not re.search(r'^      url: "https://pub.dev"\s*$', body, re.M):
                raise ValueError(f'Cannot audit non-pub.dev registry: {name}')
            packages.append((name, version[1]))
        elif source[1] not in ('sdk', 'path', 'git'):
            raise ValueError(f'Unknown dependency source: {name}')
    if not packages:
        raise ValueError('No hosted dependencies found; refusing empty audit')
    return packages


def osv_findings(packages, response):
    results = response.get('results')
    if not isinstance(results, list) or len(results) != len(packages):
        raise ValueError('OSV returned an incomplete result set')
    findings = []
    for (name, version), result in zip(packages, results):
        if not isinstance(result, dict) or result.get('next_page_token'):
            raise ValueError('OSV result is invalid or paginated; audit incomplete')
        for vuln in result.get('vulns', []):
            findings.append(f'{name}@{version}: {vuln["id"]}')
    return findings


def audit():
    packages = sorted({p for lock in LOCKS for p in pub_packages((ROOT / lock).read_text())})
    payload = {'queries': [{'package': {'name': n, 'ecosystem': 'Pub'}, 'version': v}
                           for n, v in packages]}
    request = urllib.request.Request('https://api.osv.dev/v1/querybatch',
                                     data=json.dumps(payload).encode(),
                                     headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        findings = osv_findings(packages, json.load(response))
    for finding in findings:
        print(f'VULNERABLE {finding}', file=sys.stderr)
    print(f'OSV: checked {len(packages)} distinct Pub package versions in {len(LOCKS)} locks; '
          f'{len(findings)} advisories.')
    return bool(findings)


PATTERNS = {
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'GitHub token': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b'),
    'AWS access key': re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'Bachs secret': re.compile(r'\b(?:sk_(?:live|sandbox)_|whsec_)[A-Za-z0-9_\-]{4,}\b'),
}
# Exact inert values only, and only in examples/tests. Never exclude entire files.
FIXTURE_SUFFIXES = {'dummy', 'test', 'test_key', 'fixture', 'example', 'test_signing_secret',
                    'REPLACE_WITH_YOUR_KEY', 'REPLACE_WITH_YOUR_WEBHOOK_SECRET'}


def secret_findings(path, text):
    fixture_file = any(part in ('test', 'tests') for part in Path(path).parts) or path.endswith('.example')
    for line_number, line in enumerate(text.splitlines(), 1):
        for kind, pattern in PATTERNS.items():
            for match in pattern.finditer(line):
                suffix = re.sub(r'^(sk_(live|sandbox)_|whsec_)', '', match[0])
                if kind == 'Bachs secret' and fixture_file and suffix in FIXTURE_SUFFIXES:
                    continue
                yield f'{path}:{line_number}: possible {kind} (value redacted)'


def secrets():
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    findings = []
    for name in filter(None, names):
        path = ROOT / name
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if b'\0' not in data:
            findings.extend(secret_findings(name, data.decode('utf-8', errors='replace')))
    for finding in findings:
        print(finding, file=sys.stderr)
    print(f'Tracked-file secret scan: {len(findings)} findings (values never printed).')
    return bool(findings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('osv', 'secrets'))
    args = parser.parse_args()
    try:
        return int(audit() if args.mode == 'osv' else secrets())
    except Exception as error:
        print(f'Security check FAILED: {type(error).__name__}: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
