// Password verification against the real gateway — WP-lock-pw (2026-08-22,
// lockscreen password unlock). `POST /api/login`
// (`duduclaw-gateway/src/server.rs::handle_login`, line ~2298 — read-only
// reference, not modified from here): the SAME REST endpoint the web
// dashboard's own login screen authenticates against (email + password,
// issues a fresh JWT pair on success). The lockscreen only cares about
// pass/fail — the returned `access_token`/`refresh_token` are never even
// parsed, let alone stored: this surface doesn't open or refresh a gateway
// session of its own, it just needs a yes/no answer to "is this the right
// password for this machine" (task brief: "密碼零落 log／不留明文於狀態").
//
// ── Why a hand-rolled HTTP/1.1 client ────────────────────────────────────
// Same shape as `session.rs`/`oobe/claim.rs` — see either module's own
// header comment for why this crate has no `reqwest` dependency to reach
// for. A SEPARATE, self-contained module rather than sharing code with
// either: this endpoint is a single POST with a THREE-way status split
// (200/401/429) that doesn't match `session.rs`'s single-POST/single-status
// shape or `claim.rs`'s GET-then-POST two-call shape closely enough to be
// worth threading through one shared fn — this module tree's own
// established convention (`gateway_client/mod.rs`'s header comment) is
// small independent modules over cross-module coupling.
//
// ── Which account: the machine's owner, asked from the gateway ───────────
// This surface has no concept of "which operator is unlocking" — the
// Personal edition has exactly one owner account, the one OOBE's
// `AccountCreate` step sets the password for via `/api/first-run/claim`
// (see `oobe/claim.rs`'s own header comment). Its email used to be the fixed
// placeholder `admin@local`; since platform v1.73.0 the owner can replace it
// with a real address from the dashboard. So each verify first reads the
// owner's current email from the local-session response
// (`session::local_owner_email`), then logs in with it. When no local
// session is available (auto-login switched off, a non-Personal edition, or
// an older gateway that never moved the email) it falls back to the
// placeholder, which is exactly the account those setups still have.
// Cost: one extra loopback round trip and one `login_local_auto` audit row
// per unlock attempt, which is rare (an operator typing a password).
//
// Since platform v1.73.1 the shell first asks `POST /api/owner/verify`,
// which checks the owner's password without any email (loopback only,
// shares /api/login's rate limit), so a non-Personal or auto-login-off
// owner who changed their email can still unlock. Older gateways answer
// that route with something other than `200 {"ok":true}`, and the shell
// then falls back to the email-based `/api/login` path above.
//
// ── Why the gateway's OWN 429 does not replace this surface's throttle ───
// `handle_login`'s `check_login_rate_limit` is a 15-MINUTE, IP+email-scoped
// lockout — the right guard against a sustained brute-force campaign, but
// far too coarse for the UX this surface needs (a typo shouldn't cost the
// operator fifteen minutes). `lockscreen::mod`'s own
// `FAILS_BEFORE_THROTTLE`/`THROTTLE_DURATION` (a much shorter, purely
// client-side 2s cooldown after 3 consecutive failures) exists specifically
// to keep this surface's own retry cadence well under whatever would ever
// trip the server's 15-minute gate during ordinary "wrong password, try
// again" use — 429 is still handled here (folded into `Unreachable`, see
// that variant's own doc comment) as defense in depth, not as the primary
// throttle.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

const DEFAULT_GATEWAY_URL: &str = "http://127.0.0.1:18789";
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
const READ_WRITE_TIMEOUT: Duration = Duration::from_secs(5);

/// The owner's placeholder email, used when the gateway can't tell us the
/// current one — see this file's header comment.
const FALLBACK_LOCK_ACCOUNT_EMAIL: &str = "admin@local";

