# Free cloud deployment

`render.yaml` deploys all four Java services, the Next.js frontend, and
PostgreSQL on Render's free plan. You do not need to buy a server or domain;
Render provides HTTPS URLs and supports the signaling WebSocket.

## Important free-plan limits

- Free web services sleep when idle and can take about a minute to wake up.
  The monthly free instance-hour allowance is shared across the services in
  your Render workspace. Five services running continuously exceed it.
- Render's free PostgreSQL database expires after 30 days and its data is
  deleted. This is suitable only for a temporary demo. For data you need to
  keep, stop before deploying and choose a persistent free PostgreSQL provider
  instead; its account and connection details must be configured separately.
- Free service capacity, startup time, and availability are not guaranteed.

## Deploy

1. Sign in to Render using GitHub and authorize access to the public app
   repositories.
2. In Render, choose **New > Blueprint**, then select
   `jorishi9617/signaling-service`. Render reads `render.yaml` there and creates
   all five services plus the database, including services whose source lives
   in the other public repositories.
3. Choose **Apply**. Render generates the shared Base64 JWT secret and token
   API key automatically; they are not stored in the repositories.
4. Wait for the builds to complete. The first deploy can
   take several minutes. Render assigns HTTPS URLs to the web services and
   the frontend build is configured to use those service names.
5. Open the `jorishi9617-video-platform-web` URL shown on its Render service
   page to use the application.

Clients that call the token service's `/api/tokens` endpoints must send its
generated `API_KEY` in the `X-API-Key` request header. Retrieve the key from
the Render dashboard; do not post it in chat or commit it.

## After deployment

Render automatically redeploys a service when its repository's `master` branch
changes. To preserve your database after its 30-day expiry, export or migrate
the data before that date. Stopping or deleting the Render database permanently
deletes its data.

The `compose.yaml` file remains available for deploying the same stack on a
server you manage.
