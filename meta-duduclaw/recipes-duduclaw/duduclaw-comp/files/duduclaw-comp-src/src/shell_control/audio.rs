//! Volume control for the gateway (rootless gateway, 2026-10-15).
//!
//! The gateway's audio bridge used to run `wpctl` itself as root against the
//! kiosk session's PipeWire socket. The gateway now runs as uid 1000, the uid
//! every AI employee shares, and a PipeWire socket is all-or-nothing: any
//! client that can connect may record the microphone or attach to screen-cast
//! streams. So the gateway asks comp instead, over the shell-control socket
//! (already SO_PEERCRED-authenticated, Agent authority), and comp, running as
//! the kiosk user with its own PipeWire access, runs `wpctl` with a fixed
//! argument list: read the default output's volume, set volume or mute on
//! it, read `wpctl status`, or switch the default output to a numeric id.
//! Nothing a caller sends ever becomes a free-form wpctl argument.
//!
//! These verbs run on the socket thread, not the compositor's calloop
//! thread: a hung `wpctl` must not stall rendering. Each `wpctl` call is
//! bounded by [`WPCTL_TIMEOUT`] and killed when it overruns.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use super::protocol::{AudioInfo, ShellControlRequest, ShellControlResponse};

/// The wpctl binary (on PATH in the kiosk session).
pub(crate) const WPCTL: &str = "wpctl";
/// The same target name duduclaw-shell's own audio backend uses.
pub(crate) const DEFAULT_SINK: &str = "@DEFAULT_AUDIO_SINK@";
/// Upper bound a caller may set. wpctl accepts more (amplification); the
/// gateway's slider never needs it.
pub(crate) const MAX_VOLUME_PCT: i64 = 100;
/// Largest object id accepted for `set_audio_output` (PipeWire ids are u32;
/// anything past i32 is not a real object on this box).
pub(crate) const MAX_OBJECT_ID: i64 = i32::MAX as i64;
const WPCTL_TIMEOUT: Duration = Duration::from_secs(3);
/// `wpctl status` on a desktop with many devices is a few KB; cap what is
/// relayed so a pathological output cannot balloon the response line.
const MAX_STATUS_BYTES: usize = 64 * 1024;

/// Field validation for the three audio verbs (called from
/// `listener::validate`). `None` for every other op.
pub(crate) fn validate(req: &ShellControlRequest) -> Option<Result<(), String>> {
    match req {
        ShellControlRequest::GetAudio => Some(Ok(())),
        ShellControlRequest::SetAudio { volume_pct, muted } => Some(match (volume_pct, muted) {
            (None, None) => Err("set_audio needs volume_pct and/or muted".into()),
            (Some(v), _) if !(0..=MAX_VOLUME_PCT).contains(v) => {
                Err(format!("set_audio volume_pct must be 0..={MAX_VOLUME_PCT}"))
            }
            _ => Ok(()),
        }),
        ShellControlRequest::SetAudioOutput { id } => Some(if (1..=MAX_OBJECT_ID).contains(id) {
            Ok(())
        } else {
            Err("set_audio_output id must be a positive PipeWire object id".into())
        }),
        _ => None,
    }
}

/// wpctl's volume argument for a percentage: `40` -> `"0.40"`.
pub(crate) fn volume_arg(pct: i64) -> String {
    let pct = pct.clamp(0, MAX_VOLUME_PCT);
    format!("{}.{:02}", pct / 100, pct % 100)
}

/// Parses `wpctl get-volume` output: `Volume: 0.45` or
/// `Volume: 0.45 [MUTED]`. Returns (percent, muted).
pub(crate) fn parse_get_volume(out: &str) -> Option<(i64, bool)> {
    let line = out.lines().find(|l| l.trim_start().starts_with("Volume:"))?;
    let rest = line.trim_start().strip_prefix("Volume:")?.trim();
    let mut parts = rest.split_whitespace();
    let value: f64 = parts.next()?.parse().ok()?;
    if !value.is_finite() || value < 0.0 {
        return None;
    }
    let muted = parts.any(|p| p == "[MUTED]");
    Some(((value * 100.0).round() as i64, muted))
}

/// The wpctl argument lists a verb runs, in order. Pure, so the mapping
/// from request to command is unit-tested without wpctl installed.
pub(crate) fn plan(req: &ShellControlRequest) -> Vec<Vec<String>> {
    match req {
        ShellControlRequest::GetAudio => vec![
            vec!["get-volume".into(), DEFAULT_SINK.into()],
            vec!["status".into()],
        ],
        ShellControlRequest::SetAudio { volume_pct, muted } => {
            let mut cmds = Vec::new();
            if let Some(v) = volume_pct {
                cmds.push(vec!["set-volume".into(), DEFAULT_SINK.into(), volume_arg(*v)]);
            }
            if let Some(m) = muted {
                cmds.push(vec!["set-mute".into(), DEFAULT_SINK.into(), if *m { "1" } else { "0" }.into()]);
            }
            cmds.push(vec!["get-volume".into(), DEFAULT_SINK.into()]);
            cmds
        }
        ShellControlRequest::SetAudioOutput { id } => vec![
            vec!["set-default".into(), id.to_string()],
            vec!["status".into()],
        ],
        _ => Vec::new(),
    }
}

/// Runs one wpctl call with the timeout. Ok(stdout) on exit status 0.
fn run_wpctl(args: &[String]) -> Result<String, String> {
    let mut child = Command::new(WPCTL)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("wpctl_unavailable: {e}"))?;
    let deadline = Instant::now() + WPCTL_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut out = String::new();
                if let Some(mut so) = child.stdout.take() {
                    let _ = so.by_ref().take(MAX_STATUS_BYTES as u64).read_to_string(&mut out);
                }
                return if status.success() { Ok(out) } else { Err("wpctl_failed".into()) };
            }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("wpctl_timeout".into());
            }
            Err(e) => return Err(format!("wpctl_wait_failed: {e}")),
        }
    }
}

