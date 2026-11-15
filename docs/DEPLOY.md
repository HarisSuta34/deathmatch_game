# Deploying Block Deathmatch for free

The game has two parts:

| Part | What it is | Where it goes |
|---|---|---|
| **Client** | The web export (`build/web`), plain static files | GitHub Pages (or itch.io) |
| **Server** | Headless Godot running this project, speaks WebSocket | A host that can run a Docker container or a Linux program |

Players open the client link; the client connects to the server address stored in
`scripts/config.gd` (`PRODUCTION_URL`). Because GitHub Pages is **https**, the server
address must be **wss://** (encrypted WebSocket). All options below give you that.

Order of work: **1) put the server online → 2) put its address in the client → 3) publish the client.**

---

## 1. Server — pick one option

Hosting offers change often. These were checked in **November 2026**; confirm the current
terms on the provider's own page when you sign up.

| | A. Render (free web service) | B. Your own PC + Cloudflare quick tunnel | C. Oracle Cloud "Always Free" VM |
|---|---|---|---|
| Cost | Free | Free | Free |
| Account / card | Account needed. Render says no card is required, but some users report being asked for one as verification | **No account, no card** | Account **and credit card** required (not charged) |
| Always on? | Sleeps after 15 min with nobody connected; first player then waits ~1 min | Only while your PC and the two programs are running | Yes, 24/7 |
| Address | Fixed: `wss://<name>.onrender.com` | **Changes every time** you restart the tunnel | Fixed, but you must set up a hostname + HTTPS yourself |
| Setup effort | Low (about 10 minutes, all in the browser) | Low | High (Linux server administration) |
| Limits | 0.1 CPU / 512 MB, 750 h per month, monthly outbound bandwidth cap (a full 20-player match uses roughly 150 MB, a 4-player match under 10 MB) | Your home internet upload speed; quick tunnels are meant for testing | Generous |
| Best for | **Recommended**: a permanent link you can share | Trying it with friends tonight | A serious, always-on server later |

Ruled out: Fly.io (no free tier any more), Koyeb (free compute tier no longer offered to new
users / card hold), Hugging Face Docker Spaces (need a paid plan since 2026), Railway (trial credit only).

### Option A — Render (recommended)

The repository already contains a `Dockerfile` that Render can build directly from GitHub.
It was tested locally: the container starts in a few seconds and uses about 35 MB of memory.

1. Create an account at <https://render.com> (signing in with GitHub is easiest).
2. **New → Web Service** → connect your GitHub repository `deathmatch_game`.
3. Settings:
   - **Language / Runtime:** Docker (detected from the `Dockerfile`)
   - **Branch:** `main`
   - **Instance type:** **Free**
   - Leave everything else at its default. Do not set a start command. Render provides the
     `PORT` variable and the server listens on it automatically.
4. Click **Deploy**. Wait until the log shows `Server listening on port ...`.
5. Your server address is the service URL with `https` replaced by `wss`, e.g.
   `https://block-deathmatch.onrender.com` → **`wss://block-deathmatch.onrender.com`**.

Notes:
- Render redeploys automatically whenever you push to `main`. A redeploy ends running matches.
- When the server is asleep, the menu shows "Connecting to the server..." for up to a minute. That is normal.
- Opening the https URL in a browser shows an error page — expected, it only speaks WebSocket.

### Option B — your own PC + Cloudflare quick tunnel

1. Download `cloudflared` for Windows from
   <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/> (no account needed).
2. Start the game server in a terminal in this folder:
   `tools\godot.ps1 --headless --path . ++ --server`
3. In a second terminal: `cloudflared tunnel --url http://localhost:9080`
4. It prints an address like `https://random-words.trycloudflare.com`. Your server address is
   **`wss://random-words.trycloudflare.com`**.
5. Because this address changes on every restart, don't bake it into the client. Share a link
   with the address attached instead:
   `https://<you>.github.io/deathmatch_game/?server=wss://random-words.trycloudflare.com`

(Not yet tested with this game: Cloudflare tunnels support WebSockets, but try it with a friend before relying on it.)

### Option C — Oracle Cloud Always Free VM (outline)

1. Create an Always Free Ubuntu VM (Ampere or AMD micro shape) and open TCP ports 80 and 443 in its security list.
2. Get a free hostname that points at the VM's public IP (for example from DuckDNS).
3. On the VM install Docker, clone this repository, then:
   `docker build -t bdm-server . && docker run -d --restart=always -p 127.0.0.1:9080:10000 bdm-server`
4. Install Caddy and run it as a reverse proxy; it obtains the HTTPS certificate automatically:
   `caddy reverse-proxy --from your-name.duckdns.org --to localhost:9080`
5. Server address: **`wss://your-name.duckdns.org`**.

Alternative to Docker on a VM: `tools\export.ps1` also produces `build\server\server.x86_64` + `server.pck`
(Linux dedicated-server export). Copy both files to the VM and run `./server.x86_64 --headless -- --server --port=9080`.

---

## 2. Tell the client where the server is

Open `scripts/config.gd` and set:

```gdscript
const PRODUCTION_URL := "wss://block-deathmatch.onrender.com"   # your address from step 1
```

How the client chooses the address:
1. `?server=wss://...` in the page link, if present;
2. otherwise `PRODUCTION_URL`, when the page is not opened from localhost;
3. otherwise `ws://localhost:9080` (local testing).

The address is also shown in the small **Server** box at the bottom of the main menu and can be edited there.

---

## 3. Client — GitHub Pages

1. In a terminal in this folder run: `tools\publish_web.ps1`
   It exports the web build and pushes it to the `gh-pages` branch of your repository
   (the branch is replaced each time, so it always holds just the latest build).
2. One time only, on GitHub: **repository → Settings → Pages → Build and deployment →
   Source: "Deploy from a branch" → Branch: `gh-pages`, folder `/ (root)` → Save.**
   (On a free GitHub account the repository must be public for Pages.)
3. After a minute or two the game is live at `https://<your-github-name>.github.io/deathmatch_game/`.
   Share that link.

Re-run `tools\publish_web.ps1` whenever you change the game or the server address.
The export is single-threaded, so it needs no special server headers.

### Alternative: itch.io

1. Run `tools\export.ps1`, then zip the **contents** of `build\web` (so `index.html` is at the top of the zip; leave out the `.import` files).
2. On itch.io create a new project, **Kind of project: HTML**, upload the zip and tick
   "This file will be played in the browser". Set the viewport to 1280 × 720 and enable the fullscreen button.
3. "SharedArrayBuffer support" is **not** needed.

---

## Testing before you deploy

- Desktop, several windows: `tools\play_local.ps1 2` (dev server + 2 game windows).
- Browser version locally: `tools\serve_web.ps1` (dev server + local web server, opens `http://localhost:8060`).
- The dev server (`--dev`) lets the host start with any number of players. A real server
  (no `--dev`, as in the Dockerfile) enforces the even 4–20 rule.

## Troubleshooting

| Problem | Likely cause |
|---|---|
| "Could not reach the server" immediately | Wrong address, or `ws://` used on an https page — it must be `wss://` |
| Long "Connecting..." then it works | Free server was asleep (Render) |
| Mouse does not lock after spawning | Browsers require a click: click the game once ("Click to play") |
| Game is slow in the browser | Close other tabs; use Chrome/Edge/Firefox with hardware acceleration enabled |
| Players lag when many are online | Free CPU limit of the server; fewer players per room, or move to option C |
