//! Group-shared access to this compositor's IPC endpoints (rootless gateway,
//! 2026-10-15).
//!
//! The compositor runs as `duduclaw-kiosk`. Until the gateway de-rooted, its
//! two sockets (`shell_control`, `codrive`) and the codrive bearer token were
//! owner-only (0600) and the gateway reached them as root. The gateway now
//! runs as uid 1000 (`duduclaw`), so owner-only would lock it out. Making
//! them world-accessible is not an option either: `duduclaw-flatpak-verify`
//! (and any Flatpak app it runs) is in the `duduclaw-kiosk` group to reach
//! the Wayland socket in the same directory.
//!
//! So both sockets go to group [`IPC_GROUP`] with mode 0660 and the token
//! file with 0640. The OS creates that group with exactly two members, the
//! kiosk user and the gateway account (`duduclaw-cli`'s useradd block). The
//! authentication on top does not change: `shell_control` still checks the
//! peer uid with `SO_PEERCRED` (the gateway's uid is trusted as the agent
//! only when `DUDUCLAW_SHELL_CONTROL_AGENT_UID` names it), and `codrive` still
//! requires the bearer token.
//!
//! Fail-closed: if the group does not exist (a development machine, an image
//! without the OS layer) or the chown is refused (this process is not a
//! member), the endpoint stays owner-only, exactly the pre-2026-10-15
//! behaviour. The caller logs which case applied.
//!
//! The group is looked up by reading `/etc/group` directly rather than through
//! NSS (`getgrnam_r`): DuDuClaw OS uses files-only NSS, and a std-only module
//! keeps these functions testable on any Unix host.

use std::fs::{File, Permissions};
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// Group that may connect to the IPC sockets and read the codrive token.
pub const IPC_GROUP: &str = "duduclaw-ipc";
/// Where the group database is read from.
pub const GROUP_FILE: &str = "/etc/group";
/// Mode when no group can be applied: owner only.
pub const PRIVATE_MODE: u32 = 0o600;
/// Mode for a socket shared with [`IPC_GROUP`] (connect needs write).
pub const SHARED_SOCKET_MODE: u32 = 0o660;
/// Mode for a secret file shared with [`IPC_GROUP`] (read only).
pub const SHARED_SECRET_MODE: u32 = 0o640;

/// What [`share_path`] / [`share_file`] ended up applying.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Access {
    /// No IPC group known: owner-only mode applied.
    Private,
    /// Group ownership and the shared mode applied.
    Group { gid: u32 },
    /// The group exists but changing the group was refused; owner-only mode
    /// applied instead. `reason` is the OS error, for the caller's log line.
    Fallback { gid: u32, reason: String },
}

impl Access {
    /// The permission bits this outcome leaves on the endpoint.
    pub fn mode(&self, shared_mode: u32) -> u32 {
        match self {
            Access::Group { .. } => shared_mode,
            Access::Private | Access::Fallback { .. } => PRIVATE_MODE,
        }
    }
}

/// Looks `name` up in the contents of a `group(5)` file and returns its gid.
/// First match wins, as with NSS `files`. Comment and blank lines are
/// skipped; a line whose gid field does not parse yields `None` (the entry is
/// unusable, and guessing would be worse).
pub fn gid_from_group_db(contents: &str, name: &str) -> Option<u32> {
    for line in contents.lines() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split(':');
        let (Some(group), Some(_password), Some(gid)) =
            (fields.next(), fields.next(), fields.next())
        else {
            continue;
        };
        if group == name {
            return gid.trim().parse().ok();
        }
    }
    None
}

/// The gid of [`IPC_GROUP`] on this host, or `None` if the group database
/// cannot be read or has no such group.
pub fn ipc_group_gid() -> Option<u32> {
    let contents = std::fs::read_to_string(GROUP_FILE).ok()?;
    gid_from_group_db(&contents, IPC_GROUP)
}

