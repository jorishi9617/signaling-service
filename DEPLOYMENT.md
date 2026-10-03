# Deploy the video platform

This repository contains the signaling service, its standalone Render
Blueprint, and the optional full-stack local Docker Compose setup. The
signaling service builds and deploys from this repository without cloning or
building any other application repository. All providers currently have free
offerings, but nobody can guarantee exactly $0 forever: free plans and quotas
can change, services can sleep or be limited, and usage outside free
allowances can be charged. Review each provider's current pricing and add
billing alerts before enabling paid usage.

## Run everything locally

Install Docker Desktop, then from this repository's directory run:

```sh
docker compose up --build
```

The full-stack Compose setup requires the auth, call, token, and frontend
repositories checked out as sibling directories next to `signaling-service`.
To run just signaling locally, use `docker build -t video-platform-signaling .`
and start the image with `JWT_SECRET` and `FRONTEND_ORIGINS` configured.

Open <http://localhost:3000>. Local PostgreSQL is at `localhost:5432`
(`video` / `video-local` by default); the backend apps are exposed on ports
8081-8084. The database and each Java service are capped at 256 MiB, and the
frontend is capped at 384 MiB, to make memory failures visible during local
testing.

These defaults are for local development only. The checked-in JWT and API-key
fallbacks are not production secrets. To stop the stack, run
`docker compose down`; add `-v` only if you also want to delete the local
database.

## Deploy the database on Neon

The Neon project is already linked in this checkout as project
`noisy-smoke-33215628`, branch `production`, database `neondb`. The auth and
call services apply their Flyway migrations at startup, creating the `auth`
and `calls` schemas as needed.

In the Neon console, select the Java/JDBC connection option and copy the
direct (non-pooler) JDBC URL. Store it as the Render environment variable
`DATABASE_URL` for both `video-platform-auth` and `video-platform-call`.
Spring expects the URL to start with `jdbc:postgresql://`; if Neon gives you a
URL starting with `postgresql://`, add the `jdbc:` prefix. The direct URL is
needed because Flyway migrations run when each service starts. Keep the
credentials private; do not commit the URL.

## Deploy signaling independently on Render

1. Push the repositories to GitHub and sign in to Render with GitHub.
2. Choose **New → Blueprint**, select the
   `jorishi9617/signaling-service` repository, and apply its `render.yaml`.
   This Blueprint defines only `video-platform-signaling`; it does not create
   or build any other application.
3. When prompted, set `JWT_SECRET` to the same Base64 secret used by the
   services that issue/validate your user tokens. It must decode to at least
   32 bytes. Set `FRONTEND_ORIGINS` to the exact Vercel frontend origin, such
   as `https://frontend-web.vercel.app`.
4. Wait for the GitHub Actions check and Render build to complete. Render
   builds the Dockerfile directly from this repository; the image bounds the
   Java heap to 128 MiB. The Blueprint selects Render's free plan.
5. Use the service URL from the Render dashboard as the frontend's signaling
   URL, with `wss://` and `/ws` appended, for example
   `wss://video-platform-signaling.onrender.com/ws`.

The auth, call, and token services can be deployed separately from their own
repositories and provider configurations. Render's free web services may
sleep while idle, so expect slow first requests.

## Deploy the frontend on Vercel

1. Import `jorishi9617/frontend-web` into Vercel and deploy its `master`
   branch.
2. The frontend's `vercel.json` proxies `/api/auth/*` and `/api/calls/*` to
   their Render services. If a Render URL differs from the configured
   hostname, update the matching rewrite and redeploy.
3. Set these Vercel Production environment variables:

   | Variable | Value |
   | --- | --- |
   | `NEXT_PUBLIC_SIGNALING_URL` | Signaling service URL using `wss://` and ending in `/ws` |
   | `TOKEN_API_URL` | Token service URL using `https://` |
   | `TOKEN_API_KEY` | The secret `API_KEY` from the Render `video-platform-secrets` group |

   The Next.js server proxies `/api/tokens/*` and injects `TOKEN_API_KEY`;
   the key is not sent to the browser. Redeploy the frontend after setting
   these values.
4. Set `FRONTEND_ORIGINS` on this signaling service to the exact Vercel
   production origin, for example `https://frontend-web.vercel.app`.

The HTTP API rewrites are same-origin from the browser, so CORS is not needed
for those proxied requests. The direct WebSocket connection is allowed by the
signaling service's `FRONTEND_ORIGINS` setting.

## CI/CD

This repository's `.github/workflows/ci.yml` verifies the signaling service
using only its own source and Maven dependencies on pushes and pull requests
to `master`. Render is configured to deploy this service after checks pass.
