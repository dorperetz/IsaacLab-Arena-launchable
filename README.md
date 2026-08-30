# Isaac Lab Arena Launchable

A one-click [NVIDIA Brev](https://brev.nvidia.com) Launchable that boots to a browser with
**Isaac Sim 6.0.1**, **Isaac Lab 3.0**, **[Isaac Lab Arena](https://github.com/isaac-sim/IsaacLab-Arena)**,
a **VS Code** IDE and a **streaming Isaac Sim viewport** — no local install, no GPU on your desk.

It is the presentation tier of [isaac-launchable](https://github.com/isaac-sim/isaac-launchable)
(code-server + nginx + WebRTC web viewer) layered on top of Arena's own container image, so
Arena remains the single source of truth for the simulation stack.

## What you get

| URL | What |
|---|---|
| `/` | VS Code in the browser (code-server), opened on `/workspaces` |
| `/viewer/` | The Isaac Sim viewport, streamed over WebRTC |

Inside the container:

- Isaac Sim 6.0.1 at `/isaac-sim` — `python` is aliased to `/isaac-sim/python.sh`
- Isaac Lab 3.0, installed editable from `submodules/IsaacLab`
- Isaac Lab Arena and all nine `isaaclab_arena*` packages, installed editable with `[dev]`
- The GR00T and OpenPI remote policy clients, the OSMO CLI, `gh`, `hf`, `pre-commit`
- The Arena clone bind-mounted at `/workspaces/isaaclab_arena` — **edits persist on the host**

Nothing auto-starts. The viewer shows "Waiting for stream..." until you run a command;
the in-browser README has the exact commands.

## Deploying on Brev

1. Go to [brev.nvidia.com](https://brev.nvidia.com) and create a new Launchable.
2. **Compute**: pick a GPU **with RT cores** — Kit streaming requires them. L40S / L4 / A10G
   class works. AWS is the tested provider; Crusoe instances are known not to work.
3. **Disk**: at least **250 GB**. The Isaac Sim base image alone is ~20 GB and the built
   Arena image is considerably larger.
4. **Container**: choose *VM Mode* → "Basic VM with Python installed", "I don't have any
   code files", no Jupyter.
5. **Setup script**: paste the contents of [`setup.sh`](setup.sh) into the *Paste Script* tab.
6. **Expose ports**: add a **Secure Link** named `isaac` on port **80**, and TCP/UDP port
   rules for:

   ```
   1024
   47998
   49100
   ```

   Port 80 carries VS Code and the WebRTC signaling handshake through nginx; 1024 and 47998
   carry the WebRTC media stream directly, bypassing the proxy. 49100 is the Kit signaling
   server.

### First boot takes a while

The setup script builds the Arena image on the instance — expect **45–90 minutes**. Until
the `vscode` container is up, port 80 returns `502`. Watch progress with:

```bash
tail -f ~/isaac-arena-build.log
```

If you would rather not wait on every deploy, build the image once, push it to a registry
you control, and have the instance pull it: set `ARENA_IMAGE` in `.env` to the pushed tag
and run `./build.sh -s`.

## Running it yourself (local or your own GPU host)

Requires Linux x86_64, an NVIDIA GPU with RT cores, Docker, and the NVIDIA Container Toolkit.
This stack does not run on macOS or Windows.

```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
git clone https://github.com/isaac-sim/IsaacLab-Arena.git
git -C IsaacLab-Arena submodule update --init --recursive

git clone https://github.com/dorperetz/IsaacLab-Arena-launchable.git isaac-arena-launchable
cd isaac-arena-launchable
cp .env.example .env    # then edit ARENA_REPO, HOST_UID/HOST_USER, VIEWER_ENV=localhost
./build.sh
docker compose up -d
```

Open <http://localhost/> for VS Code and <http://localhost/viewer/> for the viewport.

`just deploy` does the build and launch in one step; `just --list` shows the rest.

## How it fits together

Three containers, all on the host network so they reach each other over `localhost`:

```
browser ──80──> nginx ─┬─ /        ──> code-server        :8080  (loopback only)
                       ├─ /viewer/ ──> web viewer (Vite)  :5173
                       └─ /sign_in ──> Kit WebRTC signaling:49100
browser ──1024/47998 (UDP)─────────> Kit WebRTC media (direct, public IP)
```

- **`vscode`** — `FROM isaaclab_arena:latest` plus code-server 4.96.4. A small shim hands
  off to Arena's own entrypoint, which recreates your host user inside the container (so
  bind-mounted files keep the right ownership), grants passwordless sudo, and applies the
  image's shell aliases before starting code-server. The shim exists only to create that
  user's home directory first: Arena's entrypoint runs `useradd` without `-m` and then
  chowns `/home/$USER`, which fails when your username is not `ubuntu` — the only home
  directory the Isaac Sim base image ships. Arena's entrypoint itself is untouched, so
  upstream changes to it keep flowing through.

  VS Code extensions are baked into `/opt/code-server/extensions` rather than a home
  directory, because that user does not exist until the container starts.
- **`nginx`** — OpenResty reverse proxy, from `isaac-launchable` with one change: the
  `/sign_in` signaling proxy targets **8011**, not upstream's 49100. Isaac Sim 6.0.1 /
  Kit 110 binds its WebRTC signaling server to 8011; 49100 is dead in this version.
  Confirm on a running instance with `ss -tulpn | grep kit`.
- **`web-viewer`** — the NVIDIA WebRTC sample app, copied verbatim from `isaac-launchable`.
  Its entrypoint patches the signaling and media server addresses at every start, so the
  stack survives an instance reboot picking up a new public IP.

`build.sh` builds in two steps: `isaaclab_arena:latest` straight from
`IsaacLab-Arena/docker/Dockerfile.isaaclab_arena` (unmodified, with the same build args as
Arena's own `run_docker.sh`), then the three compose images. Upstream Arena changes flow
through by pulling the Arena clone and rebuilding — there is no forked copy of its install
logic to maintain.

### Why `WORKDIR=/workspaces/isaaclab_arena` matters

Arena's Dockerfile defaults to `/workspace`, but installs its packages editable. The bind
mount and the `WORKDIR` build arg must be the same absolute path or the editable installs
point at a directory the mount has shadowed. `build.sh` and `docker-compose.yml` both use
`/workspaces/isaaclab_arena`, matching Arena's `run_docker.sh`. Change one, change both.

## Differences from `run_docker.sh`

The container keeps Arena's Isaac Sim requirements (`--privileged`, `--ipc=host`,
`--net=host`, unlimited memlock/stack, `runtime: nvidia`) but drops things that only make
sense on a developer laptop:

- No X11 / `DISPLAY` mounts — this is a headless cloud host, and streaming replaces them.
- No Docker socket, SSH agent or `~/.config/gh` mounts. Mounting the Docker socket into a
  container reachable from a browser is a privilege-escalation path, so it is not shipped.
- `CUDA_VISIBLE_DEVICES` is not pinned to `0` (unlike the upstream launchable), because
  Arena's distributed evaluation needs every GPU visible.

## Optional: cuRobo

The `ik_reachable` reachability validator needs cuRobo, which is not built by default
(it compiles CUDA extensions, ~10 extra minutes):

```bash
INSTALL_CUROBO=true ./build.sh
```

## Repository layout

```
build.sh                  two-step build (Arena image, then launchable images)
setup.sh                  the Brev setup script
docker-compose.yml        the three services
docker-compose.override.yml   build contexts (omit for a prebuilt-image deploy)
vscode/                   code-server layer + the in-browser README
nginx/                    reverse proxy          (from isaac-launchable; signaling port changed)
web-viewer-sample/        WebRTC viewer          (verbatim from isaac-launchable)
```

## Licence

Apache 2.0. The `web-viewer-sample/` directory is an unmodified copy from
[isaac-sim/isaac-launchable](https://github.com/isaac-sim/isaac-launchable); `nginx/` is
the same but for the signaling port noted above.
