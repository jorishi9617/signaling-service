# Deploy the video platform

This repository supports local Docker Compose, Render for the four Java
services, Neon for PostgreSQL, and Vercel for the frontend. All providers
currently have free offerings, but nobody can guarantee exactly $0 forever:
free plans and quotas can change, services can sleep or be limited, and usage
outside free allowances can be charged. Neon and Render free tiers also have
resource and availability limits. Review each provider's current pricing and
add billing alerts before enabling paid usage.

## Run everything locally

Install Docker Desktop, then from this repository's directory run:

```sh
docker compose up --build
```

The auth, call, token, and frontend repositories must be checked out as sibling
directories next to `signaling-service`, matching this workspace layout.

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

## Deploy the Java services on Render

1. Push the repositories to GitHub and sign in to Render with GitHub.
2. Choose **New → Blueprint**, select the
   `jorishi9617/signaling-service` repository, and apply its `render.yaml`.
   The blueprint creates the auth, call, signaling, and token Java services
   from the other public repositories.
3. In the Render environment group `video-platform-secrets`, set `JWT_SECRET`
   to a random Base64 secret (generate with `openssl rand -base64 48`) and
   `API_KEY` to a separate random value (generate with `openssl rand -hex 32`).
   Keep both private. The same JWT secret is used by all token issuers and
   validators.
4. Set `DATABASE_URL` on the auth and call services to the Neon direct
   connection string. The blueprint prompts for this secret.
5. Wait for the GitHub Actions CI checks and Render builds to complete. The
   backend images constrain the Java heap to 128 MiB and the blueprint selects
   Render's free plan.

Service endpoints are named in the blueprint: `video-platform-auth`,
`video-platform-call`, `video-platform-signaling`, and `video-platform-token`.
If Render assigns different public URLs, use the actual URLs from the service
dashboard in Vercel. Render's free web services may sleep while idle, so expect
slow first requests.

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
4. Set `FRONTEND_ORIGINS` on the Render auth, call, and signaling services to
   the exact Vercel production origin, for example
   `https://frontend-web.vercel.app`, then redeploy those services.

The HTTP API rewrites are same-origin from the browser, so CORS is not needed
for those proxied requests. The direct WebSocket connection is allowed by the
signaling service's `FRONTEND_ORIGINS` setting.

## CI/CD

Each GitHub repository has a workflow under `.github/workflows/ci.yml`. It runs
Maven verification for the Java services and a production build for the
frontend on pushes and pull requests to `master`. Render is configured to
deploy after checks pass.
