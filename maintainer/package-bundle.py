"""Package the collector's CMake dependencies as a relocatable teaching SDK."""
import hashlib
import json
import pathlib
import platform
import shlex
import shutil
import subprocess
import sys
import tarfile

work = pathlib.Path(sys.argv[1]).resolve()
build = work / 'build'
reply = build / '.cmake/api/v1/reply'
index = json.loads(sorted(reply.glob('index-*.json'))[-1].read_text())
model = json.loads((reply / index['reply']['codemodel-v2']['jsonFile']).read_text())
ref = next(t for t in model['configurations'][0]['targets'] if t['name'] == 'workshop-agent')
target = json.loads((reply / ref['jsonFile']).read_text())
sdk = work / 'package/falco-libs'
if sdk.exists():
    shutil.rmtree(sdk)
(sdk / 'include').mkdir(parents=True)
(sdk / 'lib').mkdir()
includes = []
# Preserve directory structure and ordering, including generated headers.
for item in target['compileGroups'][0]['includes']:
    source = pathlib.Path(item['path'])
    dest = sdk / 'include' / str(len(includes))
    dest.mkdir()
    for header in source.rglob('*'):
        if header.is_file() and header.suffix in ('.h', '.hpp', '.hh', '.hxx', '.inc', '.inl', '.ipp'):
            output = dest / header.relative_to(source)
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(header, output)
    includes.append('${CMAKE_CURRENT_LIST_DIR}/' + str(dest.relative_to(sdk)))
links = []
for fragment in target['link']['commandFragments']:
    if fragment['role'] != 'libraries':
        continue
    for arg in shlex.split(fragment['fragment']):
        if arg.endswith('.a'):
            source = pathlib.Path(arg)
            if not source.is_absolute():
                source = build / target['paths']['build'] / source
            dest = sdk / 'lib' / source.name
            if dest.exists() and dest.read_bytes() != source.read_bytes():
                raise RuntimeError(f'Conflicting library names: {source}')
            shutil.copy2(source, dest)
            links.append('${CMAKE_CURRENT_LIST_DIR}/lib/' + dest.name)
        elif arg.startswith('-l'):
            links.append(arg)
        else:
            raise RuntimeError(f'Unpackaged link dependency: {arg}')
for archive in (sdk / 'lib').glob('*.a'):
    subprocess.run(['strip', '--strip-debug', str(archive)], check=True)
defines = [d['define'].replace('"', '\\"') for d in target['compileGroups'][0].get('defines', [])]
config = ['add_library(sinsp INTERFACE IMPORTED)']
for prop, values in [('INTERFACE_INCLUDE_DIRECTORIES', includes), ('INTERFACE_LINK_LIBRARIES', links), ('INTERFACE_COMPILE_DEFINITIONS', defines)]:
    config.append(f'set_property(TARGET sinsp PROPERTY {prop}')
    config.extend(f'    "{value}"' for value in values)
    config.append(')')
config.append('set_property(TARGET sinsp PROPERTY INTERFACE_COMPILE_OPTIONS "-fno-strict-aliasing")')
(sdk / 'FalcoWorkshopConfig.cmake').write_text('\n'.join(config) + '\n')
commit = subprocess.check_output(['git', '-C', str(work / 'libs'), 'rev-parse', 'HEAD'], text=True).strip()
(sdk / 'manifest.json').write_text(json.dumps({'ubuntu': '24.04', 'architecture': platform.machine(), 'falco_commit': commit}, indent=2) + '\n')
# Ship upstream license/notice files with the bundled dependencies.
for base in [work / 'libs', build]:
    for source in base.rglob('*'):
        if source.is_file() and source.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE', 'COPYRIGHT')):
            dest = sdk / 'licenses' / base.name / source.relative_to(base)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
dist = work.parent.parent / '.artifacts/dist'
dist.mkdir(parents=True, exist_ok=True)
archive = dist / f'falco-libs-ubuntu24.04-{platform.machine()}.tar.gz'
with tarfile.open(archive, 'w:gz') as out:
    out.add(sdk, arcname='falco-libs')
archive.with_suffix(archive.suffix + '.sha256').write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
print(f'Packaged {archive}: {archive.stat().st_size // 1024 // 1024} MiB, Falco {commit}')
