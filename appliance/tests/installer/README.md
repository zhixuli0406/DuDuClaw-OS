# Installer stream regression tests

Run the production installer's write and post-write section against temporary
regular files, without root, a block device, a VM or third-party Python modules:

```sh
python3 appliance/tests/installer/test_stream_write.py
```

Requires Python 3, Bash and the host's `awk`, `tail`, `mktemp`, `mkfifo`, `rm`
and `rmdir`. The harness reads the shipped script's actual shebang, shell options
and section 5 through its end; it does not maintain a second implementation of
the stream logic. Only external tool fixtures replace disk/image utilities.

The 29 path cases cover prefix-then-error from `zstd` and `dd` in all three
paths (numeric progress, ordinary `pv`, no `pv`), `pv` errors in its two paths,
exact successful byte copies, FIFO creation and progress-reader errors, sync
failure, optional size-listing failure and progress requested without `pv`.
They also send SIGTERM and SIGINT only to the true installer parent in all
three paths and require its stream children and progress resources to disappear.
Six startup cases inject those signals precisely between launching the real
write job and recording its PID; the pending cancellation must still be honored.
Every failed stream must stop before GPT repair or settings injection, emit no
completion or 100% sample, clean progress files and reap its stream children.
Cancellation uses the write job's dedicated process group, never the caller's
process group or process-name matching. SIGKILL is not catchable and is outside
this cleanup contract.
Without `pv`, there is no `pv` failure stage to inject; the test instead verifies
that the fallback never executes `pv` and still preserves the original bytes.

Progress samples are capped at 99 until every stream stage, progress reader and
sync succeeds. This prevents an early `pv` 100% from masking a late decoder,
checksum or disk-write error. The final 100% covers the image-write phase;
installer success still requires the later steps and a zero process exit.

These host tests do **not** validate a real zstd frame, block-device flushes,
GPT/PARTUUID preservation, image package dependencies or a bootable installation.
A real `kas build` and blank-disk QEMU installation of both shipping ISOs remain
separate required validation; no test-login image can replace those checks.
