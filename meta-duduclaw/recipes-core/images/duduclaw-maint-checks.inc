# DuDuClaw OS — build-time checks for the maintenance SSH account
# (2026-10-16). Required by duduclaw-image.bb, so every image that installs
# duduclaw-maint runs them: both shipping editions and the development
# images built on duduclaw-image.
#
# Authority: commercial/docs/DESIGN-maintenance-ssh-account-2026-10.md
# (private platform tree) section 3.1 "建置斷言". The recipe that creates the
# account is recipes-duduclaw/duduclaw-maint/duduclaw-maint.bb; these checks
# read the finished rootfs instead of trusting the recipe, so a later change
# anywhere (another recipe, a bbappend, a useradd-staticids table) that
# breaks one of the properties below fails the build.
#
# What fails the build:
#   1. uid 4800 or gid 4800 belongs to anything but duduclaw-maint, or the
#      account's primary group, home, shell or shadow field is not what the
#      design fixed ('*'), or the account is a member of any group;
#   2. 4800 falls inside the host's dynamic system range (login.defs
#      SYS_UID/GID_MIN..MAX, and 101-999 regardless), inside any
#      /etc/subuid or /etc/subgid range (or DUDUCLAW_SUBID_RANGE, which
#      duduclaw-image-compat.inc writes), inside the Android ids Waydroid
#      uses on the host, or inside systemd's reserved ranges;
#   3. the maint-shell path is missing from /etc/shells, or the home is not
#      an empty root:root 0555 directory, or any polkit rules file in the
#      image names duduclaw-maint (owner decision 2026-10-16: the account
#      gets no polkit grant; its two restarts go through the root helper
#      service);
#   4. the readiness marker is installed but the menu binaries are not
#      (until the platform snapshot that carries them lands, a missing
#      shell is only a warning: the account cannot log in either way);
#   5. compared with the previous release's account table
#      (DUDUCLAW_ACCOUNT_BASELINE, set by the shipping image recipes), any
#      user or group changed its id or disappeared, or a new one appeared
#      that DUDUCLAW_ACCOUNT_IDS_ADDED does not list. A changed id after an
#      A/B update leaves the files on /data owned by the wrong account.
#
# Runs as the LAST rootfs post-process step (`:append`, applied after every
# `+=`), so it sees /etc/subuid after duduclaw-image-compat.inc's
# duduclaw_write_subids. A python function for the same reason as
# duduclaw_check_filecaps: do_rootfs runs under pseudo, so os.lstat sees the
# ownership and modes the packages set, not the build user's.

DUDUCLAW_MAINT_USER = "duduclaw-maint"
DUDUCLAW_MAINT_ID = "4800"
DUDUCLAW_MAINT_HOME = "${datadir}/duduclaw-maint"
DUDUCLAW_MAINT_SHELL = "${libexecdir}/duduclaw/maint-shell"
DUDUCLAW_MAINT_TOOLS = "${libexecdir}/duduclaw/maint-shell ${libexecdir}/duduclaw/maint-helper"
DUDUCLAW_MAINT_READY = "${nonarch_libdir}/duduclaw/maint-ssh.ready"

# Inclusive ranges the maintenance id must stay out of.
# Android ids, from AOSP system/core/libcutils/include/private/
# android_filesystem_config.h as summarised in the design (not yet checked
# against the Android image Waydroid downloads): 0 root; 1000-1099 system
# services; 2000-2002 shell/cache/diag; 2900-2999 OEM; 3001-3099 network
# and related groups (the design lists 3001-3012; widened to the whole
# block so newer AIDs such as AID_VIRTUALMACHINE are covered); 5000-5999
# OEM; 6000-7999 system/odm/product/system_ext reserved; 9997-9999
# everybody/misc/nobody; 10000 and up apps, shared gids, isolated
# processes and secondary users.
DUDUCLAW_AOSP_AID_RANGES = "0-0 1000-1099 2000-2002 2900-2999 3001-3099 5000-5999 6000-7999 9997-9999 10000-4294967294"
DUDUCLAW_SYSTEMD_RESERVED_RANGES = "60001-60513 61184-65519 65534-65534 524288-4294967294"
DUDUCLAW_HOST_DYNAMIC_RANGE = "101-999"

