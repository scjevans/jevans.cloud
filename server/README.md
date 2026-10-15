# Media server

Jellyfin plus the "arr" apps, all in Docker, with downloads locked inside a VPN.

## What each piece does

Think of it as a small restaurant:

| App | Port | Job | In the kitchen |
| --- | ---- | --- | -------------- |
| **Jellyfin** | 8096 | Plays your library on TVs, phones, browsers | The dining room |
| **Sonarr** | 8989 | Watches for TV episodes you want, sends them to be fetched, files them | The TV menu manager |
| **Radarr** | 7878 | Same job for movies | The movie menu manager |
| **Prowlarr** | 9696 | Keeps your list of indexers (search sites) and shares it with Sonarr/Radarr | The supplier phone book |
| **Bazarr** | 6767 | Finds subtitles for what Sonarr/Radarr filed | The translator |
| **qBittorrent** | 8080 | Does the actual downloading | The delivery van |
| **Gluetun** | | A VPN tunnel that qBittorrent and Prowlarr live inside | A sealed tunnel the van must drive through |
| **Homepage** | 3000 | One page showing every app, whether it's running, and a link to open it | The board by the kitchen door |
| **Caddy** | 80, 443 | Lets the outside world reach Jellyfin (and nothing else) over HTTPS | The host at the front door |

### Why the tunnel matters

qBittorrent and Prowlarr don't have their own network connection at all. They borrow Gluetun's
(`network_mode: service:gluetun` in the compose file). So if the VPN drops, they have **no**
internet, rather than quietly falling back to your normal connection. That's the kill switch,
and it's built into the plumbing instead of being a setting you could forget to tick.

What your ISP sees: encrypted traffic to a VPN server, not what's inside it or which sites
it goes to. They can still tell you're using a VPN, and Jellyfin, Sonarr, Radarr and Bazarr
use your normal connection (they only fetch artwork, metadata and subtitles).

## The folder layout

Everything shares one `/data` folder, on one drive:

```
/data
├── torrents        qBittorrent downloads land here
│   ├── movies
│   └── tv
└── media           your tidy library, what Jellyfin shows
    ├── movies
    └── tv
```

Because downloads and library are on the same drive, Sonarr/Radarr can **hardlink** a finished
download into the library. A hardlink is like a second label on the same box: the file shows up
in both places, takes the space once, appears instantly, and qBittorrent can keep seeding it.
If they were on different drives, every file would be copied, doubling the space.

## Setup