/// Why a verify attempt did not resolve to `Ok(())`. `lockscreen::render`'s
/// own `apply_unlock_result` collapses every variant but
/// `InvalidCredentials` into ONE honest "本機服務未回應" (local service
/// isn't responding) message — see this file's header comment on why a rare
/// 429 belongs in that same bucket rather than a THIRD UI state the task
/// brief never asked for. Kept as distinct variants anyway (same
/// `SessionError`/`ClaimError` precedent) for the stderr diagnostic and for
/// these unit tests.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum LoginError {
    /// Couldn't complete the TCP round trip at all — DNS/connect/read/write
    /// failure, or a timeout tripped. THE case the task brief's offline
    /// fail-safe semantics are written for: no gateway reachable means no
    /// way to verify a password at all, so the lockscreen stays locked
    /// (see `lockscreen/render.rs`'s own header comment).
    Unreachable(String),
    /// `POST /api/login` -> 401 — a real password mismatch for the owner
    /// account. The ONLY variant that means "the gateway is
    /// fine, the typed password was wrong."
    InvalidCredentials,
    /// `POST /api/login` -> 429 — the gateway's OWN 15-minute rate limit
    /// tripped (see this file's header comment). Reachable in practice only
    /// after a burst far exceeding what this surface's own 2s throttle
    /// would ever let through in normal use.
    RateLimited,
    /// An HTTP status this module has no specific handling for.
    Http(u16),
    /// The response didn't parse as valid HTTP/1.1 framing (status line /
    /// UTF-8 headers) — this module never needs to read the response BODY
    /// at all (see this file's header comment), so a malformed JSON body on
    /// an otherwise well-formed 200 is not a failure case this variant (or
    /// any other) needs to cover.
    Malformed(String),
    /// The configured base URL failed the scheme/host safety gate before
    /// any I/O — same rule `session.rs`/`oobe/claim.rs` each enforce
    /// independently (refuse fail-closed before dialing out).
    NonLoopback,
}

struct HttpResponse {
    status: u16,
}

/// Real entry point — reads `DUDUCLAW_SHELL_GATEWAY_URL` (same env var, same
/// fallback, as every other client in this module tree).
pub(crate) fn verify_password(password: &str) -> Result<(), LoginError> {
    let base = gateway_base_url();
    match owner_verify_at(&base, password)? {
        OwnerVerify::Verified => Ok(()),
        OwnerVerify::Invalid => Err(LoginError::InvalidCredentials),
        OwnerVerify::RateLimited => Err(LoginError::RateLimited),
        OwnerVerify::Unsupported => {
            let email = lock_account_email(&base);
            verify_password_at(&base, &email, password)
        }
    }
}

/// Outcome of `POST /api/owner/verify` (platform v1.73.1+), which checks the
/// owner's password without needing the owner's email.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OwnerVerify {
    Verified,
    Invalid,
    RateLimited,
    /// Anything else: an older gateway without the endpoint (404/405, or a
    /// catch-all page), or a refusal. The caller falls back to `/api/login`.
    Unsupported,
}

/// Only a 200 whose body is exactly `{"ok": true}` counts as verified: an
/// older gateway's catch-all route must never be mistaken for a match.
pub(crate) fn owner_verify_at(base_url: &str, password: &str) -> Result<OwnerVerify, LoginError> {
    let (host, port) = parse_loopback_base_url(base_url)?;
    let body = serde_json::to_vec(&serde_json::json!({ "password": password }))
        .map_err(|e| LoginError::Malformed(format!("could not encode verify request body: {e}")))?;
    let (status, resp_body) = http_post_json_with_body(&host, port, "/api/owner/verify", &body)?;
    Ok(match status {
        200 => {
            let ok = serde_json::from_slice::<serde_json::Value>(&resp_body)
                .ok()
                .and_then(|v| v.get("ok").and_then(serde_json::Value::as_bool));
            if ok == Some(true) { OwnerVerify::Verified } else { OwnerVerify::Unsupported }
        }
        401 => OwnerVerify::Invalid,
        429 => OwnerVerify::RateLimited,
        _ => OwnerVerify::Unsupported,
    })
}

/// The owner's current email, or the placeholder when the gateway can't say.
/// The reason goes to stderr (no email, no password) so a fallback is never
/// silent.
fn lock_account_email(base_url: &str) -> String {
    match super::session::local_owner_email_at(base_url) {
        Ok(email) => email,
        Err(e) => {
            eprintln!("[lockscreen] owner email unavailable ({e:?}); using the placeholder account");
            FALLBACK_LOCK_ACCOUNT_EMAIL.to_string()
        }
    }
}

fn gateway_base_url() -> String {
    std::env::var("DUDUCLAW_SHELL_GATEWAY_URL")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_GATEWAY_URL.to_string())
}

/// The testable core — every test below calls this directly against a local
/// mock server, same split every other module in this tree establishes.
/// Only the HTTP STATUS drives the outcome (see `HttpResponse`'s own doc
/// comment on why the body is never parsed): 200 -> `Ok(())`, 401 ->
/// `InvalidCredentials`, 429 -> `RateLimited`, anything else -> `Http`.
pub(crate) fn verify_password_at(base_url: &str, email: &str, password: &str) -> Result<(), LoginError> {
    let (host, port) = parse_loopback_base_url(base_url)?;
    let body = serde_json::to_vec(&serde_json::json!({ "email": email, "password": password }))
        .map_err(|e| LoginError::Malformed(format!("could not encode login request body: {e}")))?;
    let resp = http_post_json(&host, port, "/api/login", &body)?;
    match resp.status {
        200 => Ok(()),
        401 => Err(LoginError::InvalidCredentials),
        429 => Err(LoginError::RateLimited),
        other => Err(LoginError::Http(other)),
    }
}