# Previous release's account table, one line per account:
#   user <name> <uid> <gid>
#   group <name> <gid>
# Empty means "no baseline" (development images); the shipping image
# recipes set it. Refresh procedure: after a release is published, dump
# /etc/passwd and /etc/group from that release's images and regenerate the
# file (its header says how the current one was made), then empty
# DUDUCLAW_ACCOUNT_IDS_ADDED.
DUDUCLAW_ACCOUNT_BASELINE ?= ""
# Accounts allowed to be new relative to the baseline, as user:<name> or
# group:<name>. Only duduclaw-maint, which has a fixed id and so cannot move
# anyone else.
DUDUCLAW_ACCOUNT_IDS_ADDED ?= "user:duduclaw-maint group:duduclaw-maint"

python duduclaw_check_maint_account () {
    import os
    import stat

    root = d.getVar('IMAGE_ROOTFS')
    sysconf = root + d.getVar('sysconfdir')
    user = d.getVar('DUDUCLAW_MAINT_USER')
    mid = int(d.getVar('DUDUCLAW_MAINT_ID'))
    errors = []

    def fail(msg):
        errors.append(msg)

    def read_table(name):
        path = os.path.join(sysconf, name)
        if not os.path.isfile(path):
            return None
        rows = []
        with open(path) as f:
            for line in f:
                line = line.rstrip('\n')
                if not line or line.startswith('#'):
                    continue
                rows.append(line.split(':'))
        return rows

    def parse_ranges(text):
        out = []
        for item in (text or '').split():
            lo, hi = item.split('-')
            out.append((int(lo), int(hi)))
        return out

    def in_any(value, ranges):
        return [r for r in ranges if r[0] <= value <= r[1]]

    passwd = read_table('passwd')
    group = read_table('group')
    shadow = read_table('shadow')
    if passwd is None or group is None or shadow is None:
        bb.fatal('duduclaw_check_maint_account: /etc/passwd, /etc/group or /etc/shadow is missing from the rootfs')

    # --- 1. the id belongs to duduclaw-maint alone ---------------------------
    users_at = [r[0] for r in passwd if len(r) >= 7 and r[2] == str(mid)]
    groups_at = [r[0] for r in group if len(r) >= 3 and r[2] == str(mid)]
    if users_at != [user]:
        fail('uid %d belongs to %s, expected only %s' % (mid, users_at or 'nobody', user))
    if groups_at != [user]:
        fail('gid %d belongs to %s, expected only %s' % (mid, groups_at or 'nobody', user))

    pw = [r for r in passwd if r[0] == user]
    if len(pw) != 1 or len(pw[0]) != 7:
        fail('%s has %d well-formed passwd entries, expected 1' % (user, len(pw)))
    else:
        _, _, uid, gid, _, home, shell = pw[0]
        if uid != str(mid) or gid != str(mid):
            fail('%s is %s:%s in passwd, expected %d:%d' % (user, uid, gid, mid, mid))
        if home != d.getVar('DUDUCLAW_MAINT_HOME'):
            fail('%s home is %s, expected %s' % (user, home, d.getVar('DUDUCLAW_MAINT_HOME')))
        if shell != d.getVar('DUDUCLAW_MAINT_SHELL'):
            fail('%s shell is %s, expected %s' % (user, shell, d.getVar('DUDUCLAW_MAINT_SHELL')))

    member_of = [r[0] for r in group if len(r) >= 4 and user in r[3].split(',')]
    if member_of:
        fail('%s must have no supplementary groups, but is a member of %s' % (user, ' '.join(member_of)))

    sh = [r for r in shadow if r[0] == user]
    if len(sh) != 1 or len(sh[0]) < 2 or sh[0][1] != '*':
        fail('%s shadow password field must be exactly "*"' % user)

    # --- 2. the id stays out of every range it could collide with ------------
    host_dyn = parse_ranges(d.getVar('DUDUCLAW_HOST_DYNAMIC_RANGE'))
    defs = {}
    defs_path = os.path.join(sysconf, 'login.defs')
    if os.path.isfile(defs_path):
        with open(defs_path) as f:
            for line in f:
                parts = line.split()
                if len(parts) == 2 and parts[0] in ('SYS_UID_MIN', 'SYS_UID_MAX', 'SYS_GID_MIN', 'SYS_GID_MAX'):
                    defs[parts[0]] = int(parts[1])
    for kind in ('UID', 'GID'):
        lo, hi = defs.get('SYS_%s_MIN' % kind), defs.get('SYS_%s_MAX' % kind)
        if lo is not None and hi is not None:
            host_dyn.append((lo, hi))
    if in_any(mid, host_dyn):
        fail('%d is inside the host dynamic system range %s' % (mid, in_any(mid, host_dyn)))

    subid = []
    for name in ('subuid', 'subgid'):
        for r in read_table(name) or []:
            if len(r) == 3 and r[1].isdigit() and r[2].isdigit():
                start, count = int(r[1]), int(r[2])
                if count > 0:
                    subid.append((start, start + count - 1))
            else:
                fail('/etc/%s has a malformed line: %s' % (name, ':'.join(r)))
    cfg = (d.getVar('DUDUCLAW_SUBID_RANGE') or '').strip()
    if cfg:
        start, count = (int(x) for x in cfg.split(':'))
        subid.append((start, start + count - 1))
    if in_any(mid, subid):
        fail('%d is inside a subordinate id range %s' % (mid, in_any(mid, subid)))

    aosp = parse_ranges(d.getVar('DUDUCLAW_AOSP_AID_RANGES'))
    if in_any(mid, aosp):
        fail('%d is inside the Android id range %s (Waydroid runs Android ids as host ids)' % (mid, in_any(mid, aosp)))
    sysd = parse_ranges(d.getVar('DUDUCLAW_SYSTEMD_RESERVED_RANGES'))
    if in_any(mid, sysd):
        fail('%d is inside a systemd reserved range %s' % (mid, in_any(mid, sysd)))

    # --- 3. shell listed, home empty and read-only -----------------------------
    shells_path = os.path.join(sysconf, 'shells')
    shells = []
    if os.path.isfile(shells_path):
        with open(shells_path) as f:
            shells = [l.strip() for l in f]
    if d.getVar('DUDUCLAW_MAINT_SHELL') not in shells:
        fail('%s is not listed in /etc/shells (dropbear refuses the login otherwise)' % d.getVar('DUDUCLAW_MAINT_SHELL'))

    home_path = root + d.getVar('DUDUCLAW_MAINT_HOME')
    try:
        st = os.lstat(home_path)
        if not stat.S_ISDIR(st.st_mode):
            fail('%s is not a directory' % d.getVar('DUDUCLAW_MAINT_HOME'))
        else:
            if stat.S_IMODE(st.st_mode) != 0o555 or st.st_uid != 0 or st.st_gid != 0:
                fail('%s must be root:root 0555, is %d:%d %o' % (d.getVar('DUDUCLAW_MAINT_HOME'), st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)))
            if os.listdir(home_path):
                fail('%s must be empty' % d.getVar('DUDUCLAW_MAINT_HOME'))
    except FileNotFoundError:
        fail('%s does not exist' % d.getVar('DUDUCLAW_MAINT_HOME'))

    for rules_dir in (d.getVar('datadir') + '/polkit-1/rules.d', d.getVar('sysconfdir') + '/polkit-1/rules.d'):
        full = root + rules_dir
        if not os.path.isdir(full):
            continue
        for name in sorted(os.listdir(full)):
            path = os.path.join(full, name)
            hit = 'duduclaw-maint' in name
            if not hit and os.path.isfile(path):
                with open(path, errors='replace') as f:
                    hit = user in f.read()
            if hit:
                fail('%s/%s grants or mentions %s; the account must have no polkit rule' % (rules_dir, name, user))

    # --- 4. readiness marker implies the menu binaries -----------------------
    missing_tools = [t for t in d.getVar('DUDUCLAW_MAINT_TOOLS').split()
                     if not (os.path.isfile(root + t) and os.access(root + t, os.X_OK))]
    if os.path.lexists(root + d.getVar('DUDUCLAW_MAINT_READY')):
        if missing_tools:
            fail('%s is installed but %s are missing or not executable' % (d.getVar('DUDUCLAW_MAINT_READY'), ' '.join(missing_tools)))
    elif missing_tools:
        bb.warn('duduclaw_check_maint_account: %s not in the image yet (they come with the platform snapshot that adds duduclaw-maint-tools); %s cannot log in until then' % (' '.join(missing_tools), user))

    # --- 5. no account moved since the previous release ----------------------
    baseline = (d.getVar('DUDUCLAW_ACCOUNT_BASELINE') or '').strip()
    if not baseline:
        bb.warn('duduclaw_check_maint_account: no DUDUCLAW_ACCOUNT_BASELINE for %s, skipping the previous-release comparison (development image; the shipping images set one)' % d.getVar('PN'))
    else:
        if not os.path.isfile(baseline):
            bb.fatal('duduclaw_check_maint_account: DUDUCLAW_ACCOUNT_BASELINE %s does not exist' % baseline)
        want = {}
        with open(baseline) as f:
            for n, line in enumerate(f, 1):
                parts = line.split()
                if not parts or parts[0].startswith('#'):
                    continue
                if parts[0] == 'user' and len(parts) == 4:
                    want[('user', parts[1])] = (parts[2], parts[3])
                elif parts[0] == 'group' and len(parts) == 3:
                    want[('group', parts[1])] = (parts[2],)
                else:
                    bb.fatal('duduclaw_check_maint_account: %s line %d is malformed' % (baseline, n))
        have = {}
        for r in passwd:
            if len(r) >= 4:
                have[('user', r[0])] = (r[2], r[3])
        for r in group:
            if len(r) >= 3:
                have[('group', r[0])] = (r[2],)
        added_ok = set((d.getVar('DUDUCLAW_ACCOUNT_IDS_ADDED') or '').split())
        for key, ids in sorted(want.items()):
            if key not in have:
                fail('%s %s (%s) from the previous release is gone' % (key[0], key[1], ':'.join(ids)))
            elif have[key] != ids:
                fail('%s %s changed from %s to %s since the previous release' % (key[0], key[1], ':'.join(ids), ':'.join(have[key])))
        for key in sorted(set(have) - set(want)):
            if '%s:%s' % key not in added_ok:
                fail('%s %s (%s) is new since the previous release and not in DUDUCLAW_ACCOUNT_IDS_ADDED' % (key[0], key[1], ':'.join(have[key])))

    if errors:
        bb.fatal('duduclaw_check_maint_account:\n  ' + '\n  '.join(errors))
}
ROOTFS_POSTPROCESS_COMMAND:append = " duduclaw_check_maint_account;"
do_rootfs[vardeps] += "DUDUCLAW_ACCOUNT_BASELINE DUDUCLAW_ACCOUNT_IDS_ADDED DUDUCLAW_AOSP_AID_RANGES DUDUCLAW_SYSTEMD_RESERVED_RANGES DUDUCLAW_HOST_DYNAMIC_RANGE DUDUCLAW_MAINT_ID"
do_rootfs[file-checksums] += "${@'%s:True' % d.getVar('DUDUCLAW_ACCOUNT_BASELINE') if (d.getVar('DUDUCLAW_ACCOUNT_BASELINE') or '').strip() else ''}"

