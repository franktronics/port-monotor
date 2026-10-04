# Port Monitor

Native macOS menu bar utility that displays listening TCP and UDP ports and lets you stop their processes.

Port Monitor registers itself as a login item the first time it launches from the Applications folder.

## Build the Application

```bash
./scripts/build-app.sh
```

The application is created at `dist/Port Monitor.app`. It is signed locally and intended for personal use.

## Development

Open `Package.swift` in Xcode, or use:

```bash
swift run
swift test
```

## Security

- A normal signal is attempted without elevated privileges.
- If macOS reports insufficient permission, a second confirmation appears before the administrator prompt.
- The PID, process name, and ports are checked again before every signal to avoid stopping a process that reused an old PID.
- Critical macOS processes are blocked.
- `SIGKILL` can cause data loss and always requires explicit confirmation.

Some macOS protections, including SIP, may prevent an operation even with an administrator account.
