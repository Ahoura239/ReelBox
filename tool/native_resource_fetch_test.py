#!/usr/bin/env python3
"""Offline, serialized JVM regressions; uses the existing Gradle Kotlin cache."""
import argparse
import fcntl
import glob
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'android/app/src/main/kotlin/org/reelbox/reelbox'
TEST = ROOT / 'android/app/src/test/kotlin/org/reelbox/reelbox'


def jar(group, artifact, version):
    matches = glob.glob(str(Path.home() / '.gradle/caches/modules-2/files-2.1' /
                            group / artifact / version / '*' / '*.jar'))
    if len(matches) != 1:
        raise RuntimeError(f'Expected one cached {artifact}:{version}, got {len(matches)}')
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', default='all')
    parser.add_argument('--skip-integration', action='store_true')
    args = parser.parse_args()
    with (ROOT / '.tooling.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        helper = SRC / 'RestrictedResourceFetcher.kt'
        assert helper.exists(), 'RM007: no controlled resource fetcher; WebView owns unchecked redirects'
        version = '2.2.21'
        stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', version)
        annotations = jar('org.jetbrains', 'annotations', '13.0')
        compiler = [jar('org.jetbrains.kotlin', item, version) for item in (
            'kotlin-compiler-embeddable', 'kotlin-stdlib', 'kotlin-reflect',
            'kotlin-script-runtime', 'kotlin-daemon-embeddable')]
        compiler += [annotations, jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0')]
        with tempfile.TemporaryDirectory(prefix='native-resource-test-', dir=os.environ.get('TMPDIR')) as out:
            sources = [SRC / 'NativeUrlPolicy.kt', SRC / 'PlaybackSnapshot.kt', helper,
                       TEST / 'NativePolicyTest.kt', TEST / 'RestrictedResourceFetchTest.kt']
            subprocess.run(['java', '-Xmx256m', '-XX:MaxMetaspaceSize=192m', '-XX:+UseSerialGC',
                            '-cp', os.pathsep.join(compiler), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                            '-no-stdlib', '-no-reflect', '-jvm-target', '17',
                            '-classpath', os.pathsep.join([stdlib, annotations]), '-d', out,
                            *map(str, sources)], check=True, cwd=ROOT, timeout=120)
            classpath = os.pathsep.join([out, stdlib])
            subprocess.run(['java', '-Xmx128m', '-cp', classpath,
                            'org.reelbox.reelbox.tests.NativePolicyTestKt'], check=True, cwd=ROOT, timeout=60)
            subprocess.run(['java', '-Xmx128m', '--add-modules', 'jdk.httpserver', '-cp', classpath,
                            'org.reelbox.reelbox.tests.RestrictedResourceFetchTestKt', args.case], check=True, cwd=ROOT, timeout=60)
        if not args.skip_integration:
            activity = (SRC / 'EmbeddedVideoActivity.kt').read_text()
            start = activity.index('override fun shouldInterceptRequest(')
            end = activity.index('override fun onReceivedSslError', start)
            interceptor = activity[start:end]
            assert 'return null' not in interceptor, 'RM007: interceptor delegates unchecked redirects to WebView'
            assert 'resourceFetcher.fetch(' in interceptor, 'RM007: controlled fetcher is not wired to WebView'
            assert interceptor.count('resourceFetcher.fetch(') == 2, 'Both WebView interceptor overloads must use controlled fetching'
            assert 'request.method, request.requestHeaders' in interceptor, 'Method/range headers are not wired'
            assert 'secureContext = !request.isForMainFrame && securePage' in interceptor, 'Mixed-content guard is missing'
            assert 'handler.cancel()' in activity and 'handler.proceed()' not in activity, 'TLS errors must fail closed'
            assert 'response.body.close()' in activity and 'catch (_: IllegalArgumentException)' in activity, 'Invalid Android response metadata must fail closed'
            print('WebView interceptor source wiring: passed (not a device test)', flush=True)


if __name__ == '__main__':
    main()
