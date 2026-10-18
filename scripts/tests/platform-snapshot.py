#!/usr/bin/env python3
"""Validate the generated platform snapshots without compiling or BitBake.

Run with --platform-root pointing at the exact source checkout. This checks
source equality, manifest closure, dependency pins, and crate-fetch checksums;
it does not prove that a target binary compiles or an OS image boots.
"""
import argparse
import pathlib
import re
import subprocess
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[2]
RECIPES = ROOT / 'meta-duduclaw/recipes-duduclaw'

def toml(path):
    return tomllib.loads(path.read_text())

def registry(lock):
    return {(p['name'], p['version']): p for p in lock['package'] if 'crates.io' in p.get('source', '')}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform-root', type=pathlib.Path, required=True)
    args = parser.parse_args()
    source = args.platform_root.resolve()
    source_packages = toml(source / 'Cargo.lock')['package']
    source_lock = registry({'package': source_packages})
    source_revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    inc = (ROOT / 'meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc').read_text()
    assert f'DUDUCLAW_PLATFORM_SRCREV = "{source_revision}"' in inc, 'platform source revision mismatch'
    cli = RECIPES / 'duduclaw-cli/files/duduclaw-cli-src'
    workspace = toml(cli / 'Cargo.toml')['workspace']
    members = {cli / member for member in workspace['members']}
    seen = set()
    pending = [cli / 'crates/duduclaw-cli', cli / 'crates/duduclaw-maint-tools']
    while pending:
        crate = pending.pop().resolve()
        if crate in seen: continue
        seen.add(crate)
        manifest = toml(crate / 'Cargo.toml')
        assert (crate / 'Cargo.toml').read_bytes() == (source / 'crates' / crate.name / 'Cargo.toml').read_bytes(), crate
        for table in [manifest, *manifest.get('target', {}).values()]:
            for kind in ('dependencies', 'dev-dependencies', 'build-dependencies'):
                for name, spec in table.get(kind, {}).items():
                    if not isinstance(spec, dict): continue
                    base = crate
                    if spec.get('workspace'):
                        spec = workspace['dependencies'].get(name, {}); base = cli
                    if isinstance(spec, dict) and 'path' in spec:
                        pending.append(base / spec['path'])
    assert seen == {p.resolve() for p in members}, 'snapshot members do not equal path closure'
    count = 0
    for crate in sorted(members):
        for path in crate.rglob('*'):
            if not path.is_file(): continue
            relative = path.relative_to(crate)
            assert path.read_bytes() == (source / 'crates' / crate.name / relative).read_bytes(), path
            count += 1
    print(f'ok: {len(members)} workspace members, {count} crate files match the selected platform source')
    for name in ('duduclaw-cli', 'duduclaw-sysd'):
        recipe = RECIPES / name
        lock_packages = toml(recipe / 'files' / (name + '-src') / 'Cargo.lock')['package']
        packages = registry({'package': lock_packages})
        fetches = (recipe / (name + '-crates.inc')).read_text()
        fetched = set(re.findall(r'crate://crates.io/([^/\s]+)/([^\s\\]+)', fetches))
        assert set(packages) <= fetched, f'{name}: missing registry fetches {set(packages) - fetched}'
        for key, package in packages.items():
            assert key in source_lock and source_lock[key]['checksum'] == package['checksum'], (name, key, 'pin drift')
            checksum = re.search(r'SRC_URI\[' + re.escape('-'.join(key)) + r'\.sha256sum\]\s*=\s*"([a-f0-9]+)"', fetches)
            assert checksum and checksum.group(1) == package['checksum'], (name, key, 'fetch checksum mismatch')
        for package in lock_packages:
            git_source = package.get('source', '')
            if not git_source.startswith('git+'):
                continue
            assert any(p['name'] == package['name'] and p['version'] == package['version']
                       and p.get('source') == git_source for p in source_packages), (name, 'git pin drift')
            recipes = list(recipe.glob(name + '_*.bb'))
            assert len(recipes) == 1, name
            revision = git_source.rsplit('#', 1)[-1]
            assert re.search(r'SRCREV_' + re.escape(package['name']) + r'\s*=\s*"' + re.escape(revision) + '"',
                             recipes[0].read_text()), (name, 'git SRCREV missing or stale')
        print(f'ok: {name}, {len(packages)} registry pins match source and fetch checksums; git pins match recipes')
    sysd = RECIPES / 'duduclaw-sysd/files/duduclaw-sysd-src'
    for path in (sysd / 'src').rglob('*'):
        if path.is_file():
            assert path.read_bytes() == (source / 'crates/duduclaw-sysd' / path.relative_to(sysd)).read_bytes(), path
    print('ok: standalone sysd sources match platform; rollback floor is independently owned')

if __name__ == '__main__': main()
