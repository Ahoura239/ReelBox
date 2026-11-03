#!/usr/bin/env python3
"""Run all Flutter test files, including real-worker host registration.

The multipart file needs a Linux path-provider registrant in spawned isolates.
Run it in its own invocation, not by skipping its cases in the normal suite.
All Flutter tooling shares the project's existing lock. This is host evidence,
not Android hardware or process-kill/restart verification.
"""
from __future__ import annotations

import argparse
import fcntl
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default=shutil.which('flutter'))
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if not args.flutter:
        parser.error('Flutter was not found; provide --flutter /path/to/flutter')
    root = Path(__file__).resolve().parents[1]
    output = (args.output_dir or root / 'build' / 'host-verification').resolve()
    output.mkdir(parents=True, exist_ok=True)
    files = sorted(p.relative_to(root).as_posix() for p in (root / 'test').rglob('*_test.dart'))
    multipart = 'test/download_multipart_http_test.dart'
    if multipart not in files:
        parser.error('Required real-worker multipart test file is missing')
    ordinary = [p for p in files if p != multipart]
    common = [args.flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', '--timeout=90s']
    stages = [
        ('analysis', [args.flutter, 'analyze'], []),
        ('ordinary', common + ordinary, ordinary),
        ('multipart', common + ['--dart-define=flutter.dart_plugin_registrant=' + (root / multipart).as_uri(), multipart], [multipart]),
    ]
    report = {
        'scope': 'all Flutter test files; real multipart HTTP/workers run separately with required host registration',
        'android_hardware_verified': False,
        'expected_test_files': files,
        'covered_test_files': [],
        'stages': [],
        'passed': False,
    }
    result = 0
    with (root / '.tooling.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for name, command, covered in stages:
            log = output / (name + '.log')
            print('Running ' + name + ' -> ' + str(log), flush=True)
            try:
                with log.open('w') as stream:
                    code = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=1200, check=False).returncode
            except subprocess.TimeoutExpired:
                code = 124
            text = log.read_text(errors='replace')
            counts = re.findall(r'\+(\d+)(?: -\d+)?: All tests passed!', text)
            stage = {'name': name, 'command': command, 'exit_code': code, 'log': str(log)}
            if covered:
                stage['passed_test_count'] = int(counts[-1]) if counts else None
                if code == 0 and not counts:
                    code = 1
                    stage['exit_code'] = code
                    stage['verification_error'] = 'Missing successful nonempty test summary'
            report['stages'].append(stage)
            if code == 0:
                report['covered_test_files'].extend(covered)
            else:
                result = code
                break
        report['passed'] = result == 0 and sorted(report['covered_test_files']) == files
        if report['passed']:
            report['passed_test_count'] = sum(stage.get('passed_test_count', 0) for stage in report['stages'])
    (output / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['passed', 'expected_test_files', 'covered_test_files']}), flush=True)
    print('Verification report: ' + str(output / 'verification.json'), flush=True)
    return 0 if report['passed'] else (result or 1)


if __name__ == '__main__':
    sys.exit(main())
