# Wake website

The download and about pages, served by nginx.

## Deploy on Dokploy

1. In your DNS, add an `A` record for the subdomain (e.g. `wake`) pointing at the VPS. On Cloudflare, turn the proxy off or set SSL to "Full" so Let's Encrypt can issue the certificate.
2. In Dokploy, create a project, then **Create Service › Compose**.
3. Provider: GitHub, repository `amiralibg/wake`, branch `main`. Set **Compose Path** to `./site/docker-compose.yml` and save.
4. Click **Deploy**.
5. In the **Domains** tab, add the domain: service `wake-site`, path `/`, container port `80`, HTTPS on with Let's Encrypt.
6. **Deploy** again. A Compose service only picks up a new domain on redeploy.
7. Open `https://<your domain>/health`; it should answer `ok`.

To rebuild on every push to `main`, turn on **Autodeploy** in the service's General tab.

If you get a 502, check that the domain's container port is `80` and that the container is running (`docker ps -a | grep wake` on the VPS, or the service's Logs tab).

## Run locally

```bash
docker build -t wake-site . && docker run --rm -p 8080:80 wake-site
```

Then open http://localhost:8080.

## After a release

The download button, version and size load from the latest GitHub release. If that request fails, the page falls back to the `v0.1.0` links written in `index.html` and `about.html`; bump those when you release.