/// Identical logic to `session.rs`/`oobe/claim.rs`'s own
/// `parse_loopback_base_url` — re-derived rather than shared, see this
/// file's header comment on why this module tree favors small independent
/// modules over cross-module coupling.
fn parse_loopback_base_url(url: &str) -> Result<(String, u16), LoginError> {
    let rest = url.strip_prefix("http://").ok_or(LoginError::NonLoopback)?;
    let authority = rest.split('/').next().unwrap_or(rest);

    let (host, port) = if let Some(after_bracket) = authority.strip_prefix('[') {
        let mut parts = after_bracket.splitn(2, ']');
        let host = parts.next().ok_or(LoginError::NonLoopback)?.to_string();
        let port = match parts.next() {
            Some(p) if !p.is_empty() => p.strip_prefix(':').and_then(|d| d.parse::<u16>().ok()).ok_or(LoginError::NonLoopback)?,
            _ => 80,
        };
        (host, port)
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h.to_string(), p.parse::<u16>().map_err(|_| LoginError::NonLoopback)?),
            None => (authority.to_string(), 80),
        }
    };

    let host_lower = host.to_ascii_lowercase();
    let is_loopback = host_lower == "127.0.0.1" || host_lower == "::1" || host_lower == "localhost";
    if !is_loopback {
        return Err(LoginError::NonLoopback);
    }
    Ok((host_lower, port))
}

fn connect(host: &str, port: u16) -> Result<TcpStream, LoginError> {
    let target = if host.contains(':') { format!("[{host}]:{port}") } else { format!("{host}:{port}") };
    let mut addrs = target.to_socket_addrs().map_err(|e| LoginError::Unreachable(e.to_string()))?;
    let sock_addr = addrs.next().ok_or_else(|| LoginError::Unreachable("could not resolve any address".to_string()))?;
    let stream = TcpStream::connect_timeout(&sock_addr, CONNECT_TIMEOUT).map_err(|e| LoginError::Unreachable(e.to_string()))?;
    let _ = stream.set_read_timeout(Some(READ_WRITE_TIMEOUT));
    let _ = stream.set_write_timeout(Some(READ_WRITE_TIMEOUT));
    Ok(stream)
}

fn http_post_json(host: &str, port: u16, path: &str, body: &[u8]) -> Result<HttpResponse, LoginError> {
    let mut stream = connect(host, port)?;
    let mut request = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}:{port}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n",
        body.len()
    )
    .into_bytes();
    request.extend_from_slice(body);
    stream.write_all(&request).map_err(|e| LoginError::Unreachable(e.to_string()))?;
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).map_err(|e| LoginError::Unreachable(e.to_string()))?;
    parse_response(&raw)
}

/// Like `http_post_json`, but also returns the response body (after the
/// header terminator); used only where the body decides the outcome.
fn http_post_json_with_body(host: &str, port: u16, path: &str, body: &[u8]) -> Result<(u16, Vec<u8>), LoginError> {
    let mut stream = connect(host, port)?;
    let mut request = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}:{port}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n",
        body.len()
    )
    .into_bytes();
    request.extend_from_slice(body);
    stream.write_all(&request).map_err(|e| LoginError::Unreachable(e.to_string()))?;
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).map_err(|e| LoginError::Unreachable(e.to_string()))?;
    let status = parse_response(&raw)?.status;
    let body_start = raw.windows(4).position(|w| w == b"\r\n\r\n").map(|i| i + 4).unwrap_or(raw.len());
    Ok((status, raw[body_start..].to_vec()))
}