/// Executes an audio verb. `None` for any other op (the caller dispatches
/// those to the compositor thread as before). The returned `detail` is the
/// audit line for the two setters (`None` for the read-only verb).
pub(crate) fn handle(req: &ShellControlRequest) -> Option<(ShellControlResponse, Option<String>)> {
    let cmds = plan(req);
    if cmds.is_empty() {
        return None;
    }
    let mut info = AudioInfo { volume_pct: None, muted: None, status: None };
    for args in &cmds {
        let out = match run_wpctl(args) {
            Ok(out) => out,
            Err(e) => return Some((ShellControlResponse::err(e), None)),
        };
        match args[0].as_str() {
            "get-volume" => match parse_get_volume(&out) {
                Some((v, m)) => {
                    info.volume_pct = Some(v);
                    info.muted = Some(m);
                }
                None => return Some((ShellControlResponse::err("wpctl_unparseable"), None)),
            },
            "status" => info.status = Some(out),
            _ => {}
        }
    }
    let detail = match req {
        ShellControlRequest::SetAudio { volume_pct, muted } => {
            Some(format!("volume_pct={volume_pct:?} muted={muted:?}"))
        }
        ShellControlRequest::SetAudioOutput { id } => Some(format!("id={id}")),
        _ => None,
    };
    Some((ShellControlResponse::audio(info), detail))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volume_arg_formats_two_decimals_and_clamps() {
        assert_eq!(volume_arg(0), "0.00");
        assert_eq!(volume_arg(7), "0.07");
        assert_eq!(volume_arg(40), "0.40");
        assert_eq!(volume_arg(100), "1.00");
        assert_eq!(volume_arg(250), "1.00");
        assert_eq!(volume_arg(-5), "0.00");
    }

    #[test]
    fn parse_get_volume_reads_value_and_mute() {
        assert_eq!(parse_get_volume("Volume: 0.45\n"), Some((45, false)));
        assert_eq!(parse_get_volume("Volume: 0.45 [MUTED]\n"), Some((45, true)));
        assert_eq!(parse_get_volume("Volume: 1.00"), Some((100, false)));
        assert_eq!(parse_get_volume("garbage"), None);
        assert_eq!(parse_get_volume("Volume: abc"), None);
        assert_eq!(parse_get_volume("Volume: -1.0"), None);
    }

    #[test]
    fn validate_bounds() {
        assert_eq!(validate(&ShellControlRequest::GetAudio), Some(Ok(())));
        assert!(matches!(validate(&ShellControlRequest::SetAudio { volume_pct: None, muted: None }), Some(Err(_))));
        assert!(matches!(validate(&ShellControlRequest::SetAudio { volume_pct: Some(101), muted: None }), Some(Err(_))));
        assert!(matches!(validate(&ShellControlRequest::SetAudio { volume_pct: Some(-1), muted: None }), Some(Err(_))));
        assert_eq!(validate(&ShellControlRequest::SetAudio { volume_pct: Some(100), muted: None }), Some(Ok(())));
        assert_eq!(validate(&ShellControlRequest::SetAudio { volume_pct: None, muted: Some(true) }), Some(Ok(())));
        assert!(matches!(validate(&ShellControlRequest::SetAudioOutput { id: 0 }), Some(Err(_))));
        assert!(matches!(validate(&ShellControlRequest::SetAudioOutput { id: MAX_OBJECT_ID + 1 }), Some(Err(_))));
        assert_eq!(validate(&ShellControlRequest::SetAudioOutput { id: 52 }), Some(Ok(())));
        assert_eq!(validate(&ShellControlRequest::ListWindows), None);
    }

    #[test]
    fn plan_uses_fixed_arguments_only() {
        assert_eq!(
            plan(&ShellControlRequest::SetAudio { volume_pct: Some(30), muted: Some(false) }),
            vec![
                vec!["set-volume".to_string(), DEFAULT_SINK.into(), "0.30".into()],
                vec!["set-mute".to_string(), DEFAULT_SINK.into(), "0".into()],
                vec!["get-volume".to_string(), DEFAULT_SINK.into()],
            ]
        );
        assert_eq!(
            plan(&ShellControlRequest::SetAudioOutput { id: 52 }),
            vec![vec!["set-default".to_string(), "52".into()], vec!["status".to_string()]]
        );
        assert_eq!(
            plan(&ShellControlRequest::GetAudio),
            vec![vec!["get-volume".to_string(), DEFAULT_SINK.into()], vec!["status".to_string()]]
        );
        assert!(plan(&ShellControlRequest::ListWindows).is_empty());
    }

    #[test]
    fn audio_verbs_are_agent_allowed_and_parse_from_the_wire() {
        let req: ShellControlRequest = serde_json::from_str(r#"{"op":"set_audio","params":{"volume_pct":40}}"#).unwrap();
        assert_eq!(req, ShellControlRequest::SetAudio { volume_pct: Some(40), muted: None });
        assert!(req.agent_allowed());
        let req: ShellControlRequest = serde_json::from_str(r#"{"op":"get_audio"}"#).unwrap();
        assert!(req.agent_allowed());
        assert_eq!(req.op_name(), "get_audio");
        let bad = serde_json::from_str::<ShellControlRequest>(r#"{"op":"set_audio","params":{"volume_pct":40,"args":"x"}}"#);
        assert!(bad.is_err(), "unknown fields must be rejected");
    }
}
