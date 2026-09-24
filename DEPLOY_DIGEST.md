# Deploy over SSH

Built on 2026-09-21. This is the reasoning behind the deploy keys, the exact
commands each step runs, and the first thing to look at after a failure.

Nothing in the ssh path ran on this machine. No sshd listens here, so the copy,
the remote run and the remote debug were never exercised against a real target.
The parts that do not need a device were tested, and section 6 says which.

## 1. What it does

Qt Creator deploys in three steps: install the project into a staging tree, copy
that tree to the device, start the program there. The same three steps are now
bound to four keys.

| Key | Command | Steps it runs |
|---|---|---|
| `<leader>mh` | `:CMakeSelectDevice` | Pick the device. The choice is remembered per project root. |
| `<leader>mu` | `:CMakeDeploy` | Build, install, before_deploy, copy. |
| `<leader>mr` | `:CMakeRunRemote` | The four above, then before_run and the program. |
| `<leader>md` | `:CMakeDebugRemote` | The four above, then gdbserver and the cross gdb. |
| | `:CMakeDeployDoctor` | Report what the deploy and the debug setup lack. |

A `!` on any of the three commands skips the pre-flight checks. The checks
otherwise block the command, the way `:CMakeBuildChecked` does.

## 2. Decisions already taken

These were chosen deliberately. If a test contradicts one, that is new
information, and not a question left open:

- The device is an ssh Host alias. Address, login user, port, key and jump host
  all stay in `~/.ssh/config`, which ssh and rsync read by themselves.
- The files land in a directory the login user owns. No sudo runs anywhere.
- rsync carries the files, over ssh.
- The debugger is the cross gdb of the SDK, driven through `cppdbg`. codelldb
  keeps the host, and the two do not overlap.
- One key runs the whole chain, because a stale build on the device is the
  failure this feature exists to prevent.

## 3. The device table

`vim.g.qss_devices`, declared in the project `.nvim.lua`, which `init.lua:3`
reads through `exrc`. A list and a name-to-device map are both accepted. An
entry without `ssh` is dropped. `doc/yocto-exrc-template.lua` holds the filled
example.

| Field | Default | Read by |
|---|---|---|
| `name` | The `ssh` alias, or the map key. | The picker, the staging path. |
| `ssh` | Required. | Every ssh and rsync call. |
| `prefix` | None. The doctor refuses without it. | `CMAKE_INSTALL_PREFIX`, the copy destination, and the working directory of the program. |
| `env` | `{}` | `env A=b` in front of the program. |
| `args` | `{}` | Arguments of the program and of gdbserver. |
| `before_deploy` | `{}` | After the install, before the copy. |
| `before_run` | `{}` | The same ssh connection as the program. |
| `gdb` | None. Required for `<leader>md`. | `miDebuggerPath`. |
| `gdbserver` | `gdbserver` | The command started on the device. |
| `sysroot` | None. | `set sysroot` in gdb. |
| `source_map` | `{}` | One `set substitute-path` per entry. |
| `port` | `2345` | The port gdbserver holds, and the port gdb dials. |

A trailing slash on `prefix` and on `sysroot` is stripped. A hook given as one
string becomes a list of one.

## 4. The chain, as commands

Run these by hand to find which step breaks. `<staging>` is
`<build dir>/qss-deploy/<device name>`, and `<staged root>` is
`<staging><prefix>`. The build directory is the one cmake-tools reports, which
is `out/Debug` by default and not `build`.

```sh
# 1. build            cmake-tools/build.lua:15, the args the :CMake* keys use
cmake --build out/Debug --parallel

# 2. install          cmake-tools/deploy.lua:134
DESTDIR=$PWD/out/Debug/qss-deploy/rpi4 cmake --install $PWD/out/Debug --config Debug

# 3. before_deploy    cmake-tools/deploy.lua:160, skipped when the list is empty
ssh rpi4-dev '( systemctl stop myapp ; true )'

# 4. copy             cmake-tools/deploy.lua:177
rsync -az --info=progress2 --delete \
    $PWD/out/Debug/qss-deploy/rpi4/home/root/app/ rpi4-dev:/home/root/app/

# 5. run              cmake-tools/deploy.lua:252
ssh -t rpi4-dev "cd '/home/root/app' && ( pkill -f myapp ; true ) && \
    env 'QT_QPA_PLATFORM=eglfs' '/home/root/app/bin/myapp'"

# 6. debug            cmake-tools/deploy.lua:355
ssh -t rpi4-dev "cd '/home/root/app' && ( pkill -f myapp ; true ) && \
    env 'QT_QPA_PLATFORM=eglfs' 'gdbserver' ':2345' '/home/root/app/bin/myapp'"
```

Step 2 uses `DESTDIR` and not `--prefix`. The binary is configured with the
prefix it runs under on the device. The RPATH and the QML import paths inside it
are therefore already right. `DESTDIR` only decides where that layout is
assembled here. That is what makes the staging tree a mirror of the device.

Between step 2 and step 4, an empty staged tree stops the chain
(`deploy.lua:124`). A project with no `install()` rule makes `cmake --install`
succeed and copy nothing, and that is the one failure in this chain that looks
like success.