You need a Linux machine (Ubuntu is easiest), with Docker installed:
[docs.docker.com/engine/install](https://docs.docker.com/engine/install/). Run the commands below on that machine.

### 1. Get the files

```sh
git clone https://github.com/scjevans/jevans.cloud.git
cd jevans.cloud/server
```

### 2. Make the folders

```sh
sudo mkdir -p /data/torrents/{movies,tv} /data/media/{movies,tv} /opt/media/config
sudo chown -R $USER:$USER /data /opt/media
```

If you have a big second drive, mount it at `/data` first (or point `DATA_DIR` at it in step 3).

### 3. Fill in your settings

```sh
cp .env.example .env
nano .env
```

Every line has a comment explaining it. For the VPN lines, download a **WireGuard** config file
from your VPN provider's website; the private key and address are in it. The VPN provider must
be one [Gluetun supports](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers).

### 4. Start it

```sh
docker compose up -d
```

Check the tunnel came up:

```sh
docker logs gluetun | tail -20
docker exec gluetun wget -qO- https://ipinfo.io
```

The second command should show the VPN server's country and IP, not your home one.

### 5. Connect the apps to each other

Open each app in a browser at `http://<server-ip>:<port>`. The containers find each other by the
addresses below, not `localhost` (each container is its own little computer).

**qBittorrent** (`:8080`)
1. The first-run password is printed in the logs: `docker logs qbittorrent`. Log in as `admin`
   with it, then change it under Tools → Options → Web UI.
2. Options → Downloads: set the default save path to `/data/torrents`.
3. Options → Advanced → Network interface: choose `tun0`. (A belt-and-braces second kill switch.)

**Sonarr** (`:8989`) and **Radarr** (`:7878`)
1. Settings → Media Management → Add Root Folder: `/data/media/tv` (Sonarr) or `/data/media/movies` (Radarr).
   Leave "Use Hardlinks instead of Copy" on.
2. Settings → Download Clients → + → qBittorrent: Host `gluetun`, Port `8080`, your qBittorrent
   login, Category `tv` (Sonarr) or `movies` (Radarr).
3. Settings → General: copy the **API Key**, you'll need it for Prowlarr.

**Prowlarr** (`:9696`)
1. Indexers → Add Indexer: add the sites you use.
2. Settings → Apps → + Sonarr: Prowlarr Server `http://gluetun:9696`,
   Sonarr Server `http://172.30.0.11:8989`, paste Sonarr's API key.
3. Same for Radarr: Radarr Server `http://172.30.0.12:7878`.

Prowlarr is inside the tunnel, so it reaches Sonarr/Radarr by their fixed address instead of name.

If an indexer fails with "blocked by CloudFlare Protection": Settings → Indexers → + → FlareSolverr,
Host `http://localhost:8191`, Tags `flaresolverr`. Then edit the blocked indexer, give it the same
`flaresolverr` tag, and Test again. FlareSolverr shares the tunnel with Prowlarr, which is why it's `localhost`.

**Bazarr** (`:6767`)
1. Settings → Sonarr: Address `sonarr`, Port `8989`, API key. Settings → Radarr: Address `radarr`, Port `7878`.
2. Settings → Languages and Providers: pick your languages and a subtitle source or two.

**Jellyfin** (`:8096`)
1. Follow the setup wizard. Add libraries: Shows → `/data/media/tv`, Movies → `/data/media/movies`.

### 6. The dashboard

Open `http://<server-ip>:3000`. Each app gets a tile with a green "running" badge (red if stopped),
its CPU and memory use, and a click-through to open it. The top strip shows the server's CPU,
memory and how full `/data` is.

Homepage learns what's running from a small helper, `dockerproxy`, rather than from Docker directly.
Docker's control socket is like a master key to the whole server; the helper is a doorman who will
answer "what's running?" but refuses to start, stop or create anything.

To change the dashboard, edit the files in `homepage/` (`services.yaml` holds the tiles). It reloads
on its own, just refresh the page. If the page says "Host validation failed", `SERVER_IP` in `.env`
doesn't match the address you typed in the browser.

### 7. Make Jellyfin reachable from outside

This puts Jellyfin at `https://media.jevans.cloud`, so you (and anyone you give an account) can watch
away from home, and the website's status light on channels 2 and 3 turns ON AIR.

Caddy (in the compose file) is the front door. Think of your router as the building's front gate
and Caddy as the receptionist behind it: the gate sends every web visitor to the receptionist,
who checks they asked for `media.jevans.cloud` and walks them to Jellyfin. The other apps have no
door to the street at all; they stay home-only.

Caddy also fetches the padlock (the HTTPS certificate) from Let's Encrypt by itself and renews it
before it runs out. Its settings are one short file: `caddy/Caddyfile`.

**a. Point the name at your house (DNS).** At whoever manages DNS for `jevans.cloud` (where you
added the GitHub Pages records), add one record:

| Type | Name | Value | TTL |
| ---- | ---- | ----- | --- |
| `A` | `media` | your home's public IP | 5 min (or the lowest offered) |

Your public IP is what `curl -4 ifconfig.me` prints on the server. It is **not** `192.168.1.95`,
that's the address inside your home. If your DNS host is Cloudflare, set the record to
"DNS only" (grey cloud): streaming video through Cloudflare's free proxy breaks their terms.

Leave the existing `jevans.cloud` records alone; the website stays on GitHub Pages.

**b. Open the gate (port forwarding).** On the Fios router (`http://192.168.1.1`), find Port Forwarding
(under Firewall, or Advanced → Security & Firewall on newer routers). Add two rules, both to `192.168.1.95`:

| Application | Protocol | Port |
| ----------- | -------- | ---- |
| Custom: `caddy-https` | TCP and UDP | 443 → 443 |
| Custom: `caddy-http` | TCP | 80 → 80 |

Forward **only** these two. Never forward 8096, 8989, 8080 or the others. (Port 80 is only for
getting the certificate; if Verizon blocks it, Caddy manages over 443 alone.)

**c. Start Caddy.**

```sh
cd ~/jevans.cloud/server
git pull
docker compose up -d
docker logs caddy 2>&1 | grep -i certificate
```

Look for `certificate obtained successfully`. If it complains instead, wait a few minutes for
the DNS record to spread and run `docker restart caddy`.

**d. Tell Jellyfin about its receptionist.** In Jellyfin: Dashboard → Networking → Known proxies,
add `172.30.0.20` and save, then `docker restart jellyfin`. Without this, Jellyfin thinks every
visitor is Caddy, so it can't tell home viewers from away ones (for streaming limits) or log who
tried a wrong password.

**e. Check it.** On your phone with Wi-Fi off, open `https://media.jevans.cloud`. You should get the
Jellyfin login. Then open `https://jevans.cloud/#3`: it should say ON AIR with your server's name.

**Before you share it**, give every Jellyfin account a strong password, and in Dashboard → Users
untick "Allow remote connections" for any account that only ever watches at home.

**If your public IP changes.** Fios addresses rarely change, but they can (after a long outage or a
new router). If the site goes OFF AIR while Jellyfin works at home, compare `curl -4 ifconfig.me`
with the `A` record and update it.

**If it works on mobile data but not on home Wi-Fi**, your router isn't looping the request back
inside. Nothing's broken: use `http://192.168.1.95:8096` at home.

**Why not Tailscale Funnel?** Funnel would avoid the port forwarding, but it only serves addresses
ending in `.ts.net`, so it can't answer at `media.jevans.cloud`, which is what the website checks.
It also caps bandwidth, which video quickly hits. Plain Tailscale (no Funnel) is still a good
private way in for you alone, if you'd rather not open any ports.

## Everyday commands

```sh
docker compose ps              # what's running
docker compose logs -f sonarr  # watch one app's log (Ctrl+C to stop)
docker compose pull && docker compose up -d   # update everything
docker compose down            # stop everything (your settings and files stay)
```

## When something's wrong

- **qBittorrent/Prowlarr won't open:** the VPN probably isn't up. `docker logs gluetun` usually says
  why, most often a mistyped key or address in `.env`.
- **Can't open qBittorrent/Prowlarr from another device at home:** check `LAN_SUBNET` in `.env` matches
  your network, then `docker compose up -d` again.
- **Sonarr/Radarr copy files instead of hardlinking:** downloads and library must be on the same drive,
  under the same `DATA_DIR`.
- **Permission errors:** `PUID`/`PGID` in `.env` must match the owner of `/data` (`id` shows yours).
