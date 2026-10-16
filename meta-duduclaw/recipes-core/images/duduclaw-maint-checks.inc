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

# --- Firewall pieces for the maintenance account (2026-10-16) ---------------
# duduclaw-sysd checks the live ruleset before it opens a window (the jump,
# the uid-4800 reject rule, both source sets with exactly these elements);
# this checks the files that produce it. Keep these constants, nftables.conf
# and sysd's constants equal.
DUDUCLAW_MAINT_SRC4 = "10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"
DUDUCLAW_MAINT_SRC6 = "fc00::/7 fe80::/10"
DUDUCLAW_MAINT_NFT_RULE = "/usr/sbin/nft add rule inet filter duduclaw_maint_egress meta skuid ${DUDUCLAW_MAINT_ID} counter reject"

# What fails the build:
#   - nftables.service.d/60-duduclaw-maint.conf is missing, or its
#     ExecStartPost=/ExecReload= are not exactly "-" + DUDUCLAW_MAINT_NFT_RULE
#     (numeric uid, failure tolerated);
#   - /etc/nftables.conf (when the image has the firewall) names an account
#     or group in a skuid/skgid match (nft resolves names at load time and an
#     unknown one fails the whole ruleset), lacks the empty
#     duduclaw_maint_egress chain, does not have the `oif "lo"` jump to it as
#     the first rule of the output chain (before the podman jump), has source
#     sets whose elements differ from the constants above, or lacks the
#     three maintenance-port rules (v4 accept, v6 accept, reset).
python duduclaw_check_maint_nft () {
    import os
    import re

    root = d.getVar('IMAGE_ROOTFS')
    errors = []

    dropin = root + d.getVar('systemd_system_unitdir') + '/nftables.service.d/60-duduclaw-maint.conf'
    want = '-' + d.getVar('DUDUCLAW_MAINT_NFT_RULE')
    if not os.path.isfile(dropin):
        errors.append('nftables.service.d/60-duduclaw-maint.conf is missing')
    else:
        found = {'ExecStartPost': [], 'ExecReload': []}
        with open(dropin) as f:
            for line in f:
                line = line.strip()
                for key in found:
                    if line.startswith(key + '='):
                        found[key].append(' '.join(line.split('=', 1)[1].split()))
        for key, vals in found.items():
            if vals != [want]:
                errors.append('nftables drop-in %s is %r, expected [%r]' % (key, vals, want))

    conf_path = root + d.getVar('sysconfdir') + '/nftables.conf'
    if os.path.isfile(conf_path):
        with open(conf_path) as f:
            conf = '\n'.join(l.split('#', 1)[0] for l in f)
        bad = re.findall(r'\bsk(?:uid|gid)\s+(?:(?:==|!=)\s*)?([^\s;{}]+)', conf)
        named = [b for b in bad if not b.isdigit()]
        if named:
            errors.append('/etc/nftables.conf matches on account names %s; use numbers, and keep the maintenance rule out of this file' % named)
        if not re.search(r'chain\s+duduclaw_maint_egress\s*\{\s*\}', conf):
            errors.append('/etc/nftables.conf lacks the empty duduclaw_maint_egress chain')
        out = re.search(r'chain\s+output\s*\{(.*?)\n\s*\}', conf, re.S)
        rules = [l.strip() for l in out.group(1).split('\n') if l.strip() and not l.strip().startswith('type ')] if out else []
        if not rules or not re.fullmatch(r'oif\s+"lo"\s+jump\s+duduclaw_maint_egress', rules[0]):
            errors.append('/etc/nftables.conf: the first rule of the output chain must be `oif "lo" jump duduclaw_maint_egress` (found %r)' % (rules[0] if rules else None))
        for name, var in (('maintenance_src4', 'DUDUCLAW_MAINT_SRC4'), ('maintenance_src6', 'DUDUCLAW_MAINT_SRC6')):
            m = re.search(r'set\s+' + name + r'\s*\{(.*?)\}\s*\n', conf, re.S)
            elems = None
            if m:
                e = re.search(r'elements\s*=\s*\{([^}]*)\}', m.group(1) + '}')
                if e:
                    elems = sorted(x.strip() for x in e.group(1).split(',') if x.strip())
            if elems != sorted(d.getVar(var).split()):
                errors.append('/etc/nftables.conf set %s has %s, expected %s' % (name, elems, sorted(d.getVar(var).split())))
        for pat, what in (
                (r'ip\s+saddr\s+@maintenance_src4\s+tcp\s+dport\s+@maintenance_tcp_ports\s+accept', 'IPv4 LAN/VPN accept rule'),
                (r'ip6\s+saddr\s+@maintenance_src6\s+tcp\s+dport\s+@maintenance_tcp_ports\s+accept', 'IPv6 LAN accept rule'),
                (r'tcp\s+dport\s+@maintenance_tcp_ports\s+reject\s+with\s+tcp\s+reset', 'reset rule for other sources')):
            if not re.search(pat, conf):
                errors.append('/etc/nftables.conf lacks the %s' % what)
        if re.search(r'^\s*tcp\s+dport\s+@maintenance_tcp_ports\s+accept', conf, re.M):
            errors.append('/etc/nftables.conf still accepts maintenance_tcp_ports from every source')

    if errors:
        bb.fatal('duduclaw_check_maint_nft:\n  ' + '\n  '.join(errors))
}
ROOTFS_POSTPROCESS_COMMAND:append = " duduclaw_check_maint_nft;"
do_rootfs[vardeps] += "DUDUCLAW_MAINT_SRC4 DUDUCLAW_MAINT_SRC6 DUDUCLAW_MAINT_NFT_RULE"