After step 6, gdb attaches (`deploy.lua:317`). Its `miDebuggerServerAddress`
is the hostname that `ssh -G <alias>` reports. Its `program` is the binary in
the build tree. It also runs `set sysroot`, and one `set substitute-path` per
`source_map` entry. `program` is the build-tree file on purpose, because the
staged copy is often stripped.

## 5. Where each piece lives

| File | What it holds |
|---|---|
| `lua/qss_nvim/remote/device.lua` | The device table, the selection, `ssh -G` resolution, and every argv builder. No CMake knowledge. |
| `lua/qss_nvim/remote/doctor.lua` | The pre-flight checks. `M.run` for a deploy, `M.debug` adds the cross toolchain ones. |
| `lua/qss_nvim/cmake-tools/deploy.lua` | The chain, the staging paths, the dap configuration. |
| `lua/qss_nvim/cmake-tools/build.lua` | The shared build step, taken out of `tests.lua`. |
| `lua/qss_nvim/findings.lua` | The `:*Doctor` renderer, taken out of `cmake-tools/init.lua`. |
| `lua/qss_nvim/nvim-dap/adapters/cppdbg.lua` | Registers the adapter. It registers no configuration. |
| `lua/qss_nvim/cmake-tools/state.lua` | Gained `cache_values()`, the name-to-value cache reader. |

Two constants are the ones most likely to need an edit: `LISTENING` at
`deploy.lua:278` is the gdbserver line the attach waits for, and
`LISTEN_TIMEOUT_MS` at `deploy.lua:281` is how long it waits.

## 6. What was tested, and how

- 37 unit checks on the pure functions of `device.lua`. They cover the argv
  builders, the defaults, both table shapes and the hook wrapping. They also
  cover the `--delete` guard for seven refused prefixes, and the selection with
  one device and with two. All passed.
- The staging tree, against a real CMake project with an `install(TARGETS ...)`
  rule. `DESTDIR` produced
  `out/Debug/qss-deploy/local/home/root/app/bin/qssapp`, and the remote path
  came back as `/home/root/app/bin/qssapp`.
- The loaded configuration. The four commands exist, and the four keys carry
  their descriptions. `cppdbg` and `codelldb` are both registered. `tests.lua`
  still exposes `components`, `run_all` and the shared build helper.
- Every blocked path: no device, two devices and no choice, and a device with no
  cross gdb. Each one reported and stopped.
- `lua-language-server --check` over `lua/`. It adds nothing beyond the
  `Undefined global vim` noise that all 131 files already carry.

The test scripts were written to the session scratchpad, so they are gone.
Recreating them is the recipe in `doc/` terms: one Lua file per area, run with
`nvim --headless -c "lua pcall(dofile, ...)" -c "qa!"`, results written to a
file. Never wait with `vim.defer_fn`, because the timer never fires without a
UI and the run hangs.

## 7. If a test fails tomorrow

| Symptom | First thing to look at |
|---|---|
| `Text file busy` from rsync | The old binary still runs. Put the stop command in `before_deploy`. |
| Files land in the wrong place | `CMAKE_INSTALL_PREFIX` against `prefix`. `:CMakeDeployDoctor` compares them, and `<leader>mv` edits the cache. |
| Nothing is copied, and no error | The project installs no files. The chain stops at `deploy.lua:124` with that text. |
| Stale files stay on the device | `prefix` is one of the shared directories at `device.lua:50`, so `--delete` was dropped on purpose. |
| The copy asks for a password | rsync reads `~/.ssh/config` like ssh. The key belongs there, not here. |
| The debugger never attaches | gdbserver printed another line. Compare its output in the task pane with `LISTENING` at `deploy.lua:278`. |
| gdb attaches and has no symbols | The build type. The launch target must be built with debug information. |
| gdb shows no sources | `source_map`. The build records container paths, so `/work` and `/build` both need an entry. |
| `ssh does not know the host` | `ssh -G <alias>` fails. The alias is not in `~/.ssh/config`. |
| The program starts and dies at once | The environment. Add what the image needs to `env`, starting with the Qt platform plugin. |

## 8. What is deliberately not there

- No overseer template for the deploy. The chain needs a Lua check between the
  install and the copy, and a continuation for the run and the debug. A second
  code path that expresses the same chain as one command line is worth less than
  one path that works. `<leader>mm` therefore does not offer it.
- No `after_run` hook. Nothing asked for a restore step yet. It is the same
  shape as the two hooks that exist.
- Hook failures never stop the chain. `pkill` with nothing to kill exits 1, and
  a unit that is already stopped is the state the hook wants. A failure that
  matters is reported by the step after it.
- `cpp_gdb.lua` stays out of the adapter loader. Its line 67 overwrites
  `dap.configurations.cpp` with a hardcoded path, and the new adapter file
  exists so that nothing has to bring it back.

## 9. Your remaining setup

1. Install `gdbserver` on the target image.
2. Add the `Host` block for the device to `~/.ssh/config`, with a key.
3. Copy `doc/yocto-exrc-template.lua` to the project `.nvim.lua` and fill in the
   SDK path, the alias and the prefix.
4. Set `CMAKE_INSTALL_PREFIX` to that prefix with `<leader>mv`, then configure.
5. Run `:CMakeDeployDoctor`, then `<leader>mu`.
