# Website deployment

Live hostname: **https://reelbox.dartty.top:8443/** (confirmed after discovering that the originally supplied `reel.dartty.top` had no DNS record). The existing certificate is in `/etc/letsencrypt/live/reelbox.dartty.top/`; `/etc/letsencyrpt/` did not exist.

## Layout

- Public files: `/var/www/reelbox/releases/<release>/`, selected by the atomic `current` symlink
- Standalone nginx configuration: `/etc/reelbox/nginx.conf` and `security-headers.conf`
- Service: `reelbox-web.service`, enabled at boot, HTTPS port **8443** only
- Logs: `/var/log/reelbox/error.log`; access logging is disabled
- Certificate hook: `/etc/letsencrypt/renewal-hooks/deploy/reelbox-web`

Public TCP/UDP port 443 has a pre-existing ctunnel DNAT forward. The user explicitly chose **8443** rather than modifying or multiplexing that tunnel. Its firewall rules remain unchanged.

This is a **separate nginx instance**, not a modification of the existing `madmail-web.service` on port 8843. It does not touch the existing mail, proxy or tunnel configurations. Port 80 remains free for the existing Certbot standalone renewer.

## Updating

1. Stage only `index.html`, `styles.css`, `favicon.svg`, `assets/`, and `downloads/` in a new release directory. Do not expose `deploy/`, private files, Git metadata or configuration directories.
2. Copy the signed APK to `downloads/reelbox-0.2.0-arm64.apk` and the sanitized GPL source archive to `downloads/reelbox-0.2.0-source.zip`. Generate `downloads/SHA256SUMS.txt` from the actual files.
3. Verify the APK/source SHA-256 hashes on the server. Set directories to 0755 and files to 0644; nginx only needs read access.
4. Point `current` at the new release atomically, then run `nginx -t -c /etc/reelbox/nginx.conf`. Reload `reelbox-web.service` if configuration or certificates changed.
5. Verify through normal public HTTPS with hostname/chain validation enabled. Check the exact credit and GitHub URL, download MIME types, HEAD/Range/416 behavior, complete downloaded APK hash, and source ZIP integrity. Check the existing 8843 service remains healthy.

## Operations

```sh
systemctl status reelbox-web.service --no-pager
nginx -t -c /etc/reelbox/nginx.conf
systemctl reload reelbox-web.service
certbot renew --dry-run --cert-name reelbox.dartty.top --no-random-sleep-on-renew
```

The existing Certbot timer handles renewal; the scoped deploy hook tests configuration and reloads only this website's service after renewal of its certificate. No certificate/private key is copied into the public root or repository.

To roll back, atomically point `current` at the previous release directory. To stop only this website, run `systemctl disable --now reelbox-web.service`; the mail/download service remains separate.