# --- dropbear for the maintenance account (2026-10-16) ----------------------
# duduclaw-sysd refuses to open a window unless the ExecStart systemd
# actually uses for dropbear@.service equals its own constant, token by
# token; this check catches the same drift at build time. Change the
# drop-in (recipes-core/dropbear/files/60-duduclaw-maint-dropbear.conf),
# this constant and sysd's constant together.
DUDUCLAW_MAINT_DROPBEAR_ARGV = "/usr/sbin/dropbear -i -r /data/system/dropbear/dropbear_ed25519_host_key -w -s -j -k -m -T 3 -I 1800 -G duduclaw-maint -D /run/duduclaw-maint-ssh -c /usr/libexec/duduclaw/maint-shell"
DUDUCLAW_MAINT_CLOSE = "${libexecdir}/duduclaw/maint-ssh-close"
DUDUCLAW_MAINT_DROPBEAR_INACCESSIBLE = "-/data/duduclaw -/data/duduclaw-kiosk -/data/system/iwd -/data/system/containers"

# What fails the build:
#   - dropbear@.service.d/60-duduclaw-maint.conf is missing, its ExecStart
#     is not exactly a reset plus "-" + DUDUCLAW_MAINT_DROPBEAR_ARGV, or it
#     lacks BindsTo=duduclaw-sysd.service, IPAddressDeny=any, the
#     EnvironmentFile= reset, RequiresMountsFor=/data, or any of its sandbox
#     settings (NoNewPrivileges, ProtectSystem=strict, ProtectProc=invisible,
#     ProtectHome, PrivateTmp, InaccessiblePaths as designed);
#   - the ExecStart binary does not resolve (through oe-core's
#     dropbear -> dropbearmulti link) to a root-owned regular executable
#     under sbindir that only root can write;
#   - any other drop-in for dropbear@.service sets ExecStart= (it would
#     replace or add to ours);
#   - dropbear.socket.d/60-duduclaw-maint.conf lacks BindsTo=duduclaw-
#     sysd.service;
#   - dropbearkey.service.d/60-duduclaw-maint.conf does not generate into
#     /data/system/dropbear;
#   - a host key is baked into the image (/etc/dropbear or
#     /data/system/dropbear not empty): every device would share it;
#   - the fallback close script is missing or not executable, or there is
#     no flock command for its audit lock.
python duduclaw_check_maint_dropbear () {
    import os
    import stat

    root = d.getVar('IMAGE_ROOTFS')
    unitdir = root + d.getVar('systemd_system_unitdir')
    errors = []

    def parse(path):
        """Return {section: [(key, value), ...]} for a systemd unit file."""
        out, section = {}, None
        with open(path) as f:
            for raw in f:
                line = raw.strip()
                if not line or line[0] in '#;':
                    continue
                if line.startswith('[') and line.endswith(']'):
                    section = line[1:-1]
                    out.setdefault(section, [])
                    continue
                if '=' in line and section:
                    k, v = line.split('=', 1)
                    out[section].append((k.strip(), v.strip()))
        return out

    def values(unit, section, key):
        return [v for k, v in unit.get(section, []) if k == key]

    service_dir = os.path.join(unitdir, 'dropbear@.service.d')
    ours = os.path.join(service_dir, '60-duduclaw-maint.conf')
    if not os.path.isfile(ours):
        errors.append('dropbear@.service.d/60-duduclaw-maint.conf is missing')
    else:
        u = parse(ours)
        execs = values(u, 'Service', 'ExecStart')
        want = '-' + ' '.join(d.getVar('DUDUCLAW_MAINT_DROPBEAR_ARGV').split())
        if len(execs) != 2 or execs[0] != '' or ' '.join(execs[1].split()) != want:
            errors.append('dropbear@ ExecStart is %r, expected ["", %r]' % (execs, want))
        if 'duduclaw-sysd.service' not in ' '.join(values(u, 'Unit', 'BindsTo')).split():
            errors.append('dropbear@ drop-in lacks BindsTo=duduclaw-sysd.service')
        if values(u, 'Service', 'IPAddressDeny') != ['any']:
            errors.append('dropbear@ drop-in must set IPAddressDeny=any')
        if '' not in values(u, 'Service', 'EnvironmentFile'):
            errors.append('dropbear@ drop-in must reset EnvironmentFile=')
        # Session sandbox: each of these must stay exactly as designed.
        for key, want_v in (('NoNewPrivileges', 'yes'), ('ProtectSystem', 'strict'),
                            ('ProtectProc', 'invisible'), ('ProtectHome', 'yes'),
                            ('PrivateTmp', 'yes')):
            if values(u, 'Service', key) != [want_v]:
                errors.append('dropbear@ drop-in must set %s=%s (has %s)' % (key, want_v, values(u, 'Service', key)))
        inacc = ' '.join(values(u, 'Service', 'InaccessiblePaths')).split()
        if sorted(inacc) != sorted(d.getVar('DUDUCLAW_MAINT_DROPBEAR_INACCESSIBLE').split()):
            errors.append('dropbear@ drop-in InaccessiblePaths is %s, expected %s' % (inacc, d.getVar('DUDUCLAW_MAINT_DROPBEAR_INACCESSIBLE').split()))
        if '/data' not in ' '.join(values(u, 'Unit', 'RequiresMountsFor')).split():
            errors.append('dropbear@ drop-in must have RequiresMountsFor=/data')
    for name in sorted(os.listdir(service_dir)) if os.path.isdir(service_dir) else []:
        full = os.path.join(service_dir, name)
        if name != '60-duduclaw-maint.conf' and os.path.isfile(full) and values(parse(full), 'Service', 'ExecStart'):
            errors.append('dropbear@.service.d/%s sets ExecStart=, which would change the maintenance dropbear command' % name)

    # The ExecStart binary sysd compares by path. oe-core installs dropbear
    # as a multi-call binary (/usr/sbin/dropbear -> dropbearmulti); sysd
    # canonicalizes at runtime, and here the path must resolve, inside the
    # rootfs, to a root-owned regular executable under sbindir that only
    # root can write. The resolved path is printed for the build log.
    def resolve_in_root(path):
        cur, seen = path, 0
        while True:
            parts = cur.strip('/').split('/')
            built = ''
            for i, part in enumerate(parts):
                cand = built + '/' + part
                full = root + cand
                if os.path.islink(full):
                    seen += 1
                    if seen > 40:
                        return None
                    target = os.readlink(full)
                    nxt = target if target.startswith('/') else os.path.normpath(os.path.dirname(cand) + '/' + target)
                    cur = nxt + ('/' + '/'.join(parts[i + 1:]) if i + 1 < len(parts) else '')
                    break
                built = cand
            else:
                return os.path.normpath(built)
    exe = d.getVar('DUDUCLAW_MAINT_DROPBEAR_ARGV').split()[0]
    real = resolve_in_root(exe)
    sbindir = d.getVar('sbindir')
    if real is None or not os.path.lexists(root + real):
        errors.append('%s does not resolve to a file in the image' % exe)
    else:
        st = os.lstat(root + real)
        if not (real.startswith(sbindir + '/') and stat.S_ISREG(st.st_mode) and st.st_uid == 0
                and st.st_mode & 0o111 and not st.st_mode & 0o022):
            errors.append('%s resolves to %s, which must be a root-owned regular executable under %s, not group/world-writable' % (exe, real, sbindir))
        else:
            bb.note('duduclaw_check_maint_dropbear: %s resolves to %s' % (exe, real))

    sock = os.path.join(unitdir, 'dropbear.socket.d', '60-duduclaw-maint.conf')
    if not os.path.isfile(sock):
        errors.append('dropbear.socket.d/60-duduclaw-maint.conf is missing')
    elif 'duduclaw-sysd.service' not in ' '.join(values(parse(sock), 'Unit', 'BindsTo')).split():
        errors.append('dropbear.socket drop-in lacks BindsTo=duduclaw-sysd.service')

    key = os.path.join(unitdir, 'dropbearkey.service.d', '60-duduclaw-maint.conf')
    if not os.path.isfile(key):
        errors.append('dropbearkey.service.d/60-duduclaw-maint.conf is missing')
    else:
        execs = values(parse(key), 'Service', 'ExecStart')
        if not execs or execs[0] != '' or not any('/data/system/dropbear/dropbear_ed25519_host_key' in e for e in execs[1:]):
            errors.append('dropbearkey drop-in must reset ExecStart= and generate /data/system/dropbear/dropbear_ed25519_host_key')

    for keydir in (d.getVar('sysconfdir') + '/dropbear', '/data/system/dropbear'):
        full = root + keydir
        if os.path.isdir(full) and os.listdir(full):
            errors.append('%s in the image is not empty (%s): a baked-in host key would be shared by every device' % (keydir, ' '.join(sorted(os.listdir(full)))))

    close = root + d.getVar('DUDUCLAW_MAINT_CLOSE')
    if not (os.path.isfile(close) and os.access(close, os.X_OK)):
        errors.append('%s is missing or not executable' % d.getVar('DUDUCLAW_MAINT_CLOSE'))
    # The close script takes the audit lock with flock(1) (busybox's applet
    # or util-linux's); without it no fallback close record can be written.
    if not any(os.path.lexists(root + d.getVar(v) + '/flock') for v in ('base_bindir', 'bindir', 'base_sbindir', 'sbindir')):
        errors.append('no flock command in the image (maint-ssh-close needs it for the audit lock)')

    if errors:
        bb.fatal('duduclaw_check_maint_dropbear:\n  ' + '\n  '.join(errors))
}
ROOTFS_POSTPROCESS_COMMAND:append = " duduclaw_check_maint_dropbear;"
do_rootfs[vardeps] += "DUDUCLAW_MAINT_DROPBEAR_ARGV DUDUCLAW_MAINT_DROPBEAR_INACCESSIBLE"
