#!/usr/bin/env python3
"""Verify Reelbox's signed ARM64 release APK without reading signing secrets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--android-sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', '/root/developer-tools/android')))
    parser.add_argument('--build-tools', default='36.0.0')
    parser.add_argument('--baseline-apk', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    tools = args.android_sdk / 'build-tools' / args.build_tools

    def run(tool, *arguments):
        result = subprocess.run([str(tools / tool), *map(str, arguments)], capture_output=True, text=True, check=True)
        return result.stdout + result.stderr

    badging = run('aapt', 'dump', 'badging', args.apk)
    signature = run('apksigner', 'verify', '--verbose', '--print-certs', args.apk)
    (args.output_dir / 'apk-badging.log').write_text(badging)
    (args.output_dir / 'apk-signature.log').write_text(signature)
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    assert package and package.groups() == ('org.reelbox.app', '2', '0.2.0'), 'Wrong package/version; never deliver a stale APK'
    assert 'application-debuggable' not in badging, 'Debuggable APK'
    minimum = re.search(r"^sdkVersion:'(\d+)'", badging, re.M)
    target = re.search(r"^targetSdkVersion:'(\d+)'", badging, re.M)
    assert minimum and minimum.group(1) == '24'
    assert target and target.group(1) == '36'
    assert 'CN=Reelbox Local Release' in signature and 'Android Debug' not in signature
    signer = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)', signature)
    assert signer, 'No certificate digest'
    with zipfile.ZipFile(args.apk) as archive:
        assert archive.testzip() is None, 'APK ZIP corruption'
        names = archive.namelist()
        abis = sorted({name.split('/')[1] for name in names if name.startswith('lib/') and name.endswith('.so')})
        assert abis == ['arm64-v8a'], 'Unsupported or dependency-only ABI advertised'
        for library in ['libapp.so', 'libflutter.so', 'libmpv.so']:
            assert 'lib/arm64-v8a/' + library in names, 'Missing ' + library
        assert 'assets/flutter_assets/kernel_blob.bin' not in names, 'Debug kernel found'
    baseline_matches = None
    if args.baseline_apk:
        baseline = run('apksigner', 'verify', '--print-certs', args.baseline_apk)
        old = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)', baseline)
        assert old and old.group(1).lower() == signer.group(1).lower(), 'Cannot upgrade the delivered beta: signer mismatch'
        baseline_matches = True
    report = {
        'passed': True, 'apk': str(args.apk.resolve()), 'bytes': args.apk.stat().st_size,
        'sha256': digest(args.apk), 'package': package.group(1), 'version_code': 2,
        'version_name': '0.2.0', 'min_sdk': 24, 'target_sdk': 36, 'abis': abis,
        'release_signer': 'CN=Reelbox Local Release', 'signer_sha256': signer.group(1).lower(),
        'same_signer_as_delivered_beta': baseline_matches, 'zip_integrity': True,
        'core_native_libraries_present': True, 'debuggable': False,
        'android_hardware_verified': False,
    }
    (args.output_dir / 'apk-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