# --- Root helper units for the maintenance menu (2026-10-16) ---------------
# The menu's only root entry point (logs and the two restarts; no polkit). What fails the build:
# the socket or the per-connection service is missing; the socket is not
# exactly root:duduclaw-maint 0660 with Accept=yes and MaxConnections=4 on
# /run/duduclaw-maint-helper.sock; the service lost any of its required
# settings (root, socket stdin/stdout, NoNewPrivileges, ProtectSystem=strict,
# ProtectProc=invisible, PrivateNetwork, IPAddressDeny=any,
# RuntimeMaxSec=3600, the preserved 0700 RuntimeDirectory the helper keeps
# its restart rate limit in, the empty capability bounding set, AF_UNIX
# only, @system-service, the kernel/cgroup/device/home/tmp/namespace/
# personality/W^X protections); it is placed in system-dropbear.slice; or
# the socket is not enabled.
DUDUCLAW_MAINT_HELPER_SOCKET_SETTINGS = "ListenStream=/run/duduclaw-maint-helper.sock SocketUser=root SocketGroup=duduclaw-maint SocketMode=0660 Accept=yes MaxConnections=4"
DUDUCLAW_MAINT_HELPER_SERVICE_SETTINGS = "User=root ExecStart=/usr/libexec/duduclaw/maint-helper StandardInput=socket StandardOutput=socket NoNewPrivileges=yes ProtectSystem=strict ProtectProc=invisible PrivateNetwork=yes IPAddressDeny=any RuntimeMaxSec=3600 RuntimeDirectory=duduclaw-maint-helper RuntimeDirectoryMode=0700 RuntimeDirectoryPreserve=yes CapabilityBoundingSet= AmbientCapabilities= RestrictAddressFamilies=AF_UNIX SystemCallFilter=@system-service SystemCallArchitectures=native ProtectKernelTunables=yes ProtectKernelModules=yes ProtectKernelLogs=yes ProtectControlGroups=yes ProtectClock=yes ProtectHostname=yes PrivateDevices=yes ProtectHome=yes PrivateTmp=yes RestrictNamespaces=yes RestrictRealtime=yes RestrictSUIDSGID=yes LockPersonality=yes MemoryDenyWriteExecute=yes"

python duduclaw_check_maint_helper () {
    import os

    root = d.getVar('IMAGE_ROOTFS')
    unitdir = root + d.getVar('systemd_system_unitdir')
    errors = []

    def settings(path):
        out = {}
        with open(path) as f:
            for raw in f:
                line = raw.strip()
                if line and line[0] not in '#;[' and '=' in line:
                    k, v = line.split('=', 1)
                    out.setdefault(k.strip(), []).append(v.strip())
        return out

    for name, var in (('duduclaw-maint-helper.socket', 'DUDUCLAW_MAINT_HELPER_SOCKET_SETTINGS'),
                      ('duduclaw-maint-helper@.service', 'DUDUCLAW_MAINT_HELPER_SERVICE_SETTINGS')):
        path = os.path.join(unitdir, name)
        if not os.path.isfile(path):
            errors.append('%s is missing' % name)
            continue
        have = settings(path)
        for item in d.getVar(var).split():
            k, v = item.split('=', 1)
            if have.get(k) != [v]:
                errors.append('%s: %s is %s, expected [%r]' % (name, k, have.get(k), v))

    svc = os.path.join(unitdir, 'duduclaw-maint-helper@.service')
    if os.path.isfile(svc) and any(v.startswith('system-dropbear') for v in settings(svc).get('Slice', [])):
        errors.append('duduclaw-maint-helper@.service must not run in system-dropbear.slice (a window close kills that slice)')
    # The two units the helper restarts (constants in the platform binary).
    for unit in ('duduclaw-gateway.service', 'duduclaw-llama-server.service'):
        if not os.path.isfile(os.path.join(unitdir, unit)):
            bb.note('duduclaw_check_maint_helper: %s is not in this image; the helper\'s restart of it will fail' % unit)

    wants = root + d.getVar('sysconfdir') + '/systemd/system/sockets.target.wants/duduclaw-maint-helper.socket'
    if not os.path.lexists(wants):
        errors.append('duduclaw-maint-helper.socket is not enabled (no sockets.target.wants link)')

    if errors:
        bb.fatal('duduclaw_check_maint_helper:\n  ' + '\n  '.join(errors))
}
ROOTFS_POSTPROCESS_COMMAND:append = " duduclaw_check_maint_helper;"
do_rootfs[vardeps] += "DUDUCLAW_MAINT_HELPER_SOCKET_SETTINGS DUDUCLAW_MAINT_HELPER_SERVICE_SETTINGS"
