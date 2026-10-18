# Both shipping editions support the same CPU local-model service. The base
# image adds only the service and its hard llama-cpp dependency, not the
# desktop coding-CLI bundle. Live installer recipes do not require this file.
IMAGE_INSTALL:append:pn-duduclaw-image-ab = " duduclaw-llama-server"

# Check the actual packaged rootfs, not just IMAGE_INSTALL declarations.
python duduclaw_check_local_model () {
    import os
    import stat
    import struct
    from pathlib import Path

    root = Path(d.getVar('IMAGE_ROOTFS'))
    items = [
        (d.getVar('bindir') + '/llama-server', 0o755, True),
        (d.getVar('bindir') + '/llama-cli', 0o755, True),
        (d.getVar('libexecdir') + '/duduclaw/llama-server-run', 0o755, False),
        (d.getVar('systemd_system_unitdir') + '/duduclaw-llama-server.service', 0o644, False),
    ]
    for guest, mode, elf in items:
        try:
            path = root
            parts = Path(guest).parts[1:]
            for part in parts[:-1]:
                path = path / part
                if not stat.S_ISDIR(os.lstat(path).st_mode):
                    raise ValueError('payload parent is not a real directory')
            path = path / parts[-1]
            before = os.lstat(path)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0 or
                    before.st_gid != 0 or stat.S_IMODE(before.st_mode) != mode or before.st_size == 0):
                raise ValueError('payload must be a nonempty root-owned regular file with exact mode')
            with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as stream:
                held = os.fstat(stream.fileno())
                identity = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_gid, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
                if not stat.S_ISREG(held.st_mode) or identity(held) != identity(before):
                    raise ValueError('payload changed while opening')
                header = stream.read(64)
                if elf and (len(header) != 64 or header[:7] != b'\x7fELF\x02\x01\x01' or
                            struct.unpack_from('<HHI', header, 16) not in ((2, 62, 1), (3, 62, 1))):
                    raise ValueError('model engine is not a 64-bit little-endian x86-64 ELF')
                if identity(os.fstat(stream.fileno())) != identity(held):
                    raise ValueError('payload changed while reading')
                if identity(os.lstat(path)) != identity(held):
                    raise ValueError('payload path changed while reading')
        except (OSError, ValueError) as error:
            bb.fatal('local model payload check failed for %s: %s' % (guest, error))
}
ROOTFS_POSTPROCESS_COMMAND:append = " duduclaw_check_local_model;"
