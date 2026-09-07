"""Rebuild AWG native libraries and Interface.class without changing other AAR classes.

Inputs are the pinned, overlaid source checkouts and the application's existing AAR.
No APK is built. The output is a separate AAR; inspect it before replacing the input.
"""
import argparse
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

p = argparse.ArgumentParser()
for name in ['go', 'ndk', 'java', 'sdk', 'annotations', 'android', 'core', 'base-aar', 'out']:
    p.add_argument('--'+name, required=True, type=Path)
a = p.parse_args()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, GOTOOLCHAIN='local', GOPATH=str(out/'gopath'), GOSUMDB='sum.golang.org', GOPROXY='https://proxy.golang.org,direct')
go = str(a.go.resolve())
goroot = Path(subprocess.check_output([go, 'env', 'GOROOT'], env=env, text=True).strip())
overlay = {}
for arch in ['386', 'amd64', 'arm', 'arm64']:
    original = goroot/'src/runtime'/f'sys_linux_{arch}.s'
    text = original.read_text()
    if arch in ['arm', 'arm64']:
        text = re.sub(r'(#define CLOCK_MONOTONIC\s+)1', r'\g<1>7', text)
    else:
        text = re.sub(r'\$1(?=[^\n]*// CLOCK_MONOTONIC)', '$7', text)
    text = text.replace('CLOCK_MONOTONIC', 'CLOCK_BOOTTIME')
    patched = out/original.name
    patched.write_text(text, newline='\n')
    overlay[str(original)] = str(patched)
overlay_path = out/'boottime-overlay.json'
overlay_path.write_text(json.dumps({'Replace': overlay}))
module = a.android.resolve()/'tunnel/tools/libwg-go'
subprocess.run([go, 'mod', 'edit', '-replace=github.com/amnezia-vpn/amneziawg-go/v3='+a.core.resolve().as_posix()], cwd=module, env=env, check=True)
subprocess.run([go, 'mod', 'tidy'], cwd=module, env=env, check=True)
platform = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
binpath = a.ndk.resolve()/'toolchains/llvm/prebuilt'/platform/'bin'
abis = {'arm64-v8a': ('arm64','aarch64'), 'armeabi-v7a': ('arm','armv7a'), 'x86': ('386','i686'), 'x86_64': ('amd64','x86_64')}

def build(item):
    abi, (arch, target) = item
    dest = out/abi/'libwg-go.so'
    dest.parent.mkdir(exist_ok=True)
    compiler = binpath/(target+'-linux-androideabi21-clang' if arch == 'arm' else target+'-linux-android21-clang')
    if os.name == 'nt': compiler = compiler.with_suffix('.cmd')
    buildenv = dict(env, GOOS='android', GOARCH=arch, CGO_ENABLED='1', CC=str(compiler))
    if arch == 'arm': buildenv['GOARM'] = '7'
    subprocess.run([go, 'build', '-overlay='+str(overlay_path), '-tags=linux', '-trimpath', '-buildvcs=false', '-ldflags=-buildid= -X github.com/amnezia-vpn/amneziawg-go/v3/ipc.socketDirectory=/data/data/com.wgfytunnel/cache/amneziawg', '-buildmode=c-shared', '-o', str(dest), '.'], cwd=module, env=buildenv, check=True)
    print('Built', abi, hashlib.sha256(dest.read_bytes()).hexdigest(), flush=True)
    return dest

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(build, abis.items()))

with zipfile.ZipFile(a.base_aar) as z:
    base_classes = z.read('classes.jar')
classes_jar = out/'base-classes.jar'
classes_jar.write_bytes(base_classes)
classes_dir = out/'classes'
classes_dir.mkdir(exist_ok=True)
android_jar = a.sdk.resolve()/'platforms/android-35/android.jar'
classpath = os.pathsep.join(str(x) for x in [classes_jar, android_jar, a.annotations.resolve()])
source = a.android.resolve()/'tunnel/src/main/java/org/amnezia/awg/config/Interface.java'
javac = a.java.resolve()/'bin'/('javac.exe' if os.name == 'nt' else 'javac')
subprocess.run([str(javac), '--release', '17', '-cp', classpath, '-d', str(classes_dir), str(source)], check=True)
test_source = Path(__file__).resolve().parent/'InterfaceMorphTest.java'
test_cp = str(classes_dir)+os.pathsep+classpath
test_dir = out/'java-tests'
test_dir.mkdir(exist_ok=True)
subprocess.run([str(javac), '--release', '17', '-cp', test_cp, '-d', str(test_dir), str(test_source)], check=True)
java = a.java.resolve()/'bin'/('java.exe' if os.name == 'nt' else 'java')
subprocess.run([str(java), '-cp', str(test_dir)+os.pathsep+test_cp, 'InterfaceMorphTest'], check=True)
replacements = {f.relative_to(classes_dir).as_posix(): f.read_bytes() for f in classes_dir.rglob('*.class')}
new_classes = io.BytesIO()
with zipfile.ZipFile(io.BytesIO(base_classes)) as sourcezip, zipfile.ZipFile(new_classes, 'w', zipfile.ZIP_DEFLATED) as destzip:
    for item in sourcezip.infolist():
        if item.filename not in replacements: destzip.writestr(item, sourcezip.read(item))
    for name, data in replacements.items(): destzip.writestr(name, data)
result = out/'hyperwg31.aar'
with zipfile.ZipFile(a.base_aar) as sourcezip, zipfile.ZipFile(result, 'w', zipfile.ZIP_DEFLATED) as destzip:
    for item in sourcezip.infolist():
        if item.filename == 'classes.jar': data = new_classes.getvalue()
        elif item.filename.startswith('jni/') and item.filename.endswith('/libwg-go.so'):
            data = (out/item.filename.split('/')[1]/'libwg-go.so').read_bytes()
        else: data = sourcezip.read(item)
        destzip.writestr(item, data)
metadata = {'core_commit': 'b5928efb6ca19f0153958460c3d141f04abc5c2e', 'android_commit': '5c16489e2cd9ed3a0a7a27c7445bba5238132f86', 'base_aar_sha256': hashlib.sha256(a.base_aar.read_bytes()).hexdigest(), 'aar_sha256': hashlib.sha256(result.read_bytes()).hexdigest(), 'go': subprocess.check_output([go, 'version'], env=env, text=True).strip(), 'boottime': True, 'abis': list(abis)}
(out/'build.json').write_text(json.dumps(metadata, indent=2)+'\n')
print(json.dumps(metadata, indent=2))
