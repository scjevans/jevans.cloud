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
| **JellyDash** | 3002 | Shows what's playing right now and keeps a diary of everything watched on Jellyfin: who, what, when, how long | The waiter's notebook of who ordered what |
| **Beszel** | 3003 | Charts of the server's health (CPU, memory, drives, temperature, and what each app uses), and alerts on your phone when disk, heat or memory cross a line | The gauges on the kitchen wall, with an alarm on the fridge |
| **Uptime Kuma** | 3004 | Checks every app and the server's health each minute, and sends a push notification to your phone when something breaks (step 22) | The night manager who phones you if the freezer stops |
| **Vaultwarden** | (via Caddy) | Your passwords, served to the official Bitwarden apps and browser extensions | The safe in the back office |
| **MySpeed** | 5216 | Tests your home internet speed every hour and keeps a history of the results | The scale by the back door that weighs every delivery |
| **SyncTube** | 4200 | Watch parties: everyone sees the same YouTube video (or video link) at the same moment, with a chat (step 24) | The projectionist who starts the film for every table at once |

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
mkdir -p /opt/media/config/beszel/data /opt/media/config/beszel/socket /opt/media/config/beszel-agent
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

### 11. Watch statistics (JellyDash)

Jellyfin's own dashboard only shows what's playing right now. [JellyDash](https://github.com/themartz90/jellydash)
is the waiter's notebook: it writes down every play (who, what, which device, how long, direct play or
transcode) so you can look back at the most-watched shows, who watches the most, and when the house
watches. It also has a live "Now playing" page and can ping your phone when someone presses play.
It's home only, at `http://192.168.1.95:3002`.

It keeps its notebook in one small file (a SQLite database) in `/opt/media/config/jellydash/data`, so
unlike Jellystat it needs no separate database container. Think of it as a paper notebook in a drawer
instead of a filing cabinet with its own clerk.

**Coming from Jellystat?** JellyDash takes over Jellystat's address (port 3002), so bookmarks and the
Homepage tile keep working. Jellystat's history can't be copied across (the two keep different kinds of
notebook), but its folder stays on the drive until you delete it in step g. JellyDash *can* read
history from Jellyfin's **Playback Reporting** plugin, see step f.

**a. Stop Jellystat.** Do this *before* pulling, while the compose file still knows about it:

```sh
cd ~/jevans.cloud/server && docker compose rm -sf jellystat jellystat-db
```

(`rm -sf` means stop the container and remove it, without asking. Its data folder isn't touched.)

**b. Get the new files.**

```sh
cd ~/jevans.cloud && git pull
```

**c. Make a Jellyfin API key.** This is a key card JellyDash uses to read Jellyfin's records. In Jellyfin:
Dashboard → API Keys → **+**, name it `JellyDash`, and copy the key it shows. Then add it to `.env`,
pasting the key in place of `PASTE-KEY-HERE`:

```sh
echo "JELLYDASH_JELLYFIN_API_KEY=PASTE-KEY-HERE" >> ~/jevans.cloud/server/.env
```

**d. Make your JellyDash login.** JellyDash has its own login, separate from Jellyfin's. Pick a username
(here `jack`), and let the second line invent a long random password:

```sh
echo "JELLYDASH_ADMIN_USER=jack" >> ~/jevans.cloud/server/.env
```

```sh
echo "JELLYDASH_ADMIN_PASSWORD=$(openssl rand -hex 12)" >> ~/jevans.cloud/server/.env
```

Then see the password, so you can save it in Vaultwarden:

```sh
grep JELLYDASH_ADMIN_PASSWORD ~/jevans.cloud/server/.env
```

Run each `echo` once. If you ran one twice, open `.env` with `nano` and delete the extra line at the
bottom. Want Seerr requests in JellyDash too? Add `JELLYDASH_SEERR_API_KEY=` with Seerr's key (Seerr:
Settings → General → API Key) the same way. Optional.

**e. Start it.**

```sh
cd ~/jevans.cloud/server && docker compose up -d
```

```sh
docker logs jellydash 2>&1 | tail -10
```

