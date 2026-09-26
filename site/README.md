# Wake website

Two static pages: `index.html` (download) and `about.html`. No build step. The hero water is a WebGL port of the onboarding shader (`Wake/Features/Onboarding/WakeWaterShader.swift`), in `assets/water.js`.

The download button, version, date and size come from the latest GitHub release when the page loads. If that request fails, the links fall back to the pinned `v0.1.0` disk image, so update those in the HTML after a release.

## Run locally

```bash
docker build -t wake-site . && docker run --rm -p 8080:80 wake-site
```

Then open http://localhost:8080. Any static server works too (`python3 -m http.server` from this folder), though `/about` without `.html` only resolves under nginx.

## Deploy on Dokploy

Either way, point your domain at container port 80 in Dokploy; Traefik handles TLS.

- **Compose:** new Compose service from this repo, Compose Path `./site/docker-compose.yml`, then add the domain on service `wake-site`.
- **Application:** new Application from this repo, Build Type `Dockerfile`, Docker Context Path `site`, Dockerfile Path `site/Dockerfile`.

The container answers `GET /health` with `ok`, which the Dockerfile's `HEALTHCHECK` uses.
