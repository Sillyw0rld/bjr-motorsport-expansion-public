# Installing the public distribution

Use the archive for your server OS: **Windows x64** or **Linux x64**. Python,
pip and Automation are not needed on the server. Install BeamMP, BJR and your
recipient car mods separately. The baseline is BeamNG.drive 0.40, BeamMP 3.9+
and BeamJoy-Revived 2.0+; see the validation report for what was actually run.

1. Stop BeamMP. Back up the installation and persistent RacePrep data.
2. Extract the platform archive **into the BeamMP server directory**. On Linux,
   use `unzip` (preserves executable permissions), or restore them with
   `chmod +x start-bjrme-server.sh bjrme-generator/bjrme-generator`.
3. Put your Automation recipient vehicle ZIPs in `Resources/Client/` as usual.
4. Start using the supplied launcher (recommended):

   Windows: double-click `start-bjrme-server.cmd`, or run
   `start-bjrme-server.cmd BeamMP-Server.exe`.

   Linux: `./start-bjrme-server.sh ./BeamMP-Server`.

   The optional first argument is the server executable (absolute paths work).
   The launcher selects the installation directory independently of your cwd.
   BeamMP still reads its normal `ServerConfig.toml` there.

   **Can't use the launcher** (for example, a hosting panel that starts
   `BeamMP-Server` itself)? Start BeamMP normally. When the server starts,
   BJR:ME runs the same bundled generator in the background and builds parts for
   new or changed cars, then asks for `reloadmods` in the console (or sends it
   itself when the server runs in tmux). Players who join after that get the new
   parts; players already on the server rejoin. Staged updates (`bjrme update`)
   and optional mods (`bjrme get`) still install at the next launcher start, or
   with the server stopped run `./bjrme-generator/bjrme-generator --beammp .`
   (Windows: `bjrme-generator\bjrme-generator.exe --beammp .`).

The generator checks the bundled donors, scans installed Automation cars and
compares input and output hashes. On first run it generates locally: vehicle
parts are **not** bundled in the release. It validates staged JBeam/catalogues,
then atomically replaces `Resources/Client/BJR_RacePrep.zip`. Only after success
does the launcher start BeamMP. No runtime Python is invoked.

On later runs it retains unchanged vehicle outputs. New/changed/removed donors
or generator data invalidate affected parts. Car changes normally affect that
car; a changed compound source can also invalidate cars selecting it as a tyre
donor. A tested engine pair is regenerated together. Missing/corrupt generated
files are repaired. No-op runs do not rewrite the client ZIP.

## Checking without starting

From the server directory:

```sh
./bjrme-generator/bjrme-generator --beammp . --check
```

Windows: `bjrme-generator\bjrme-generator.exe --beammp . --check`.
Omit `--check` to generate while the server is stopped. Use `--verbose` for the
builder diagnostics. For nonstandard server arguments, call the executable with
`--server <executable> --server-arg=<argument>` (repeat `--server-arg`).

## Clients and reloads

Preflight runs before BeamMP loads its download list, so no `reloadmods` is
needed for the normal launcher path. Joining players download the generated
client ZIP through BeamMP. Existing clients do **not** acquire server-side file
changes automatically. Change cars/donors between sessions, stop the server,
run preflight/restart, and have players reconnect. A service should run the
launcher as its foreground process and stop the whole process group.

The expansion plugin detects the public preflight marker and does not start a
background ZIP writer or send `reloadmods`. The older developer integration
remains available for legacy source installs; it is not the public startup path.
No original BJR file is modified.

## Updates and failures

- Keep `BJRME-donors/custom/` and persistent server data. Updates contain
  only README placeholders in custom directories, never custom ZIP exports.
- Keep `Resources/Server/RacePrep/updater/generation-state.json` for fast checks.
  Deleting it forces a safe rebuild. Do not manually change generated parts.
- Invalid exports/checksums, unsupported structures, permission errors and
  incomplete generation stop preflight; the server is not launched. Previous
  generated assets remain available. Correct the named source or restore a
  backup and retry. A failure before ZIP publication does not change it.
- Concurrent generators are refused. The launcher also holds
  `updater/server-session.lock` while its server process runs. After a crash,
  inspect processes and stop BeamMP before removing stale `generation.lock` or
  `server-session.lock` directories. Never remove a lock held by a live process.
- Don't run the generator by hand against a running server: stop it first. (A
  server started without the launcher runs it itself, in the background, at
  start; see step 4.)
- ZIP and state publication are separate atomic replacements. A crash between
  them causes conservative regeneration next start, not acceptance of an
  unverified ZIP. Fix filesystem permissions if publication cannot complete.

Native Windows and live multiplayer acceptance are separate release gates. A
configured CI workflow is not evidence that these gates passed.

For everyday start, donor and console update commands, see the [usage guide](USAGE.md).