You should see `starting background workers`. Open `http://192.168.1.95:3002` and sign in with the
username and password from step d. There's no setup wizard: it already knows where Jellyfin is
(`http://jellyfin:8096`, inside the server) from the compose file. From now on it checks Jellyfin every
30 seconds, even when nobody has the page open.

**f. History from before today (optional).** JellyDash only sees plays from the moment it starts. If you
installed Jellyfin's **Playback Reporting** plugin for Jellystat, that plugin has been keeping its own
history: open JellyDash → History → **Import history** → **Import from server plugin**. It counts the
plays first and asks before saving anything. Not installed? Install it now (Dashboard → Plugins →
Catalog → Playback Reporting) and it's a second notebook from today on.

**Phone alerts (optional).** JellyDash can send "Jack started watching The Office" through ntfy, the
same app Uptime Kuma uses (step 22). Pick a *different* hard-to-guess topic name from Uptime Kuma's, add
`JELLYDASH_NTFY_TOPIC=your-topic-name` to `.env`, run `docker compose up -d`, and subscribe to that
topic in the ntfy app. Anyone who knows the topic name can read it, so make it random.

**g. Delete Jellystat for good (once you're happy).** Nothing here is needed by JellyDash. These remove
Jellystat's folder (its notebook and database), its two downloaded images, and its old private network:

```sh
sudo rm -rf /opt/media/config/jellystat
```

```sh
docker image rm cyfershepard/jellystat postgres:15 ; docker network prune -f
```

Then open `.env` with `nano` and delete the two `JELLYSTAT_...` lines. Also delete the old `Jellystat`
key in Jellyfin (Dashboard → API Keys).

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
them from inside the server, so use the container names, like Seerr and JellyDash do:

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

### 16. Server health charts and alerts (Beszel)

Homepage tells you whether each app is running. Beszel tells you *how the server is doing*, how it was
doing last Tuesday at 9pm, and buzzes your phone when a number crosses a line. Think of a fitness tracker:
a sensor on your wrist takes the readings, and an app on your phone keeps the history, draws the charts
and nudges you when your heart rate is too high. Here that's two containers:

| Container | Fitness-tracker part | What it does |
| --------- | -------------------- | ------------ |
| `beszel-agent` | The wristband | Reads the PC itself (CPU, memory, both drives, temperatures, network) and every container (how much CPU, memory and network each app uses) |
| `beszel` | The phone app | Keeps the history, draws the charts, sends the alerts. The only one you open: `http://192.168.1.95:3003` |

It's home only, like JellyDash: no Caddy site and no port forwarding, so nobody outside the house can
see it (away from home, Tailscale gets you in, step 22h). The two talk through a small file on the
server (a "socket"), a bit like a pneumatic tube between two rooms, so the agent doesn't open a port either.
Together they use a fraction of the memory the old Grafana + Prometheus set did.

**a. Get the new files and start the hub.**

```sh
cd ~/jevans.cloud && git pull && mkdir -p /opt/media/config/beszel/data /opt/media/config/beszel/socket /opt/media/config/beszel-agent
```

```sh
cd ~/jevans.cloud/server && docker compose up -d beszel
```

If you had Grafana before, that says `port is already allocated`: Grafana still holds 3003. Stop the
four old containers first, then run the line above again:

```sh
docker rm -f grafana prometheus node-exporter cadvisor
```

**b. Make your login.** On a computer at home, open `http://192.168.1.95:3003` and make an account
(email and password; save them in Vaultwarden). The email is only a username: nothing is sent to it.

**c. Add the server.** Click **Add System** top right, and fill in:

- **Name:** `jevans-server`
- **Host / IP:**

  ```
  /beszel_socket/beszel.sock
  ```

Leave the box open. It shows a `docker-compose.yml` with two lines you need: `KEY` (starts with
`ssh-ed25519`) and `TOKEN`. In another window, on the server, add them to your `.env` (it's your own
copy, so `git pull` didn't add these lines). Run this, paste the KEY when it asks, and press Enter:

```sh
cd ~/jevans.cloud/server && read -p "KEY: " k && echo "BESZEL_AGENT_KEY='$k'" >> .env
```

Then the same for the TOKEN:

```sh
read -p "TOKEN: " t && echo "BESZEL_AGENT_TOKEN=$t" >> .env
```

`grep BESZEL .env` should show both lines, the key inside single quotes. Then start the agent, and the
new Homepage tile:

```sh
docker compose up -d --remove-orphans && docker compose restart homepage
```

Back in the browser, click **Add System** in the box. The server turns green within a minute.
(`--remove-orphans` clears out anything else the compose file no longer lists; step g tidies up after
Grafana.)

**d. Look around.** Click **jevans-server**. Charts need a few minutes of readings before they draw a line.

- **Top:** CPU, memory, disk, network, temperatures, and how long since the last restart.
- **Disk:** the system SSD, plus a separate **Media** chart for the media drive, each with free space
  and read/write speed. If **Media** shows space but no read/write speed, run `lsblk` on the server:
  the media drive's partition (the one mounted at `/data`) probably isn't called `sdb1`. Change `sdb1`
  in `docker-compose.yml` to its name and `docker compose up -d beszel-agent`.
- **Docker:** CPU, memory and network per container. Torrent traffic shows up under `gluetun`, because
  qBittorrent and Prowlarr borrow its connection. Jellyfin's upload going up means someone is streaming.

Change the time range top right (1 hour up to 30 days).

**e. Tell it about your phone.** Beszel sends alerts to the same ntfy channel as Uptime Kuma (step 22c).
If you've lost your topic name, it's in the ntfy app, and in Uptime Kuma under Settings →
Notifications → My phone. In Beszel click your account top right → **Settings** → **Notifications** →
**Add URL**, and paste this with your topic at the end:

```
ntfy://ntfy.sh/jevans-3f9a1c0e7b2d4a56?priority=high
```

Click **Test URL** (your phone should buzz), then **Save Settings**.

**f. Set the alarm lines.** Back on the main page, click the bell 🔔 on the **jevans-server** row and
turn these on:

| Alert | Set it to | Means |
| ----- | --------- | ----- |
| **Status** | on | The agent stopped reporting |
| **Disk Usage** | `90%` | The SSD or the media drive is over 90% full |
| **Memory Usage** | `95%` | Less than 5% of memory is free |
| **Temperature** | `85°C` | The hottest sensor (CPU or drive) is over 85°C |

Leave the time at 1 minute, so a short spike doesn't wake you. You get a second message when it's back
to normal. These replace the "Drives", "Temperatures" and "Memory" checks Uptime Kuma used to do.
Whether the media drive is *plugged in* at all stays with Uptime Kuma (step 22e), because Beszel can
only tell you how full a drive is, not that it's gone.

**g. If you had Grafana before: tidy up.** Its charts, logins and history were in two folders that are
no longer used. Delete them, and the four old programs:

```sh
sudo rm -rf /opt/media/config/grafana /opt/media/config/prometheus
```

```sh
docker image rm grafana/grafana prom/prometheus prom/node-exporter ghcr.io/google/cadvisor:v0.60.6
```

If you ever opened port 9100 in the firewall for Grafana, close it again:
`sudo ufw delete allow from 172.16.0.0/12 to any port 9100`. And remove `GRAFANA_ADMIN_PASSWORD`
from `.env` with `nano ~/jevans.cloud/server/.env`.

In Uptime Kuma, delete the four "health" monitors that asked Prometheus (**Drives under 90% full**,
**Media drive plugged in**, **Temperatures OK**, **Memory OK**): click each → **Delete**. Then follow
step 22e's new "Is the media drive plugged in?" part, and add `beszel` and `beszel-agent` as two more
Docker Container monitors.

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

### 21. Netflix-style rows (Action, Comedy, Oscar winners)

Out of the box, Jellyfin's home page is like a video shop with one shelf per library: "Latest Movies",
"Latest Shows". These steps add themed shelves you scroll sideways, like Netflix: a row per genre,
"Because you watched...", hidden gems, and an Oscar winners row.

Two plugins do it, both installed from Jellyfin's plugin store like steps 12 to 14:

- **Home Screen Sections** rebuilds the home page out of rows you pick. Its **Genre** row picks a
  handful of genres (Action, Comedy, Thriller...) weighted towards what each person watches, so a
  comedy fan sees more comedy shelves. It reads genres that Jellyfin already downloaded for every film,
  so there's nothing to tag by hand.
- **Jellyfin Oscars** looks up every film's Oscar history and keeps an **Oscar Winners** collection
  up to date. Jellyfin doesn't store awards on its own, which is why this one is needed.

**a. Install Home Screen Sections.** It lives in the same store as File Transformation and Media Bar
(step 12a). Dashboard → Plugins → Catalog → install **Plugin Pages**, then **Home Screen Sections**
(it needs Plugin Pages and File Transformation), then:

```sh
docker restart jellyfin
```

**b. Pick your rows.** On the home page, open the menu (☰ top left) → **Modular Home**. Click the
button at the top to turn it on, then tick the rows you want. A good Netflix-like set:

| Row | What it shows |
| --- | ------------- |
| Continue Watching, Next Up | Same as now |
| Genre | Several rows, one per genre, e.g. "Action Movies", "Comedy Movies" |
| Because You Watched | Films like one you just finished |
| Hidden Gems | Rated 7.5 or higher, not watched yet |
| Decade | "Best of the 1990s" style row |
| Collections | Your collections, including Oscar Winners once step c is done |
| Discover, My Requests | Things from Seerr you don't have yet, with a request button |

Save (it doesn't say it saved), then refresh with Ctrl+Shift+R. Each person picks their own rows the
same way. Discover and My Requests use Seerr: if they're empty, Dashboard → Plugins → **Home Screen
Sections** and enter `http://seerr:5055` with Seerr's API key.

**No Modular Home in the menu?** Plugin Pages is missing: the log (`docker logs jellyfin | grep -i pluginpages`)
says `PluginPages plugin not found`. Install it, restart, and refresh.

**c. Add the Oscar winners.** Get a free API key from [omdbapi.com](https://www.omdbapi.com/apikey.aspx)
(it's emailed to you; click the link in the email to switch it on). Then:

1. Dashboard → Plugins → **Repositories** → **+**, name `Jellyfin Oscars`, URL
   `https://raw.githubusercontent.com/FizzyMUC/jellyfin-oscars-plugin/main/manifest.json`.
2. Catalog → **Jellyfin Oscars** → Install, then `docker restart jellyfin`.
3. Dashboard → Plugins → **Jellyfin Oscars**: paste the OMDb key, turn on enrichment, tick the
   **Oscar Winners** collection (and Nominees if you want a second row), Save.
4. Run its scan from the same page (or Dashboard → **Scheduled Tasks**). The first run checks every
   film, so give it a while. The free key allows 1,000 lookups a day; with a bigger library it
   finishes over a few days on its own.

The collection then shows up under Movies → **Collections**, and in the Collections row from step b.

**Good to know:**

- The rows are part of Jellyfin's web page, so they show in a browser, the desktop app and the
  phone apps. TV apps that draw their own screens (Roku, Android TV, Apple TV's Swiftfin) keep the
  normal home page.
- The plugins are built for one exact Jellyfin version. If one disappears from the catalog after a
  Jellyfin update, its new build isn't out yet; it comes back within days or weeks.
- Want a row that's always there, like "Action" every day instead of the rotating Genre rows?
  Make it a collection (Movies → select films → ⋮ → Add to collection) and it joins the Collections
  row. The separate "Collection Sections" plugin, which gives each collection a row of its own, isn't
  out for Jellyfin 12 yet.

### 22. Alerts on your phone, and a look inside from anywhere (Uptime Kuma + ntfy + Tailscale)

Beszel (step 16) watches the numbers: disk space, heat, memory. This step adds a night watchman who
does the rounds every minute and phones you the moment an app stops, with what's wrong:

| Piece | Job | Like |
| ----- | --- | ---- |
| **Uptime Kuma** (container, port 3004) | Checks every app, the VPN and the media drive once a minute | The night watchman with a checklist |
| **ntfy** (free app on your phone) | Delivers Uptime Kuma's (and Beszel's) "Jellyfin is down" and "Jellyfin is back" messages as push notifications | The watchman's pager |
| **Tailscale** (on the server and your phone) | A private tunnel from your phone to the server, so every home-only page works away from home | A key to the back door that only your phone has |

Nothing new is opened to the internet: no port forwarding, no Caddy site. Tailscale is the same kind
of encrypted WireGuard tunnel as your Mullvad VPN, just between your own devices.

**a. Get the new files, make the folder, start it.**

```sh
cd ~/jevans.cloud && git pull && mkdir -p /opt/media/config/uptime-kuma
```

```sh
cd ~/jevans.cloud/server && docker compose up -d && docker compose restart homepage
```

Homepage restarts so it picks up the new tile.

**b. Make your Uptime Kuma login.** On a computer at home, open `http://192.168.1.95:3004`. If it asks
which database to use, pick **SQLite**. Then make a username and password (save them in Vaultwarden).

**c. Get the ntfy app and pick a secret channel name.** Install **ntfy** from the App Store or Google
Play. ntfy's free server delivers to anyone subscribed to a channel name (a "topic"), so make one
nobody could guess. On the server:

```sh
echo "jevans-$(openssl rand -hex 8)"
```

Copy what it prints (something like `jevans-3f9a1c0e7b2d4a56`). In the ntfy app tap **+**, paste it as
the topic, leave the server as `ntfy.sh`, and **Subscribe**. Allow notifications when it asks.

**d. Tell Uptime Kuma about your phone and about Docker.** In Uptime Kuma, click your name top right →
**Settings**.

1. **Notifications** → **Setup Notification**. Type **ntfy**, a name like `My phone`, server URL
   `https://ntfy.sh`, the topic from step c, priority **High**. Tick **Default enabled** and **Apply on
   all existing monitors**. Click **Test**: your phone should buzz. **Save**.
2. **Docker Hosts** → **Setup Docker Host**. Name `server`, connection type **TCP / HTTP**, Docker
   daemon `http://dockerproxy:2375`. **Save**. (That's the same read-only Docker doorman Homepage uses:
   it can answer "is this running?" but can't start or stop anything.)

**e. Add the checks.** Back on the main page, **Add New Monitor** for each line below. Leave everything
else as it is (it checks every 60 seconds). Once one is done, the **Clone** button on it is the quick
way to make the next.

*Is each app running?* Monitor type **Docker Container**, Docker host `server`, and the friendly name
and container name both set to:

```
gluetun
```

then the same again for each of these (one monitor each): `jellyfin`, `qbittorrent`, `prowlarr`,
`sonarr`, `radarr`, `sabnzbd`, `bazarr`, `seerr`, `jellydash`, `caddy`, `adguard`, `vaultwarden`, `homepage`,
`beszel`, `beszel-agent`.

The `gluetun` one doubles as your VPN alarm: Gluetun tells Docker it's unhealthy when the tunnel drops,
and Uptime Kuma passes that on. (qBittorrent and Prowlarr have no internet then, by design.)

*Is Jellyfin actually answering?* Monitor type **HTTP(s) - Keyword**, name `Jellyfin answers`, URL
and keyword:

```
http://jellyfin:8096/health
```

```
Healthy
```

*Is the media drive plugged in?* This one matters most: the media drive is a USB drive, and if it
ever drops off, `/data` quietly becomes an empty folder on the small SSD and the apps start filling
that instead. Here the server checks itself and "presses a button" in Uptime Kuma once a minute; if
the presses stop, your phone buzzes. Like a dead man's switch on a train.

1. **Add New Monitor**, type **Push**, name `Media drive plugged in`, **Heartbeat Interval** `120`
   (two missed minutes before it worries). Copy the **Push URL** it shows, then **Save**.
2. On the server, add that URL to your `.env`. Run this, paste the URL when it asks, and press Enter:

   ```sh
   cd ~/jevans.cloud/server && read -p "Push URL: " u && echo "MEDIA_DRIVE_PUSH_URL='$u'" >> .env
   ```

3. Tell the server to run the check every minute (this adds one line to your scheduled jobs, "cron"):

   ```sh
   ( crontab -l 2>/dev/null; echo "* * * * * $HOME/jevans.cloud/server/scripts/check-media-drive.sh" ) | crontab -
   ```

Within two minutes the monitor turns green. The script is `scripts/check-media-drive.sh`: it only
presses when `/data` is mounted and the drive behind it still exists.

Disk space, temperatures and memory are Beszel's job (step 16f).

**f. A one-glance page.** **Status Pages** → **New Status Page**, name `Server`, slug:

```
server
```

Click **Add a monitor** and add them all, then **Save**. That page is what the Uptime Kuma tile on
Homepage shows, and it's handy on your phone.

**g. Install Tailscale on the server.** Paste these one at a time:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

```sh
sudo tailscale up --advertise-routes=192.168.1.95/32 --accept-dns=false
```

It prints a link: open it, sign in (Google or Apple is fine) and approve **jevans-server**. What the two
extras mean: `--advertise-routes=192.168.1.95/32` lets your phone use the server's normal home address,
so every link on Homepage works unchanged. `--accept-dns=false` leaves the server's own DNS alone, so
AdGuard keeps working as before.

Then on [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines), click the
**⋯** next to **jevans-server**:

1. **Edit route settings** → tick `192.168.1.95/32` → **Save**.
2. **Disable key expiry**, so the server doesn't drop off your tailnet every 6 months.

**h. Install Tailscale on your phone.** Get **Tailscale** from the App Store or Google Play and sign in
with the same account. Turn it on, switch your phone to mobile data, and open:

```
http://192.168.1.95:3004
```

That's Uptime Kuma. The same way, `http://192.168.1.95:3000` is Homepage and `http://192.168.1.95:3003`
is Beszel, wherever you are. (`home.jevans.cloud` and `vault.jevans.cloud` stay home-Wi-Fi only; use
the number addresses away from home.)

**When your phone buzzes,** the message names the check. Tap it in Uptime Kuma to see when it broke and
the error it got. Then:

- **An app is down:** `docker compose up -d <name>` brings it back; `docker compose logs --tail 50 <name>`
  says why it stopped. You can SSH from your phone too: Termius (free) works over Tailscale to
  `mediabox@192.168.1.95`.
- **gluetun:** `docker logs gluetun --tail 50`. Often Mullvad is just having a moment, and it reconnects
  on its own within a few minutes.
- **Media drive:** check the USB cable and power, then `sudo mount -a` and `docker compose restart`.
- **Drives, temperature, memory (from Beszel):** open Beszel for which drive or app it is.

### 23. A weekly check-up from Claude (Beszel reports)

Beszel only opens at home (or over Tailscale), and that's how it should stay. So instead of letting
Claude in, the server sends Claude a summary. Think of a nurse who copies the day's chart readings onto
one sheet and drops it in the doctor's private mailbox: the full charts never leave the house, and the
doctor reads the sheets once a week and writes back with advice.

- **The nurse:** `scripts/beszel-report.py`. Once a day it logs in to Beszel with a *read-only* login,
  works out averages and peaks (CPU, memory, swap, both drives, temperatures, network, each container),
  and writes them to a small file.
- **The mailbox:** a *private* GitHub repo, `server-reports`, that only you (and Claude) can see. The
  server gets a key that opens that one repo and nothing else.
- **The doctor:** a weekly Claude check-in in your project that reads the latest sheets and posts
  suggestions in the "Beszel reports" thread.

Only numbers and container names leave the server: no passwords, no addresses, no film titles.

**a. Make the mailbox.** On GitHub (the app or github.com/new): name it `server-reports`, choose
**Private**, tick **Add a README file**, and click **Create repository**.

**b. Give the server a key to it.** On the server, make a key just for this:

```sh
ssh-keygen -t ed25519 -N "" -C "jevans-server reports" -f ~/.ssh/server_reports
```

Show the public half (the part that's safe to share), and copy the whole line it prints:

```sh
cat ~/.ssh/server_reports.pub
```

On GitHub, open `server-reports` → **Settings** → **Deploy keys** → **Add deploy key**. Title
`jevans-server`, paste the line into **Key**, tick **Allow write access**, and click **Add key**.

**c. Copy the mailbox onto the server.** If it asks "Are you sure you want to continue connecting?",
that's GitHub introducing itself; it says yes for you.

```sh
GIT_SSH_COMMAND="ssh -i ~/.ssh/server_reports -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git clone git@github.com:scjevans/server-reports.git ~/server-reports
```

Tell that folder to always use its key, and who's signing the reports:

```sh
cd ~/server-reports && git config core.sshCommand "ssh -i ~/.ssh/server_reports -o IdentitiesOnly=yes" && git config user.name "jevans-server" && git config user.email "server@jevans.cloud"
```

**d. Get the new files and restart Beszel.** The hub gains one setting, `SHARE_ALL_SYSTEMS`, so a
second login can see the server. You're its only user, so nothing else changes.

```sh
cd ~/jevans.cloud && git pull
```

```sh
cd ~/jevans.cloud/server && docker compose up -d beszel
```

**e. Make the read-only login.** First make a password for it in Vaultwarden (the generator is fine)
and save it as "Beszel reports". On a computer at home, open `http://192.168.1.95:3003/_/` (Beszel's
back room, note the `/_/`) and log in with your usual Beszel email and password. Click **users** on the
left → **New record**, and fill in:

- **email:** `reports@jevans.cloud` (only a username, nothing is sent to it)
- **password** and **passwordConfirm:** the one you just made
- **verified:** on
- **role:** `readonly`

Click **Create**. A read-only login can look at every chart but can't change a thing.

**f. Put the login in `.env`.**

```sh
cd ~/jevans.cloud/server && echo "BESZEL_REPORT_EMAIL=reports@jevans.cloud" >> .env
```

Run this, paste the password when it asks, and press Enter:

```sh
read -p "Password: " p && echo "BESZEL_REPORT_PASSWORD='$p'" >> .env
```

**g. Try it.**

```sh
~/jevans.cloud/server/scripts/beszel-report.py
```

It should say `Report 2026-… written to /home/mediabox/server-reports`, and `server-reports` on GitHub
now has a `latest.md` (the sheet) and a `daily` folder (one file per day, so trends survive after Beszel
thins out its old readings).

**h. Run it every morning.** This adds one line to cron, at 6:50 AM:

```sh
( crontab -l 2>/dev/null; echo "50 6 * * * $HOME/jevans.cloud/server/scripts/beszel-report.py >> $HOME/server-reports.log 2>&1" ) | crontab -
```

**i. Tell Claude it's working,** in the project's "Beszel reports" thread. Claude then reads the reports
every week and posts what it would change: an app that's eating memory, swap filling up, the media drive
on course to fill, a container that keeps restarting, a CPU running hot.

If the report fails: `tail ~/server-reports.log` says why. `HTTP Error 400` means the email or password
in `.env` doesn't match step e. "can't see any systems" means step d's `docker compose up -d beszel`
didn't run. `Permission denied (publickey)` means the deploy key in step b is missing or lacks
**Allow write access**.

### 24. Watch parties (SyncTube)

SyncTube is a web page where everyone watches the same video at the same moment. Paste a YouTube link
(or Twitch, Vimeo, or a direct `.mp4` link) and it plays for everyone in the room, with a chat on the side.
Whoever holds the **Leader** button is the projectionist: when they pause, skip or rewind, every screen
follows. Nobody needs an account, just a nickname.

It's home only, at `http://192.168.1.95:4200`, and works away from home over Tailscale (step 22h), so
anyone on your Tailscale can join. Nothing new is opened to the internet.

For films and shows **in your Jellyfin library**, Jellyfin already has this built in: **SyncPlay** (the
icon with two people at the top of a video in the Jellyfin app or web page). SyncTube is for everything
else: YouTube, trailers, clips.

There's no ready-made SyncTube image to download, so the first start **builds** one from the author's
code, pinned to one exact version. That takes a few minutes the first time only.

**a. Get the new files and make the folder.**

```sh
cd ~/jevans.cloud && git pull
```

```sh
mkdir -p /opt/media/config/synctube && sudo chown 1000:1000 /opt/media/config/synctube
```

SyncTube runs as user 1000 inside its container, so its folder belongs to 1000 (like Seerr's).

**b. Build it and start it.**

```sh
cd ~/jevans.cloud/server && docker compose up -d --build synctube && docker compose restart homepage
```

You'll see it download and compile for a few minutes. Then check:

```sh
docker compose ps synctube
```

It should say `Up` (or `running`). Open `http://192.168.1.95:4200`, type a nickname, tap **+** under the
video area and paste a YouTube link. Open the same page on a second device: tap **Leader**, pause on one,
and the other pauses too. The dashboard has a new **SyncTube** tile under Watch.

**c. Optional: make yourself an admin.** Anyone can add videos and take the Leader button, which is fine
for family. Admins can also clear the chat, lock the playlist and kick people. SyncTube takes this as a
typed command, so you step into its console:

```sh
docker attach synctube
```

Press Enter once and you'll see a `>` prompt. Type `addAdmin`, a space, your nickname, a space, and a
new password, then Enter. For example `addAdmin Jack correct-horse-battery`. Then leave **without
stopping it**: hold Ctrl and press **P**, then **Q**. (In Termius, the Ctrl key is on the bar above the
keyboard.) If you press Ctrl+C by mistake, SyncTube stops and Docker starts it again a moment later.

Back on the page, log in with that nickname and password.

**d. Optional settings.** Put any you want in `/opt/media/config/synctube/config.json` (the full list is
in the author's `default-config.json`), then `docker compose restart synctube`. Two handy ones for a
small group:

- `"requestLeaderOnPause": true` lets anyone pause for everyone, without taking the Leader button.
- `"unpauseWithoutLeader": true` lets anyone press play again.

Videos uploaded from a device are kept in that folder too, capped at 3 GB (`cacheStorageLimitGiB`).

**Updating:** SyncTube is built, not pulled, so `docker compose pull` skips it. Ask Claude for the newest
version: it's one line in `docker-compose.yml` (the long code after `#`), then
`docker compose up -d --build synctube`.

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
- **Beszel's server stays red or "pending":** check `docker logs beszel-agent --tail 20`. "invalid key"
  or "unauthorized" means `BESZEL_AGENT_KEY` or `BESZEL_AGENT_TOKEN` in `.env` doesn't match the
  hub's **Add System** box (click the row's ⋮ → **Copy docker compose** to see them again); fix them and
  `docker compose up -d beszel-agent`. The Host / IP must be `/beszel_socket/beszel.sock`.
- **Beszel shows no temperatures:** the server may need its sensor tools. `sudo apt install lm-sensors`,
  `sudo sensors-detect --auto`, then `docker compose restart beszel-agent`.
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
- **Uptime Kuma says a Docker check can't connect:** the Docker host must be `http://dockerproxy:2375`
  with type TCP / HTTP (step 22d), and `docker compose ps dockerproxy` should say `Up`.
- **"Media drive plugged in" is red but the drive is fine:** run the check by hand,
  `~/jevans.cloud/server/scripts/check-media-drive.sh && echo pressed`. No `pressed` and no error means
  `MEDIA_DRIVE_PUSH_URL` is empty in `.env`, or `findmnt /data` shows nothing. `crontab -l` should list
  the line from step 22e.
- **No buzz on your phone:** in ntfy check the topic matches step c exactly, and that notifications are
  allowed for ntfy in your phone's settings. Uptime Kuma's **Test** button in the notification settings
  sends one straight away.
- **The 192.168.1.95 addresses don't open away from home:** Tailscale must be on in the phone app, and
  the `192.168.1.95/32` route approved in the Tailscale admin page (step 22g). `tailscale status` on
  the server should list your phone.
- **Sonarr/Radarr copy files instead of hardlinking:** downloads and library must be on the same drive,
  under the same `DATA_DIR`.
- **Permission errors:** `PUID`/`PGID` in `.env` must match the owner of `/data` (`id` shows yours).
- **Websites stop loading for everyone at home:** AdGuard is down and the router has no secondary
  DNS. `docker compose up -d adguard`, or set the router's DNS back to automatic. If `docker logs
  adguard` says it `cannot assign requested address`, the server started Docker before it had its
  network address: `docker compose up -d adguard` again fixes it.