/// Only the status LINE is parsed — see `HttpResponse`'s own doc comment on
/// why this module never needs the body at all, unlike every other client
/// in this tree.
fn parse_response(raw: &[u8]) -> Result<HttpResponse, LoginError> {
    let header_end = raw.windows(4).position(|w| w == b"\r\n\r\n").unwrap_or(raw.len());
    let header_text = std::str::from_utf8(&raw[..header_end]).map_err(|_| LoginError::Malformed("response headers were not valid UTF-8".to_string()))?;
    let status_line = header_text.split("\r\n").next().ok_or_else(|| LoginError::Malformed("empty HTTP response".to_string()))?;
    let status: u16 = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| LoginError::Malformed(format!("could not parse HTTP status line: {status_line:?}")))?;
    Ok(HttpResponse { status })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    /// Same one-connection-per-canned-response mock server shape as
    /// `session.rs`'s own `start_mock_server` — this endpoint only ever
    /// sends ONE request per call.
    fn start_mock_server(response: &'static str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
        let addr = listener.local_addr().expect("local_addr");
        std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut sink = [0u8; 4096];
                let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
                let _ = stream.read(&mut sink);
                let _ = stream.write_all(response.as_bytes());
                let _ = stream.shutdown(std::net::Shutdown::Write);
            }
        });
        format!("http://{addr}")
    }

    /// Like `start_mock_server`, but hands back the raw request it received.
    fn start_capturing_mock_server(response: &'static str) -> (String, std::sync::mpsc::Receiver<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
        let addr = listener.local_addr().expect("local_addr");
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut buf = [0u8; 4096];
                let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
                let n = stream.read(&mut buf).unwrap_or(0);
                let _ = tx.send(String::from_utf8_lossy(&buf[..n]).into_owned());
                let _ = stream.write_all(response.as_bytes());
                let _ = stream.shutdown(std::net::Shutdown::Write);
            }
        });
        (format!("http://{addr}"), rx)
    }

    #[test]
    fn owner_verify_accepts_only_ok_true_bodies() {
        let base = start_mock_server("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"ok\":true}");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::Verified);
        // An older gateway's catch-all page must never unlock.
        let base = start_mock_server("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<!doctype html><html></html>");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::Unsupported);
        let base = start_mock_server("HTTP/1.1 200 OK\r\n\r\n{\"ok\":false}");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::Unsupported);
    }

    #[test]
    fn owner_verify_maps_statuses() {
        let base = start_mock_server("HTTP/1.1 401 Unauthorized\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::Invalid);
        let base = start_mock_server("HTTP/1.1 429 Too Many Requests\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::RateLimited);
        let base = start_mock_server("HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(owner_verify_at(&base, "pw").unwrap(), OwnerVerify::Unsupported);
    }

    #[test]
    fn owner_verify_sends_only_the_password() {
        let (base, rx) = start_capturing_mock_server("HTTP/1.1 200 OK\r\n\r\n{\"ok\":true}");
        assert_eq!(owner_verify_at(&base, "pw-123456").unwrap(), OwnerVerify::Verified);
        let request = rx.recv_timeout(Duration::from_secs(2)).expect("request captured");
        assert!(request.starts_with("POST /api/owner/verify "), "{request}");
        assert!(request.contains(r#"{"password":"pw-123456"}"#), "{request}");
        assert!(!request.contains("email"), "{request}");
    }

    #[test]
    fn login_request_carries_the_given_email() {
        let (base, rx) = start_capturing_mock_server("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(verify_password_at(&base, "owner@example.com", "pw-123456"), Ok(()));
        let request = rx.recv_timeout(Duration::from_secs(2)).expect("request captured");
        assert!(request.starts_with("POST /api/login "), "{request}");
        assert!(request.contains(r#""email":"owner@example.com""#), "{request}");
    }

    #[test]
    fn lock_account_email_follows_the_owner() {
        let base = start_mock_server(
            "HTTP/1.1 200 OK\r\n\r\n{\"access_token\":\"j\",\"user\":{\"email\":\"owner@example.com\"}}",
        );
        assert_eq!(lock_account_email(&base), "owner@example.com");
    }

    /// No local session (auto-login off, non-Personal, unreachable): the
    /// placeholder account those setups still have.
    #[test]
    fn lock_account_email_falls_back_to_the_placeholder() {
        let base = start_mock_server("HTTP/1.1 403 Forbidden\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(lock_account_email(&base), FALLBACK_LOCK_ACCOUNT_EMAIL);
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("local_addr");
        drop(listener);
        assert_eq!(lock_account_email(&format!("http://{addr}")), FALLBACK_LOCK_ACCOUNT_EMAIL);
    }

    #[test]
    fn correct_password_returns_ok() {
        let base = start_mock_server(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 9\r\n\r\n{\"ok\":1}\n",
        );
        assert_eq!(verify_password_at(&base, "owner@example.com", "correct-horse-battery-staple"), Ok(()));
    }

    #[test]
    fn wrong_password_maps_to_invalid_credentials() {
        let base = start_mock_server("HTTP/1.1 401 Unauthorized\r\nContent-Length: 9\r\n\r\n{\"x\":1}\n\n");
        assert_eq!(verify_password_at(&base, "owner@example.com", "wrong-password"), Err(LoginError::InvalidCredentials));
    }

    #[test]
    fn rate_limited_maps_to_rate_limited() {
        let base = start_mock_server("HTTP/1.1 429 Too Many Requests\r\nContent-Length: 7\r\n\r\n{\"x\":1}");
        assert_eq!(verify_password_at(&base, "owner@example.com", "any-password"), Err(LoginError::RateLimited));
    }

    #[test]
    fn unexpected_status_maps_to_http() {
        let base = start_mock_server("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 2\r\n\r\n{}");
        assert_eq!(verify_password_at(&base, "owner@example.com", "any-password"), Err(LoginError::Http(500)));
    }

    #[test]
    fn connection_refused_maps_to_unreachable() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("local_addr");
        drop(listener);
        let result = verify_password_at(&format!("http://{addr}"), "owner@example.com", "any-password");
        assert!(matches!(result, Err(LoginError::Unreachable(_))), "{result:?}");
    }

    #[test]
    fn non_loopback_url_is_refused_without_any_connection_attempt() {
        let started = std::time::Instant::now();
        let result = verify_password_at("http://example.com:18789", "owner@example.com", "any-password");
        assert_eq!(result, Err(LoginError::NonLoopback));
        assert!(started.elapsed() < Duration::from_millis(500), "must fail before ever dialing out, elapsed={:?}", started.elapsed());
    }

    #[test]
    fn missing_header_body_separator_still_parses_the_status_line() {
        // Exercises the "no \r\n\r\n found anywhere" fallback in
        // `parse_response` (`header_end` defaults to the whole buffer) — a
        // degenerate response that closes right after the status line, with
        // no headers and no blank-line terminator at all.
        let base = start_mock_server("HTTP/1.1 200 OK\r\n");
        assert_eq!(verify_password_at(&base, "owner@example.com", "any-password"), Ok(()));
    }

    #[test]
    fn parse_loopback_base_url_accepts_all_three_loopback_spellings() {
        assert_eq!(parse_loopback_base_url("http://127.0.0.1:18789"), Ok(("127.0.0.1".to_string(), 18789)));
        assert_eq!(parse_loopback_base_url("http://localhost:18789"), Ok(("localhost".to_string(), 18789)));
        assert_eq!(parse_loopback_base_url("http://[::1]:18789"), Ok(("::1".to_string(), 18789)));
    }

    /// Live-fire pairing check against a REAL gateway — `#[ignore]`d so
    /// `cargo test` never depends on one being up, same convention
    /// `oobe/claim.rs`'s own `live_first_run_claim_against_env_gateway`
    /// establishes. Verification playbook (WP-lock-pw, 2026-08-22):
    ///   1. start a gateway with a home whose owner password is
    ///      already known, e.g. a fresh home claimed via
    ///      `DUDUCLAW_HOME=$(mktemp -d) DUDUCLAW_PORT=28794 duduclaw run`
    ///      then `POST /api/first-run/claim` with a known password (see
    ///      `oobe/claim.rs`'s own live test for the exact claim call, or
    ///      just claim it via the web dashboard once).
    ///   2. `DUDUCLAW_SHELL_GATEWAY_URL=http://127.0.0.1:28794 \
    ///      DUDUCLAW_SHELL_LIVE_LOCK_PASSWORD=<the password just claimed> \
    ///      cargo test -p duduclaw-shell -- --ignored live_verify_password --nocapture`
    #[test]
    #[ignore = "requires a live gateway with a known owner password — see doc comment"]
    fn live_verify_password_against_env_gateway() {
        let Some(base) = std::env::var("DUDUCLAW_SHELL_GATEWAY_URL").ok().filter(|v| !v.trim().is_empty()) else {
            eprintln!("[live] DUDUCLAW_SHELL_GATEWAY_URL not set — skipping");
            return;
        };
        let Some(password) = std::env::var("DUDUCLAW_SHELL_LIVE_LOCK_PASSWORD").ok().filter(|v| !v.trim().is_empty()) else {
            eprintln!("[live] DUDUCLAW_SHELL_LIVE_LOCK_PASSWORD not set — skipping");
            return;
        };
        let email = lock_account_email(&base);
        eprintln!("[live] verifying against the owner account the gateway reports");
        let wrong = verify_password_at(&base, &email, "definitely-the-wrong-password-12345");
        assert_eq!(wrong, Err(LoginError::InvalidCredentials), "a wrong password must be rejected");
        eprintln!("[live] wrong password correctly rejected");

        let right = verify_password_at(&base, &email, &password);
        assert_eq!(right, Ok(()), "the real password must verify");
        eprintln!("[live] correct password verified against {base}");
    }
}
