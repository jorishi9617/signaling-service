# Free-tier cloud deployment

This setup runs the four Java applications on Google Cloud Run, PostgreSQL on
Neon, and the Next.js frontend on Vercel. Each provider has a free tier. Google
Cloud requires a billing account, and free-tier quotas are shared and can
change; add a budget alert before deploying. Usage beyond free quotas can cost
money. Cloud Run services scale to zero when idle, so the first request after
sleep can be slow. The Neon free database is small and is not a substitute for
backups.

The free Cloud Run allowance currently includes monthly request-based compute
and up to 2 million requests, but its CPU and memory time is shared by all
services on the billing account. Four Java services can use that allowance
quickly if they receive steady traffic. WebSocket connections are limited to
the Cloud Run request timeout and clients need to reconnect after an hour.

## 1. Create free accounts and a database

1. Create a Google Cloud project and attach a billing account. Create a budget
   alert in **Billing** before running the deployment script.
2. Install the Google Cloud CLI on your computer, then run `gcloud auth login`
   and `gcloud config set project YOUR_PROJECT_ID`.
3. The Neon project is already linked in this checkout as
   `noisy-smoke-33215628`, branch `production`, database `neondb`. If you are
   setting up from a fresh checkout, install and authenticate the Neon CLI:

   ```sh
   npm install -g neon
   neon auth
   neon link --project-id noisy-smoke-33215628 \
     --branch production --no-env-pull -y
   ```

   The deploy script gets the direct production connection URL from the Neon
   CLI, converts it to JDBC, and stores it in Google Secret Manager. It does
   not print or commit the database password. The direct connection is needed
   because Flyway applies the app's checked-in migrations during startup. The
   selected database currently has no `auth` or `calls` schema; the auth and
   call services create these from their versioned Flyway migrations at startup.
4. Create a free Vercel account and connect it to GitHub. You can import the
   frontend now, but wait to configure its production variables until the APIs
   have URLs.

## 2. Deploy the Java services

From the root of the cloned `signaling-service` repository, run:

```sh
bash deploy/cloud-run/deploy.sh
```

The script creates random JWT and API-key secrets in Google Secret Manager,
gets the connection URL from the linked Neon project, builds the four Java
images, and deploys them to Cloud Run in `us-central1`. Do not paste secrets
into chat or save them in Git. Keep the script's final service URLs.

If prompted to enable Google APIs, allow it. The deploying Google account needs
permission to build images, create Cloud Run services and secrets, and use the
project's billing account.

## 3. Deploy the frontend

In the Vercel project for `jorishi9617/frontend-web`, open **Settings →
Environment Variables** and add these three variables for **Production**. Use
the URLs printed by the deployment script:

| Variable | Value |
| --- | --- |
| `AUTH_API_INTERNAL_URL` | Auth service URL, starting with `https://` |
| `CALL_API_INTERNAL_URL` | Call service URL, starting with `https://` |
| `NEXT_PUBLIC_SIGNALING_URL` | Signaling service URL, changed to `wss://` and suffixed with `/ws` |

For example, if the signaling URL is `https://service-abc-uc.a.run.app`, set
`NEXT_PUBLIC_SIGNALING_URL` to `wss://service-abc-uc.a.run.app/ws`. If Vercel already made an initial deployment, redeploy after saving the
variables. Open the Vercel deployment URL and test register, login, calls, and
WebSocket signaling.

## 4. Restrict browser origins

The first deploy allows browser origins so it works before the Vercel domain
is known. Once Vercel assigns the frontend URL, replace `*` with that exact
`https://...vercel.app` origin on the auth, call, and signaling Cloud Run
services. In each service's **Variables & Secrets** settings, edit
`FRONTEND_ORIGINS` and redeploy.

## Updating services

Push code to the corresponding public GitHub repository, then rebuild the
changed Java image from this repository's root:

```sh
gcloud builds submit ../auth-service \
  --tag us-central1-docker.pkg.dev/PROJECT_ID/video-platform/auth-service:latest
gcloud run deploy video-platform-auth \
  --image us-central1-docker.pkg.dev/PROJECT_ID/video-platform/auth-service:latest \
  --region us-central1
```

Replace `PROJECT_ID` with your Google Cloud project ID and substitute the
service and image name for call, token, or signaling.
