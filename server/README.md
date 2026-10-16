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
| **Seerr** | 5055 | Where people ask for a movie or show; approved asks go to Sonarr/Radarr | The order counter |
| **Bazarr** | 6767 | Finds subtitles for what Sonarr/Radarr filed | The translator |
| **qBittorrent** | 8080 | Does the actual downloading (torrents) | The delivery van |
| **SABnzbd** | 8085 | Downloads from Usenet, if you add it (step 20) | The courier from a private warehouse |
| **Gluetun** | | A VPN tunnel that qBittorrent and Prowlarr live inside | A sealed tunnel the van must drive through |
| **Homepage** | 3000 | One page showing every app, whether it's running, and a link to open it | The board by the kitchen door |
| **Caddy** | 80, 443 | Lets the outside world reach Jellyfin and Seerr (and nothing else) over HTTPS | The host at the front door |
| **AdGuard Home** | 53, 3001 | Answers "where is this website?" for every device at home, and says "nowhere" for ads and trackers | The bouncer with a short list of known troublemakers |
| **Jellystat** | 3002 | Keeps a diary of everything watched on Jellyfin: who, what, when, how long | The waiter's notebook of who ordered what |
| **Grafana** | 3003 | Charts of the server's health: CPU, memory, drives, temperature, and what each app uses | The gauges on the kitchen wall: oven temperature, fridge, gas |
| **Vaultwarden** | (via Caddy) | Your passwords, served to the official Bitwarden apps and browser extensions | The safe in the back office |
| **MySpeed** | 5216 | Tests your home internet speed every hour and keeps a history of the results | The scale by the back door that weighs every delivery |
| **XMLTV** | | Fetches the TV guide (what's on each channel, and when) for Jellyfin's Live TV (step 22) | The paperboy with the TV listings |

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
├── usenet          SABnzbd downloads land here (step 20)
│   ├── incomplete
│   └── complete
│       ├── movies
│       └── tv
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
sudo mkdir -p /data/torrents/{movies,tv} /data/usenet/incomplete /data/usenet/complete/{movies,tv} /data/media/{movies,tv} /opt/media/config
sudo chown -R $USER:$USER /data /opt/media
mkdir -p /opt/media/config/seerr && sudo chown 1000:1000 /opt/media/config/seerr
mkdir -p /opt/media/config/grafana /opt/media/config/prometheus /opt/media/config/xmltv/guide
```

Seerr always runs as user 1000 inside its container, so its folder belongs to 1000 whatever your own ID is.

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

**Seerr** (`:5055`), after Jellyfin is set up
1. Choose **Jellyfin** as your server type. Jellyfin URL: Hostname `jellyfin`, Port `8096`, no SSL.
   Sign in with your Jellyfin admin account; that account becomes Seerr's admin too.
2. Sync libraries, tick Movies and Shows, then Continue.
3. Add a Radarr server: Hostname `radarr`, Port `7878`, Radarr's API key, Test, then pick the
   quality profile and root folder `/data/media/movies`. Tick **Default Server**.
4. Add a Sonarr server the same way: Hostname `sonarr`, Port `8989`, root folder `/data/media/tv`,
   **Default Server** ticked.
5. Settings → Users → Import Jellyfin Users, so your family can sign in with their Jellyfin logins.
   Requests from people other than you wait for your approval unless you give them "Auto-Approve"
   (Users → edit a user → Permissions).

### 6. The dashboard

Open `http://<server-ip>:3000` (or `https://home.jevans.cloud` once you've done step 9). Each app gets a tile with a green "running" badge (red if stopped),
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

### 8. Make Seerr reachable from outside

Do step 7 first. This adds a second door, `https://requests.jevans.cloud`, so people can ask for
movies and shows from anywhere. The router gate is already open, so it only needs a name and a restart.

**a. DNS.** Add one more record next to `media`, with the same value:

| Type | Name | Value | TTL |
| ---- | ---- | ----- | --- |
| `A` | `requests` | your home's public IP | 5 min (or the lowest offered) |

**b. Restart Caddy** so it reads the new door and fetches its certificate:

```sh
cd ~/jevans.cloud && git pull
cd server && docker compose up -d && docker restart caddy
docker logs caddy 2>&1 | grep -i requests.jevans.cloud
```

**c. Tell Seerr it's behind a receptionist.** In Seerr: Settings → General, set Application URL to
`https://requests.jevans.cloud`, tick **Enable Proxy Support**, and save. Like Jellyfin's known
proxy, this lets Seerr see each visitor's real address instead of Caddy's, and makes the links in
its notifications point at the outside address.

**d. Check it.** On your phone with Wi-Fi off, open `https://requests.jevans.cloud` and sign in with
a Jellyfin account. Anyone who can sign in to Jellyfin can sign in here, which is another reason
every Jellyfin account needs a strong password.

### 9. A friendly address for the dashboard (home only)

This puts the dashboard at `https://home.jevans.cloud` instead of `http://192.168.1.95:3000`. It is
**not** reachable from outside: Caddy checks where each visitor comes from and hangs up on anyone who
isn't on your home network. (Why not `jevans.cloud/homepage`? `jevans.cloud` itself lives on GitHub's
servers, not yours, so a path on it can't reach your house. A sub-name like `home.` can.)

**a. DNS.** Add one more record next to `media`, with the same value:

| Type | Name | Value | TTL |
| ---- | ---- | ----- | --- |
| `A` | `home` | your home's public IP | 5 min (or the lowest offered) |

This is only so Caddy can get the HTTPS padlock for the name; outside visitors still get turned away.

**b. Restart the dashboard and Caddy:**

```sh
cd ~/jevans.cloud && git pull
cd server && docker compose up -d && docker restart caddy
docker logs caddy 2>&1 | grep -i home.jevans.cloud
```

**c. Point your computer at the server directly.** The Fios router can't loop a request for your own
public address back inside (the same reason `media.jevans.cloud` needed this). Add this line to your
hosts file, next to the `media.jevans.cloud` one:

```
192.168.1.95  home.jevans.cloud
```

On Windows that file is `C:\Windows\System32\drivers\etc\hosts` (open Notepad as administrator);
on a Mac or Linux it's `/etc/hosts` (`sudo nano /etc/hosts`). Phones can't do this, so on a phone keep
using `http://192.168.1.95:3000`.

**d. Check it.** Open `https://home.jevans.cloud` on that computer. On your phone with Wi-Fi off, the
same address should fail to load: that's the lock working.

### 10. Block ads and trackers for the whole house

Every time a phone, TV or laptop opens a website, it first asks a **DNS server** "what's the address
for this name?", like looking a number up in a phone book. AdGuard Home becomes your house's phone
book. For a short list of known ad and tracking names it answers "no such number", so the ad never
loads. Everything else gets the real answer. Nobody has to install anything on their device.

**How strict is it?** Mild on purpose. It uses one list, the **AdGuard DNS filter**, which is built to
block ads and trackers without breaking sites. It blocks far less than the aggressive lists people
stack up, so normal browsing, shopping, streaming apps and sign-ins keep working. It won't catch
everything (YouTube ads, for example, come from the same names as the videos, so DNS can't split them).

**a. Start it.** Ubuntu already runs its own small DNS helper on `127.0.0.53`, so AdGuard only listens
on the server's home address (`192.168.1.95`). They sit side by side without a fight.

```sh
cd ~/jevans.cloud && git pull
cd server && docker compose up -d
docker logs adguard 2>&1 | tail -5
```

If it says `address already in use` for port 53, run `sudo ss -lunp 'sport = :53'` and tell me what's
listed.

**b. The setup page.** Open `http://192.168.1.95:3001` and click through:

- **Admin web interface:** listen on *All interfaces*, port **3000** (not the suggested 80).
  Inside the box it's 3000; from your network it's 3001, the same "door number swap" the compose file
  does for the other apps.
- **DNS server:** *All interfaces*, port **53**.
- Make a username and a strong password, then sign in at `http://192.168.1.95:3001`.

**c. Keep the list mild.** Filters → DNS blocklists: leave **AdGuard DNS filter** on and turn off
anything else that's ticked. Settings → DNS settings: the default upstream (Quad9, encrypted) is
fine. It also means your ISP no longer sees the list of sites the house looks up, which suits this
project.

**d. Teach it your own names (bonus).** Filters → DNS rewrites → Add, once for each:

| Domain | Answer |
| ------ | ------ |
| `media.jevans.cloud` | `192.168.1.95` |
| `requests.jevans.cloud` | `192.168.1.95` |
| `home.jevans.cloud` | `192.168.1.95` |
| `vault.jevans.cloud` | `192.168.1.95` |

The Fios router can't loop your public address back inside, which is why you needed hosts-file lines
and `:8096` addresses at home. With these rewrites, the phone book just gives home devices the
server's inside address, so the nice names work at home on every device, phones included.

**e. Test it on one device first.** Before touching the router, from your PC:

```sh
nslookup doubleclick.net 192.168.1.95       # should answer 0.0.0.0 (blocked)
nslookup wikipedia.org 192.168.1.95         # should answer a real address
nslookup media.jevans.cloud 192.168.1.95    # should answer 192.168.1.95
```

**f. Hand it to the whole house.** In the Fios router (`http://192.168.1.1`): My Network → Network
Connections → **Network (Home/Office)** → Edit → Settings. Find **DNS Server**, choose *Use the
following DNS Server addresses*, and enter:

- **Primary:** `192.168.1.95`
- **Secondary:** `1.1.1.1`

Apply. Devices pick up the new phone book when they reconnect to Wi-Fi (or within a day on their own).
The menus move a little between Fios router models; the setting you're after is the DNS server the
router hands out to your devices. If you can only find a DNS setting under **Broadband Connection**,
that works too: the router then asks AdGuard for everyone, so the AdGuard log shows every request as
coming from `192.168.1.1` instead of from each device.

**What if the server is off?** That's what the secondary is for. If AdGuard doesn't answer, devices
quietly ask `1.1.1.1` instead, so the internet keeps working for everyone, just with ads. The cost:
some devices also use the secondary now and then when the server is fine, so a few ads slip through,
and on those moments `home.jevans.cloud` may fail to load on a phone. For a shared house, "always
works, catches most ads" beats "catches every ad, breaks the internet when the server reboots". If
you'd rather be strict, leave the secondary blank, and remember: server down means no websites for
anyone at home until it's back or you undo this step.

**g. When a site breaks.** Someone says a link or an app won't load:

1. In AdGuard, open **Query Log** and filter by *Blocked*. Look for names from around that time that
   belong to the broken site (a shopping site's checkout, a link-tracking name in an email, and so on).
2. Click the row and choose **Unblock**. That adds an allow line for just that name, like
   `@@||click.example.com^`, under Filters → Custom filtering rules. You can add them there by hand too.
3. Try again. The fix is instant for new lookups; if the device still fails, turn its Wi-Fi off and on.

To switch the blocking off for the whole house in one click (handy while you're finding the culprit),
use **Disable protection** on the AdGuard home page; it can turn itself back on after a set time.

**Undo it entirely:** set the router's DNS back to automatic. Every device goes back to Verizon's DNS.

### 11. Watch statistics (Jellystat)

Jellyfin's own dashboard only shows what's playing right now. Jellystat is the waiter's notebook: it
writes down every play (who, what, which device, how long) so you can look back at the most-watched
shows, who watches the most, and when the house watches. It's home only, at `http://192.168.1.95:3002`.

It keeps its notebook in a small database (Postgres) in its own container, `jellystat-db`. That
database sits on a private line only Jellystat can use: no internet and no port on your network.

**a. Get the new files.**

```sh
cd ~/jevans.cloud && git pull
```

**b. Make its two secrets.** Jellystat needs a database password and a "JWT secret" (the stamp it puts
on login tickets so nobody can forge one). These two lines invent long random ones and add them to
your `.env`. Run each once:

```sh
echo "JELLYSTAT_DB_PASSWORD=$(openssl rand -hex 24)" >> ~/jevans.cloud/server/.env
```

```sh
echo "JELLYSTAT_JWT_SECRET=$(openssl rand -hex 32)" >> ~/jevans.cloud/server/.env
```

You never need to read or type them. Don't run them twice: if you did, open `.env` with `nano` and
delete the extra lines at the bottom before going on.

**c. Start it.**

```sh
cd ~/jevans.cloud/server && docker compose up -d
```

```sh
docker logs jellystat 2>&1 | tail -10
```

Give it a minute the first time while the database sets itself up.

**d. Make a Jellyfin API key.** This is a key card Jellystat uses to read Jellyfin's records. In Jellyfin:
Dashboard → API Keys → **+**, name it `Jellystat`, and copy the key it shows.

**e. Connect them.** Open `http://192.168.1.95:3002`:

1. Create a Jellystat username and password (this is just for Jellystat, not Jellyfin).
2. Jellyfin URL: `http://jellyfin:8096`. API key: paste the one from step d. Save.
3. Settings → Tasks: run **Full Sync** once, so it reads in your libraries and Jellyfin's past plays.

From then on it checks Jellyfin on its own every few minutes. Use the plain `http://jellyfin:8096`, not
`https://media.jevans.cloud`: the two containers talk inside the server and never leave the house.

**Want history from before today?** Jellyfin only keeps a short activity log. If you install Jellyfin's
**Playback Reporting** plugin (Dashboard → Plugins → Catalog), Jellystat can import its history under
Settings → Tasks → Import Playback Reporting Data. Optional.

### 12. Jellyfin Enhanced (extra features inside Jellyfin)

[Jellyfin Enhanced](https://github.com/n00bcodr/Jellyfin-Enhanced) is a plugin, which is like an app
for your Jellyfin server rather than for the computer. Nothing changes in the compose file: you install
it from Jellyfin's own plugin store, and it's saved in Jellyfin's config folder, so it survives updates.
Once it's in, everyone who uses Jellyfin gets quality badges on posters (4K, HDR, Atmos), Seerr requests
from Jellyfin's search, Spoiler Guard, a release calendar, bookmarks and more. Press `?` anywhere in
Jellyfin to switch features on or off for yourself.

It needs Jellyfin 10.11 or newer (Dashboard → the version is shown at the bottom). If it's older, update
Jellyfin first with `docker compose pull jellyfin && docker compose up -d jellyfin`.

**a. Add the two plugin stores.** In Jellyfin: Dashboard → Plugins → **Repositories** → **+**, twice:

| Name | URL |
| ---- | --- |
| `File Transformation` | `https://www.iamparadox.dev/jellyfin/plugins/manifest.json` |
| `Jellyfin Enhanced` | `https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/manifest.json` |

File Transformation is a helper. Jellyfin Enhanced works by adding a few lines to Jellyfin's web page,
and inside Docker that page file is read-only. The helper lets it add those lines as the page is sent
out, instead of editing the file. Without it you'd see `Access to the path ... index.html is denied`.

**b. Install File Transformation first.** Catalog → **File Transformation** → Install. Then restart:

```sh
docker restart jellyfin
```

**c. Install Jellyfin Enhanced.** Catalog → **Jellyfin Enhanced** → Install, then `docker restart jellyfin`
again. Refresh the browser with Ctrl+F5 and press `?`: if the Enhanced panel opens, it worked.

**d. Connect it to the other apps (optional).** Dashboard → Plugins → **Jellyfin Enhanced**. It talks to
them from inside the server, so use the container names, like Seerr and Jellystat do:

| App | URL | API key from |
| --- | --- | ------------ |
| Seerr | `http://seerr:5055` | Seerr: Settings → General → API Key |
| Sonarr | `http://sonarr:8989` | Sonarr: Settings → General → API Key |
| Radarr | `http://radarr:7878` | Radarr: Settings → General → API Key |

Seerr adds requests from Jellyfin's search; Sonarr and Radarr fill the calendar and download progress.
Each section has a **Test** button. For ratings, streaming availability and reviews, it also asks for a
free TMDB API key (from themoviedb.org → Settings → API), which is optional.

### 13. Intro Skipper (a "Skip Intro" button)

[Intro Skipper](https://github.com/intro-skipper/intro-skipper) is another Jellyfin plugin. It listens to
every episode of a season, finds the stretch of music they all share (the theme tune), and marks it as
the intro, the way you'd spot the same opening bars on every track of an album. Jellyfin then offers a
**Skip Intro** button, or skips it for you. It finds end credits and recaps too.

**a. Add its plugin store.** Dashboard → Plugins → **Repositories** → **+**:

| Name | URL |
| ---- | --- |
| `Intro Skipper` | `https://intro-skipper.org/manifest.json` |

(Opening that address in a browser shows nothing. That's normal: it only answers Jellyfin, with the
build that matches your Jellyfin version.)

**b. Install it.** Catalog → **Intro Skipper** → Install, then:

```sh
docker restart jellyfin
```

**c. Let it listen.** Dashboard → **Scheduled Tasks** → run **Detect and Analyze Media Segments**. The
first run goes through your whole TV library, so it can take a while; after that it only checks new
episodes. A season needs at least two episodes before it can find the shared theme.

**d. Choose what happens at an intro.** Each person picks for themselves in Jellyfin: their profile →
**Playback** → *Media segment actions*, set **Intro** to *Ask to skip* (shows the button) or *Skip*
(skips by itself). Jellyfin Enhanced's auto-skip (step 12) uses the same markers.

### 14. Media Bar (a big slideshow on the home page)

[Media Bar](https://github.com/IAmParadox27/jellyfin-plugin-media-bar) turns the top of Jellyfin's home
page into a rotating banner, like the one on Netflix: full-width artwork, the title's logo, a short
description and a Play button, with trailers if you want them.

It comes from the same plugin store as File Transformation (step 12a), and it needs File Transformation
to add itself to the page, so do step 12a and 12b first. Use Media Bar 3.x for Jellyfin 12; the
catalog offers the build that matches your Jellyfin.

**a. Install it.** Dashboard → Plugins → Catalog → **Media Bar** → Install, then:

```sh
docker restart jellyfin
```

**b. Refresh.** Open Jellyfin's home page and press Ctrl+Shift+R (twice if needed). The bar shows at the
top. Ignore the guide's step about editing `index.html`: File Transformation does that part for you.

**c. Pick what it shows.** Click the gear on the bar to choose libraries, trailers and timing. These
choices are saved in each browser, so each person and device sets their own.

To turn trailers off for everyone, Dashboard → Plugins → **Media Bar** → untick **Enable Trailers?** →
**Save**. That server setting wins over the gear, so trailers stay off even for someone who switches them
back on there.

**Bar doesn't appear?** Open the browser's developer tools (F12) → **Network** → tick **Disable cache**,
then refresh with the tools still open. If Media Bar isn't in the catalog at all, it hasn't caught up to
your Jellyfin version yet; check again after its next release.

### 15. Abyss theme (a new look for Jellyfin)

[Abyss](https://github.com/AumGupta/abyss-jellyfin) is a theme: a dark, glassy, rounded look. It's just
CSS, the styling rules that decide colours and shapes, like a new coat of paint that leaves the house's
walls alone. Jellyfin loads it from the internet each time a page opens, so there's nothing to install
on the server, and deleting the lines puts the old look straight back.

**a. Paste the theme.** Dashboard → **Branding** → **Custom CSS**, paste these lines, then **Save**:

```css
@import url('https://cdn.jsdelivr.net/gh/AumGupta/abyss-jellyfin@main/abyss.css');
@import url('https://cdn.jsdelivr.net/gh/AumGupta/abyss-jellyfin@main/styles/abyss-je.css');
@import url('https://cdn.jsdelivr.net/gh/AumGupta/abyss-jellyfin@main/styles/abyss-mbe.css');
```

The first line is the theme. The other two restyle Jellyfin Enhanced (step 12) and the Media Bar (step
14) to match. The Media Bar one was written for a sister version of the plugin, so if the bar looks
worse with it, delete that line.

**b. Use the dark base.** Your profile → **Display** → Theme: **Dark**, and tick **Show backdrops**.
Abyss is built on top of the dark theme. Then refresh with Ctrl+F5.

**Optional extras**, pasted below the lines above:

- A lighter version for phones and TVs (less blur and animation):
  `@import url('https://cdn.jsdelivr.net/gh/AumGupta/abyss-jellyfin@main/styles/abyss-lite.css');`
- A different accent colour, for example soft blue (the same colour written two ways, both are needed):
  `:root { --abyss-accent: 100, 160, 255; --abyss-accent-channel: 100 160 255; }`

Skip the theme's "Spotlight" add-on and its installer. Spotlight is its own home-page slideshow, which
Media Bar already does, and it works by editing files inside the Jellyfin container that are replaced
on every update.

### 16. Server health charts (Grafana)

Homepage tells you whether each app is running. Grafana tells you *how the server is doing*, and how it
was doing last Tuesday at 9pm. Think of a car: the engine has sensors, a logbook writes down what they
read every 30 seconds, and the dashboard turns the logbook into gauges and charts. Here that's four
containers:

| Container | Car part | What it does |
| --------- | -------- | ------------ |
| `node-exporter` | Engine sensors | Reads the PC itself: CPU, memory, how full each drive is, temperatures, network |
| `cadvisor` | Sensors on each passenger | Reads every container: how much CPU, memory and network each app uses |
| `prometheus` | The logbook | Asks both sensors for their numbers every 30 seconds and keeps 30 days of them |
| `grafana` | The dashboard | Draws the charts. The only one you open: `http://192.168.1.95:3003` |

It's home only, like Jellystat: no Caddy site and no port forwarding, so nobody outside the house can
see it. Grafana comes already plugged into Prometheus, with a ready-made **Media server** dashboard (it's
in `grafana/dashboards/server.json`), so there's nothing to wire up.

**a. Get the new files.**

```sh
cd ~/jevans.cloud && git pull
```

**b. Make its folders.** Grafana and Prometheus run as you, so they need folders you own. If Docker made
them instead, they'd belong to root and the two apps couldn't save anything.

```sh
mkdir -p /opt/media/config/grafana /opt/media/config/prometheus
```

**c. Make a password.** This adds a random password for Grafana's `admin` login to your `.env`. Run it once:

```sh
echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 12)" >> ~/jevans.cloud/server/.env
```

Then show it, so you can copy it for the first login:

```sh
grep GRAFANA ~/jevans.cloud/server/.env
```

**d. Start it.**

```sh
cd ~/jevans.cloud/server && docker compose up -d
```

```sh
docker compose ps grafana prometheus node-exporter cadvisor
```

All four should say `Up` (or `running`).

**e. Open it.** Go to `http://192.168.1.95:3003`, log in as `admin` with the password from step c. It
opens on the **Media server** dashboard. Give it a few minutes: charts need a few readings before they
draw a line. What's on it:

- **Top row:** CPU, memory, both drives, the hottest temperature sensor, and how long since the last
  restart. Green is fine, orange means keep an eye on it, red means look now.
- **The server:** CPU and memory over time, network traffic, drive activity (`sda` is the system SSD,
  `sdb` the media drive), and free space.
- **The apps:** CPU, memory, download and upload per container. Downloads show up under `gluetun`,
  because qBittorrent borrows its connection. Jellyfin's upload going up means someone is streaming.

Change the time range top right (Last 6 hours, Last 7 days...). Click a name under a chart to show
just that app.

**Want more detail?** Grafana's community shares dashboards you can add in a few clicks. The most
popular one for the server itself is **Node Exporter Full**: Dashboards → **New** → **Import**, type
`1860`, **Load**, pick **Prometheus** at the bottom, **Import**. It has a page for nearly every number
the server reports.

The **Media server** dashboard comes from the repo, so changes you make to it in the browser are
replaced the next time Grafana restarts. To build your own, use **New** → **New dashboard**, or on
the Media server dashboard use **Save as** to make your own copy.

### 17. Your own password safe (Vaultwarden)

**What it is.** Bitwarden is a password manager, like LastPass. It comes in two halves: the **apps**
(browser extension, phone app, desktop app) and the **server** that keeps your vault and keeps every
device in sync. Vaultwarden is a home-made copy of that server half. The official Bitwarden apps
can't tell the difference, so you get Bitwarden's polished apps with your passwords living in your
house instead of someone else's data centre.

Think of it like a bank's safe-deposit box, except the box is in your own back office and only you
have the key. The key is your **master password**: your vault is scrambled with it *on your device*
before it is ever sent, so the server only ever stores scrambled data. Even someone who stole the
server's drive couldn't read your passwords without it.

**Where it can be reached.** Home only, like the dashboard: `https://vault.jevans.cloud`. Caddy hangs
up on anyone who isn't on your home network, and Vaultwarden has no port of its own. When you're out,
the apps still show every password (they keep a scrambled copy on the device and open it with your
master password); they just can't save new ones or sync until you're home again. If you later want
full syncing away from home, ask: Tailscale (a private tunnel only your own devices can use) is the
safe way to do that. Opening a password safe to the whole internet isn't.

**How it's locked down.** Layers, like a bank: the vault is home-only, the box it runs in is locked
(it runs as you rather than as the all-powerful `root` user, can't change its own files, and can only
write to its vault folder), sign-ups are closed, the admin page is switched off when you're not using
it, password hints are hidden, and it doesn't fetch website logos (which would tell your ISP which
sites you have accounts with). On your account you add two-step login and the stronger Argon2id
password scrambling. Your master password is the last and most important layer.

**a. DNS.** One more record next to `home`, same value, for the same reason (so Caddy can get the
HTTPS padlock; the Bitwarden apps refuse to connect without it):

| Type | Name | Value | TTL |
| ---- | ---- | ----- | --- |
| `A` | `vault` | your home's public IP | 5 min (or the lowest offered) |

Then in AdGuard (`http://192.168.1.95:3001`): Filters → DNS rewrites → Add `vault.jevans.cloud` →
`192.168.1.95`, so every device at home, phones included, finds it. On your PC, if it uses the hosts file
rather than AdGuard, add `192.168.1.95  vault.jevans.cloud` there too (see step 9c).

**b. Make the admin password.** Vaultwarden has a settings page at `/admin`. Its password is stored
*scrambled* (a "hash"), so even someone reading your `.env` can't learn it. Run this, type a new
password twice (it's for the settings page only, **not** your master password; save it in your password
manager later):

```sh
cd ~/jevans.cloud && git pull
docker run --rm -it vaultwarden/server /vaultwarden hash
```

It prints a line starting `ADMIN_TOKEN='$argon2id$...`. Open `.env` (`nano ~/jevans.cloud/server/.env`)
and add these two lines at the bottom, pasting everything from the first `'` to the last `'` after the
`=` on the second line:

```
VAULTWARDEN_SIGNUPS_ALLOWED=true
VAULTWARDEN_ADMIN_TOKEN='$argon2id$v=19$m=65540,t=3,p=4$...the rest of the line...'
```

Keep the single quotes: without them Docker reads every `$` as the start of a setting name and mangles it.

**c. Start it and make your account.** First give it a folder you own (it runs as you, not root; the
`chown` also fixes the folder if Docker already made it as root):

```sh
mkdir -p /opt/media/config/vaultwarden && sudo chown -R $USER:$USER /opt/media/config/vaultwarden
cd ~/jevans.cloud/server && docker compose up -d && docker restart caddy
docker logs vaultwarden 2>&1 | tail -5
```

Open `https://vault.jevans.cloud` on your PC → **Create account**. Pick a **master password** you've
never used anywhere: a few random words strung together (`maple-orbit-cactus-lantern`) is strong and
memorable. Write it down on paper and keep it somewhere safe at home. **Nobody can reset it**, not
you, not me, not the admin page. Lose it and the vault is gone for good.

**d. Close the sign-up door.** Now that your account exists, stop anyone else making one. In `.env`
change `VAULTWARDEN_SIGNUPS_ALLOWED=true` to `false`, then:

```sh
docker compose up -d vaultwarden
```

**e. Switch the admin page off.** You don't need it day to day, and a page that doesn't exist can't
be broken into. In `.env`, empty the token line so it reads just `VAULTWARDEN_ADMIN_TOKEN=`, then
`docker compose up -d vaultwarden`. `https://vault.jevans.cloud/admin` now says the page is disabled.
Want to give someone in the house their own vault later? Run step b again to put a token back, use
`/admin` → Users → **Invite User**, then empty the line again. You never need to reopen sign-ups.

**f. Lock your account down.** In the web vault, click your avatar (top right) → **Account settings**
→ **Security**:

- **Two-step login** → **Authenticator app**. Scan the code with an authenticator app on your phone
  (Aegis, 2FAS, Google or Microsoft Authenticator). Now a stolen master password alone isn't enough.
  Save the **recovery code** it shows on the same paper as your master password. If you own a hardware
  key like a YubiKey, add it here too under **Passkey / FIDO2 WebAuthn**: it's the strongest option.
- **Keys** → **KDF algorithm**: change it to **Argon2id** (keep the suggested numbers) and save. This
  is how hard your master password is to guess-and-check if someone ever got a copy of the vault:
  Argon2id makes every guess cost a lot of memory as well as time, which cripples password-cracking
  hardware. It signs you out; sign back in.

**g. Bring your passwords over from LastPass.**

> ⚠️ The file LastPass gives you is every password you own **in plain, readable text**. Treat it
> like cash left on the table. Never email it, never upload it, never paste it into a chat (including
> this one), and never put it in this repo. Do this on your own PC and delete the file as soon as the
> import is done.

1. Sign in at [lastpass.com](https://lastpass.com) → **Advanced Options** (bottom left) → **Export**.
   It asks for your LastPass master password, and it may email you to confirm first: click the link,
   then Export again. It downloads `lastpass_export.csv`.
2. In your new vault at `https://vault.jevans.cloud`: **Tools** → **Import data**. File format:
   **LastPass (csv)**. Choose the file, click **Import data**.
3. Check it: the count should roughly match LastPass, and LastPass folders become Bitwarden folders.
   Open a few logins and secure notes and make sure they're right.
4. **Delete the CSV** from your Downloads folder, then empty the Recycle Bin.

What doesn't come across: file attachments (download any from LastPass by hand and add them to the
items) and sharing with other people. Keep your LastPass account for a few weeks until you're sure
nothing is missing, then close it.

**h. Connect the Bitwarden apps.** Install the official Bitwarden extension in your browser and the
Bitwarden app on your phone. On the sign-in screen, before typing anything:

- Find **Logging in on: bitwarden.com** (or **Accessing**) and change it to **self-hosted**.
- **Server URL:** `https://vault.jevans.cloud`. Save.
- Sign in with your email and master password.

Phone at home with Wi-Fi on: it works because AdGuard points the name at the server. Then turn off
LastPass's autofill (disable or remove its extension) so the two don't fight over the same login boxes.

In each app's **Settings** → **Account security**: set **Vault timeout** to 15 minutes (or *On system
lock* on the PC) and **Timeout action** to **Lock**. On the phone, turn on **Unlock with biometrics**
so locking often isn't a chore. A locked app is a closed safe even if someone picks up your device.

**i. Back it up.** Your whole vault is one folder: `/opt/media/config/vaultwarden`. If that drive died
without a copy, so would every password. This makes a dated copy, pausing the safe for a few seconds so
the copy isn't caught mid-write:

```sh
cd ~/jevans.cloud/server && docker compose stop vaultwarden
sudo tar czf ~/vaultwarden-$(date +%F).tar.gz -C /opt/media/config vaultwarden
docker compose start vaultwarden
```

Then copy that file **off the server** (a USB stick, your PC): a backup on the same machine dies with
it. Everything in it is still scrambled with your master password, so a strong master password keeps it
safe; still keep the stick somewhere private, like you would a spare house key. Do it
after the import and every so often after that (or ask me to set up a nightly one). As an extra
safety net, the web vault's **Tools** → **Export vault** → **.json (Encrypted)** makes a password-locked
copy you could import into any Bitwarden.

### 18. Internet speed history (MySpeed)

Your provider promises a speed. MySpeed checks whether you get it: every hour it runs a speed test
(download, upload and ping) and writes the result down, like a bathroom scale that weighs you on a
timer. After a few days you can see the pattern: whether evenings are slower, or a bad day was the line
and not Jellyfin. It's home only, at `http://192.168.1.95:5216`.

It runs **outside** the VPN on purpose. Speed-testing through the tunnel would measure Mullvad's server
in another city, not your Fios line. A speed test is ordinary traffic your ISP sees every day from
millions of homes, so it gives nothing away.

**a. Get the new files and start it.**

```sh
cd ~/jevans.cloud && git pull
```

```sh
cd ~/jevans.cloud/server && docker compose up -d
```

```sh
docker compose ps myspeed
```

It should say `Up` (or `running`).

**b. Open it.** Go to `http://192.168.1.95:5216`. The first time, it asks a few questions:

1. **Which speed test to use.** Pick **Ookla** (the speedtest.net one) and accept its terms. That's the
   same test your ISP and most people use, so the numbers compare fairly.
2. **Which server.** Leave it on automatic: it picks a nearby one.

It runs its first test straight away, then every hour on its own.

**c. Optional tweaks** (the gear icon top right):

- **How often:** each test uses your full speed for about 20 seconds. Hourly is fine on Fios (no data
  cap), but if a test ever makes a film stutter, change the frequency to every 3 or 6 hours.
- **Password:** you can skip it, since only devices at home can open the page. If you set one, the
  numbers on the dashboard tile stop showing until the password is added there too (ask me).

The dashboard's **MySpeed** tile (under Home network) shows the latest download, upload and ping.

### 19. Keep films and shows in English

Prowlarr is only the phone book: it asks every indexer "who has this film?" and passes back every
answer, Italian dubs included. Sonarr and Radarr are the ones that pick which answer to download, and
out of the box they judge only on picture quality, not on language. So an Italian copy (`ITA`) or a
dual-audio one (`MULTi`) that happens to be the best quality wins. A dual-audio file then plays
Italian because Italian is marked as its default track, and Jellyfin plays the default track unless
you tell it which language you want.

**a. Make Jellyfin pick the English track** (fixes files you already have that contain English)

Each person does this in their own account, on the web or in an app:
1. Profile picture (top right) → **Settings** → **Playback**.
2. **Preferred audio language**: English.
3. Untick **Play default audio track regardless of language**, then **Save**.

**b. Make Radarr turn down non-English downloads**

1. Settings → **Custom Formats** → **+** → name it `Not English`.
2. **+** under Conditions → **Language** → Language `English`, tick **Negate**, Save. Save again.
   ("Negate" flips it: the label goes on any release that is *not* English.)
3. Settings → **Profiles** → open each quality profile you use:
   - In the custom formats list at the bottom, give `Not English` a score of `-10000`.
   - **Minimum Custom Format Score**: `0`. Anything wearing the `Not English` label now scores
     below zero and is skipped, like a shop that won't take a delivery with the wrong label.
   - **Language**: English. Tick **Upgrades Allowed**, then Save.

Dual-audio releases that include English still get through, which is fine: step a makes them play
in English.

**c. Same for Sonarr**

Repeat b in Sonarr. Its profiles have no Language box, so skip that line; the custom format does
the job on its own.

**d. Swap out the Italian copies you already have**

In Radarr: **Wanted** → **Cutoff Unmet** → **Search All**. The Italian-only films now score below
your profile's target, so Radarr looks for an English copy and replaces them. In Sonarr, open the
show, check the episode's language on the **Files** tab, and press the search (magnifier) button on
any Italian ones. If one still won't upgrade, delete that file and search again.

**e. Check the phone book**

In Prowlarr's **Indexers** list, look at the language column. If a site is Italian (or any language
you don't want), delete it there; it only ever offers Italian releases.

Watching a foreign film in its own language with subtitles? This setup blocks those too. For a
one-off, open the film in Radarr, pick **Interactive Search** (the person icon), and grab the release
yourself; a manual pick ignores the score.

### 20. Usenet (a second way to download)

Torrents are like swapping at a flea market: you trade pieces with strangers, and everyone there can
see you. Usenet is a private warehouse you pay to use. You download straight from the warehouse's
servers and never upload to anyone. It's usually faster, and new episodes are often there sooner.

It takes three pieces:

| Piece | What it is | Examples |
| ----- | ---------- | -------- |
| **Provider** | The warehouse. Paid, roughly $3 to $10 a month | Newshosting, Eweka, Frugal Usenet |
| **Indexer** | The catalogue that says where each file is kept. Some are free with limits | NZBGeek, DrunkenSlug, NZBFinder |
| **SABnzbd** | The courier that fetches the files. Already in the stack | |

**Does it need the VPN?** No. SABnzbd talks to the provider over SSL, so your ISP sees encrypted
traffic going to a Usenet company and can't see what's inside. Searches still go through Prowlarr,
inside the tunnel, so the indexer only ever sees the VPN.

**a. Sign up** with one provider and one indexer. From the provider, note the **server address**,
your **username** and **password**, and how many **connections** you're allowed. From the indexer,
copy your **API key** (usually on your profile or API page).

**b. Get the new files and start it.**

```sh
cd ~/jevans.cloud && git pull
```

```sh
sudo mkdir -p /data/usenet/incomplete /data/usenet/complete/{movies,tv} && sudo chown -R $USER:$USER /data/usenet
```

```sh
cd ~/jevans.cloud/server && docker compose up -d
```

**c. Set up SABnzbd** at `http://192.168.1.95:8085`. The first-run wizard asks for your provider:

1. Host: the provider's server address. Username and password: yours.
2. Tick **SSL**, port **563**. Connections: the number your plan allows (8 to 20 is plenty).
3. Click **Test Server**, then Next. On the folders page, put `/data/usenet/incomplete` for
   temporary downloads and `/data/usenet/complete` for completed ones.

Then, in the gear icon (Config):

- **Categories:** make sure `movies` and `tv` exist, with folder `movies` and `tv`. Save.
- **General:** copy the **API Key**. Sonarr and Radarr need it.

**d. Tell Sonarr and Radarr about it.** In each: Settings → Download Clients → + → **SABnzbd**.
Host `172.30.0.19`, Port `8080` (the inside number, not 8085), paste the API key, Category `tv`
(Sonarr) or `movies` (Radarr). Test, then Save.

**e. Add the indexer to Prowlarr** (`:9696`): Indexers → Add Indexer, search its name, paste your
API key, Test, Save. Prowlarr passes it to Sonarr and Radarr on its own, as with your torrent sites.

**f. Optional: try Usenet first.** In Sonarr and Radarr: Settings → Profiles → Delay Profiles → edit
the default one and set Preferred Protocol to **Usenet**. They'll still use torrents when Usenet
doesn't have something.

When a download finishes, Sonarr and Radarr move it into `/data/media`. It's on the same drive, so
the move is instant. Nobody needs to seed a Usenet file, so the copy in `usenet/complete` goes away.

The dashboard's **SABnzbd** tile is under Download.

### 22. Live TV with a TV guide (XMLTV)

Jellyfin can play live TV channels too, and show a grid of what's on, like a cable box. That
takes two things, and they're separate jobs:

| Piece | Job | Like |
| ----- | --- | ---- |
| **A tuner** | Brings the actual channels in | The TV aerial |
| **A guide** | Says what's on each channel, and when | The TV listings page in the newspaper |

**XMLTV** is the guide half. It's a set of small programs called *grabbers*, one per listings
source, that fetch the schedule and write it into one file, `guide.xml`. The `xmltv` container
runs the grabber every 12 hours and leaves the file where Jellyfin can read it. XMLTV brings no
channels by itself: without a tuner, there's nothing for the guide to describe.

**The tuner.** Fios TV's own channels are locked to Verizon's boxes, so they can't feed Jellyfin.
The usual choices:

- **An antenna + an HDHomeRun** (a small box from SiliconDust, around $100 to $180). It turns
  free over-the-air channels (ABC, CBS, NBC, FOX, PBS and so on, in HD) into streams on your home
  network. This is what Schedules Direct, below, has listings for.
- **An M3U playlist** from an internet TV service. Free ones like Pluto TV or Samsung TV Plus
  usually come with their own guide link, so they don't need XMLTV at all.

**The listings source.** In the US the grabber is `tv_grab_zz_sdjson`, which reads
[Schedules Direct](https://www.schedulesdirect.org): a small non-profit that sells listings to
hobbyists, about $35 a year, with a free 7-day trial. It knows every antenna and cable lineup by
ZIP code. (Jellyfin can also read Schedules Direct directly. Going through XMLTV keeps the guide
in a plain file you can check, and lets you swap to another grabber later without touching Jellyfin.)

**a. Sign up** at schedulesdirect.org. Note your username and password.

**b. Get the new files and build the container.** It's built here from Debian's XMLTV package,
using the `xmltv/` folder next to the compose file.

```sh
cd ~/jevans.cloud && git pull
```

```sh
mkdir -p /opt/media/config/xmltv/guide
```

```sh
cd ~/jevans.cloud/server && docker compose build xmltv
```

**c. One-time setup.** This asks questions in the terminal:

```sh
docker compose run --rm xmltv tv_grab_zz_sdjson --configure
```

1. Cache file: press Enter for the default.
2. Username and password: your Schedules Direct ones.
3. When it asks about lineups, add one: choose to search by country, type `USA`, then your ZIP code, and pick
   **Antenna** (called "Local Over the Air Broadcast") from the list.
4. Then choose to take all channels in the lineup. For the formats it asks about, press Enter for the defaults.

The answers are saved in `/opt/media/config/xmltv/.xmltv/`. Your password is in there, so the
folder stays on the server and isn't in git.

**d. Start it and check the first fetch:**

```sh
docker compose up -d
```

```sh
docker logs -f xmltv
```

Wait for `Guide updated` (the first fetch takes a minute or two), then Ctrl+C. The guide is now at
`/opt/media/config/xmltv/guide/guide.xml`, and Jellyfin sees the same file as `/xmltv/guide.xml`.

**e. In Jellyfin:** Dashboard → Live TV.

1. **Tuner Devices → +.** For an HDHomeRun, pick HD Homerun and type its address, like
   `http://192.168.1.50` (find it in your router's device list). Jellyfin can't find it on its own
   from inside Docker, for the same reason it needs the discovery relay. For a playlist, pick M3U
   Tuner and paste its link.
2. **TV Guide Data Providers → + → XMLTV.** File or URL: `/xmltv/guide.xml`. Save.
3. If some channels show no guide, click the provider's **Map Channels** and match each tuner
   channel to its guide channel by number.
4. Dashboard → Scheduled Tasks → **Refresh Guide** → run. After that, Jellyfin re-reads the file on its own.

Live TV then appears on the home page, with a **Guide** tab. You can also record shows from the
guide; recordings go to the folder set under Live TV → DVR.

**Updates:** the container is built here rather than downloaded, so `docker compose pull` skips
it. Every few months, rebuild it with the latest XMLTV from Debian:

```sh
docker compose build --pull xmltv && docker compose up -d xmltv
```

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
- **Sonarr/Radarr say they can't reach SABnzbd:** use Host `172.30.0.19` and Port `8080`. The name
  `sabnzbd` gets "Hostname verification failed" unless you add it under SABnzbd's Config → Special →
  host_whitelist.
- **Can't open qBittorrent/Prowlarr from another device at home:** check `LAN_SUBNET` in `.env` matches
  your network, then `docker compose up -d` again.
- **Grafana's top-row and "The server" charts say "No data", but the per-app ones work:** Prometheus
  can't reach node-exporter. Run `sudo ufw status`: if it says `active`, let containers in with
  `sudo ufw allow from 172.16.0.0/12 to any port 9100`.
- **Grafana or Prometheus keeps restarting with "permission denied":** their folder belongs to root.
  `sudo chown -R $USER:$USER /opt/media/config/grafana /opt/media/config/prometheus`, then
  `docker compose up -d`.
- **Jellyfin apps at home don't list the server on their own:** check the finder is running with
  `docker logs jellyfin-discovery`, and `sudo ufw allow 7359/udp` if `sudo ufw status` says `active`.
  The server they find is `https://media.jevans.cloud`, which works at home thanks to AdGuard's DNS
  rewrites (step 10d). You can always type `http://192.168.1.95:8096` in the app instead.
- **Bitwarden app says it can't reach the server, or a certificate error:** check you're on home
  Wi-Fi, that the app's server URL is exactly `https://vault.jevans.cloud`, and that
  `nslookup vault.jevans.cloud 192.168.1.95` answers `192.168.1.95` (step 17a's DNS rewrite). If the
  browser shows `SSL_ERROR_INTERNAL_ERROR_ALERT`, Caddy has no certificate yet: the `vault` DNS record
  is missing, or Caddy needs `docker restart caddy`.
- **The admin page says "Invalid admin token":** you're typing the password you chose in step 17b,
  not the long `$argon2id...` line. If it never works, the `.env` line probably lost its single quotes.
  If it says the page is disabled, that's step 17e working: put a token back first.
- **Vaultwarden keeps restarting with "permission denied" or "read-only file system":** its folder
  belongs to root. `sudo chown -R $USER:$USER /opt/media/config/vaultwarden`, then
  `docker compose up -d vaultwarden`.
- **MySpeed tests fail or show far below your plan:** check `docker logs myspeed`. If every test
  fails, AdGuard may be blocking the speed test site: in AdGuard (`http://192.168.1.95:3001`) open
  **Query log**, search `speedtest`, and click **Unblock** on any red line. One slow result is normal;
  a slow pattern at the same hour usually means someone is busy downloading then.
- **Sonarr/Radarr copy files instead of hardlinking:** downloads and library must be on the same drive,
  under the same `DATA_DIR`.
- **Permission errors:** `PUID`/`PGID` in `.env` must match the owner of `/data` (`id` shows yours).
- **Websites stop loading for everyone at home:** AdGuard is down and the router has no secondary
  DNS. `docker compose up -d adguard`, or set the router's DNS back to automatic. If `docker logs
  adguard` says it `cannot assign requested address`, the server started Docker before it had its
  network address: `docker compose up -d adguard` again fixes it.