/// Applies group access to a filesystem object by path (used for listening
/// sockets: `fchown` on a socket fd changes the socket, not its filesystem
/// node). The group is changed BEFORE the mode is widened, so there is never
/// a moment where the old group (for a socket in `/run/duduclaw-kiosk`, that
/// is `duduclaw-kiosk`) has the shared mode. `lchown`: never follows a
/// symlink placed at `path`.
pub fn share_path(path: &Path, gid: Option<u32>, shared_mode: u32) -> io::Result<Access> {
    let access = match gid {
        None => Access::Private,
        Some(gid) => match std::os::unix::fs::lchown(path, None, Some(gid)) {
            Ok(()) => Access::Group { gid },
            Err(e) => Access::Fallback {
                gid,
                reason: e.to_string(),
            },
        },
    };
    std::fs::set_permissions(path, Permissions::from_mode(access.mode(shared_mode)))?;
    Ok(access)
}

/// Applies group access to an open file (used for the codrive token, which is
/// created 0600 and only then shared, all through the same descriptor, so
/// there is no window where a path swap could redirect it).
pub fn share_file(file: &File, gid: Option<u32>, shared_mode: u32) -> io::Result<Access> {
    let access = match gid {
        None => Access::Private,
        Some(gid) => match std::os::unix::fs::fchown(file, None, Some(gid)) {
            Ok(()) => Access::Group { gid },
            Err(e) => Access::Fallback {
                gid,
                reason: e.to_string(),
            },
        },
    };
    file.set_permissions(Permissions::from_mode(access.mode(shared_mode)))?;
    Ok(access)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::MetadataExt;
    use std::path::PathBuf;

    fn temp_path(tag: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        // Short name: a Unix socket path must fit in sun_path (104 bytes on
        // macOS, whose temp dir is already ~50 bytes long).
        std::env::temp_dir().join(format!(
            "dcipc-{tag}-{}-{}",
            std::process::id(),
            nanos % 1_000_000_000
        ))
    }

    /// The test process's primary gid, from `id -g` (std has no getegid).
    fn own_gid() -> u32 {
        let out = std::process::Command::new("id")
            .arg("-g")
            .output()
            .expect("run id -g");
        String::from_utf8(out.stdout)
            .expect("utf8")
            .trim()
            .parse()
            .expect("numeric gid")
    }

    fn own_uid() -> u32 {
        let out = std::process::Command::new("id")
            .arg("-u")
            .output()
            .expect("run id -u");
        String::from_utf8(out.stdout)
            .expect("utf8")
            .trim()
            .parse()
            .expect("numeric uid")
    }

    #[test]
    fn group_db_finds_exact_name() {
        let db = "root:x:0:\nduduclaw:x:1000:\nduduclaw-ipc:x:987:duduclaw,duduclaw-kiosk\n";
        assert_eq!(gid_from_group_db(db, "duduclaw-ipc"), Some(987));
        assert_eq!(gid_from_group_db(db, "duduclaw"), Some(1000));
    }

    #[test]
    fn group_db_does_not_prefix_match() {
        let db = "duduclaw-ipc2:x:5:\nduduclaw:x:1000:\n";
        assert_eq!(gid_from_group_db(db, "duduclaw-ipc"), None);
        assert_eq!(gid_from_group_db("duduclaw-ipc:x:7:\n", "duduclaw"), None);
    }

    #[test]
    fn group_db_skips_comments_blank_and_short_lines_and_first_match_wins() {
        let db = "# comment\n\nbroken-line\nduduclaw-ipc:x:42:\r\nduduclaw-ipc:x:43:\n";
        assert_eq!(gid_from_group_db(db, "duduclaw-ipc"), Some(42));
    }

    #[test]
    fn group_db_rejects_unparseable_gid() {
        assert_eq!(gid_from_group_db("duduclaw-ipc:x:abc:\n", "duduclaw-ipc"), None);
        assert_eq!(gid_from_group_db("duduclaw-ipc:x::\n", "duduclaw-ipc"), None);
        assert_eq!(gid_from_group_db("duduclaw-ipc:x:-1:\n", "duduclaw-ipc"), None);
    }

    #[test]
    fn access_mode_is_private_unless_group_applied() {
        assert_eq!(Access::Private.mode(SHARED_SOCKET_MODE), 0o600);
        assert_eq!(Access::Group { gid: 1 }.mode(SHARED_SOCKET_MODE), 0o660);
        assert_eq!(Access::Group { gid: 1 }.mode(SHARED_SECRET_MODE), 0o640);
        let fb = Access::Fallback { gid: 1, reason: "EPERM".into() };
        assert_eq!(fb.mode(SHARED_SOCKET_MODE), 0o600);
    }

    #[test]
    fn share_path_without_group_stays_owner_only() {
        let path = temp_path("nogroup");
        let listener = std::os::unix::net::UnixListener::bind(&path).expect("bind");
        std::fs::set_permissions(&path, Permissions::from_mode(0o644)).unwrap();
        let access = share_path(&path, None, SHARED_SOCKET_MODE).expect("share");
        assert_eq!(access, Access::Private);
        let mode = std::fs::symlink_metadata(&path).unwrap().mode() & 0o777;
        assert_eq!(mode, 0o600);
        drop(listener);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn share_path_with_own_group_opens_to_group() {
        let path = temp_path("owngroup");
        let listener = std::os::unix::net::UnixListener::bind(&path).expect("bind");
        let gid = own_gid();
        let access = share_path(&path, Some(gid), SHARED_SOCKET_MODE).expect("share");
        assert_eq!(access, Access::Group { gid });
        let meta = std::fs::symlink_metadata(&path).unwrap();
        assert_eq!(meta.mode() & 0o777, 0o660);
        assert_eq!(meta.gid(), gid);
        drop(listener);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn share_path_falls_back_when_chown_is_refused() {
        // Only meaningful for a non-root caller: root may chown to any gid.
        if own_uid() == 0 {
            return;
        }
        // A gid this process is very unlikely to be a member of.
        let foreign_gid = 4_000_000_000u32;
        let path = temp_path("foreign");
        std::fs::write(&path, b"x").unwrap();
        std::fs::set_permissions(&path, Permissions::from_mode(0o666)).unwrap();
        let access = share_path(&path, Some(foreign_gid), SHARED_SOCKET_MODE).expect("share");
        assert!(matches!(access, Access::Fallback { gid, .. } if gid == foreign_gid));
        let mode = std::fs::symlink_metadata(&path).unwrap().mode() & 0o777;
        assert_eq!(mode, 0o600, "a refused chown must leave the file owner-only");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn share_path_does_not_follow_a_symlink() {
        if own_uid() == 0 {
            return;
        }
        let target = temp_path("symtarget");
        std::fs::write(&target, b"x").unwrap();
        std::fs::set_permissions(&target, Permissions::from_mode(0o644)).unwrap();
        let link = temp_path("symlink");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        // lchown on the link succeeds or fails on the link itself; either way
        // the target's group must be untouched.
        let before = std::fs::metadata(&target).unwrap().gid();
        let _ = share_path(&link, Some(4_000_000_000), SHARED_SOCKET_MODE);
        assert_eq!(std::fs::metadata(&target).unwrap().gid(), before);
        let _ = std::fs::remove_file(&link);
        let _ = std::fs::remove_file(&target);
    }

    #[test]
    fn share_file_with_own_group_is_group_readable_only() {
        use std::io::Write as _;
        use std::os::unix::fs::OpenOptionsExt;
        let path = temp_path("token");
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .mode(0o600)
            .open(&path)
            .unwrap();
        f.write_all(b"secret").unwrap();
        let gid = own_gid();
        let access = share_file(&f, Some(gid), SHARED_SECRET_MODE).expect("share");
        assert_eq!(access, Access::Group { gid });
        let meta = std::fs::metadata(&path).unwrap();
        assert_eq!(meta.mode() & 0o777, 0o640);
        assert_eq!(meta.gid(), gid);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn share_file_without_group_stays_owner_only() {
        let path = temp_path("token-private");
        let f = std::fs::File::create(&path).unwrap();
        f.set_permissions(Permissions::from_mode(0o644)).unwrap();
        let access = share_file(&f, None, SHARED_SECRET_MODE).expect("share");
        assert_eq!(access, Access::Private);
        assert_eq!(std::fs::metadata(&path).unwrap().mode() & 0o777, 0o600);
        let _ = std::fs::remove_file(&path);
    }
}
