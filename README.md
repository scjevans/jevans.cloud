# jevans.cloud

Public access television for one. Plain static files, no build step:

```
index.html   the set and the remote
styles.css   colors, CRT glass, remote control
app.js       CONFIG at the top, then the 40x24 character-screen renderer
favicon.svg
```

## Channels

| CH | What |
| -- | ---- |
| 02 | Guide (home) |
| 03 | Media server: live Jellyfin status, open/copy address, app links |
| 04 | Links & socials |
| 05 | About |
| 99 | Color bars |
| anything else | static, NO SIGNAL |

Keys: digits to tune (one digit tunes after a pause, two tune at once), arrow keys or
PageUp/PageDown to surf, `C` for closed captions. Channels are addressable by URL,
e.g. `https://jevans.cloud/#3`.

## Setting it up

1. Socials live in `CONFIG.socials` in `app.js`. Give a row a `url` to open a link (or `mailto:`),
   or `copy` to copy text to the clipboard instead (used for Discord, which has no username URLs).
2. If Jellyfin ends up somewhere other than `https://media.jevans.cloud`, change `CONFIG.jellyfin.url`.

## Hosting

Any static host works: Cloudflare Pages, Netlify, GitHub Pages, or the same box that runs Jellyfin.
Point `jevans.cloud` at it and upload this folder.

## Jellyfin, when you get to it

The site expects Jellyfin on its own subdomain behind HTTPS. With Caddy on the server:

```
jevans.cloud {
    root * /srv/jevans.cloud
    file_server
}

media.jevans.cloud {
    reverse_proxy localhost:8096
}
```

Add an `A` record for `media.jevans.cloud` pointing at the server. Once it answers,
the status on channels 2 and 3 flips from OFF AIR to ON AIR and shows the server name and version
(read from Jellyfin's public `/System/Info/Public` endpoint, which needs no login).

If you'd rather not open ports, Tailscale Funnel works; just keep the public address in
`CONFIG.jellyfin.url`. (Avoid proxying video through Cloudflare's free tier: their terms frown on it.)
