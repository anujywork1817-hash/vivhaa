# New Environment Runbook

Steps for standing up Vivaha's backend (API on Elastic Beanstalk, worker/
notification/scheduler + Postgres/Redis/Kafka/Elasticsearch/MinIO on a
shared EC2 box) in a new region or account. Written after the 2026-08-24
Mumbai deployment, where two separate incidents — missing security-group
rules and a never-provisioned storage bucket — both came from steps that
existed only as tribal knowledge, not a checklist.

## 1. Security group rules

The supporting-services EC2 box needs inbound access, scoped to the VPC
CIDR (never public), for every port the API/worker/admin containers
connect to:

| Port  | Service       |
|-------|---------------|
| 56379 | Redis         |
| 59000 | MinIO         |
| 59200 | Elasticsearch |
| 59092 | Kafka         |

Run [`scripts/infra/ensure-security-group-rules.sh`](scripts/infra/ensure-security-group-rules.sh)
against the box's security group — it's idempotent, so re-running it on an
already-configured environment is safe:

```bash
SG_ID=sg-xxxxxxxx VPC_CIDR=172.31.0.0/16 ./scripts/infra/ensure-security-group-rules.sh
```

Do not open these ports by hand and consider the job done — update the
script (and re-run it) instead, so the list can't silently drift again.

## 2. MinIO / S3 buckets

**`s3Client.EnsureBucket()` / `EnsureDocsBucket()` in `cmd/api/main.go`
only run when `APP_ENV=dev`, by design.** In staging/prod, nobody creates
these buckets automatically — this step is not optional and is easy to
forget (it was forgotten on 2026-08-24, silently breaking identity
verification for every user until traced days later).

Run [`scripts/infra/provision-minio-buckets.sh`](scripts/infra/provision-minio-buckets.sh)
as an explicit deployment step for any new environment, before the API is
expected to serve traffic:

```bash
MC_HOST_local=http://ACCESS_KEY:SECRET_KEY@<minio-host>:<port> \
  ./scripts/infra/provision-minio-buckets.sh
```

Required buckets:
- `matrimony-photos` — public-read (profile photos)
- `matrimony-verification-docs` — private, presigned-URL-only (ID
  verification documents)

**Checklist item, not tribal knowledge: run this script before declaring a
new environment ready.**

## 3. nginx upload size limit

`backend/.platform/nginx/conf.d/upload_size.conf` (`client_max_body_size
15M`) is committed to the repo and part of the Elastic Beanstalk
deployment bundle — it's applied automatically on every deploy of this
codebase to a new environment. No manual step needed here; just confirm
the file is present in the deployed bundle if uploads start failing with
413s again.

## 4. Environment variables

Every **non-secret** environment variable (`DB_HOST`, `REDIS_ADDR`,
`KAFKA_BROKERS`, `ES_ADDRESSES`, `S3_*` endpoints/bucket names,
`CORS_ALLOWED_ORIGINS`, feature flags, etc.) is set via
[`backend/.ebextensions/01-environment-settings.config`](.ebextensions/01-environment-settings.config),
so they're re-asserted from source control on every deploy rather than
depending on a Beanstalk console setting a failed config-deploy could roll
back (this happened on 2026-08-24 — `KAFKA_BROKERS`/`ES_ADDRESSES`
silently reverted to a stale `localhost` snapshot). **Update values in
that file, not in the Beanstalk console, if the supporting-services box
or any endpoint ever moves.**

**Credentials are deliberately excluded** from that file and remain
Beanstalk console / Parameter Store only: `DB_PASSWORD`,
`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `RAZORPAY_KEY_ID`,
`RAZORPAY_KEY_SECRET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `TURN_SECRET`.
Committing secrets to source control is a worse risk than the config-drift
problem `.ebextensions` solves here — if these ever need the same
rollback protection, migrate them to AWS Systems Manager Parameter Store
(SecureString) referenced from `option_settings`, never inline into the
`.config` file. When setting these for a new environment, apply them all
in a single `aws elasticbeanstalk update-environment --option-settings
...` call covering every secret at once, not one-at-a-time console edits
— a partial update is exactly what caused the 2026-08-24 rollback to
silently drop only some variables.

## 5. Verifying the environment is healthy

`GET /health` reports on every hard dependency, not just DB/Redis:

```json
{
  "success": true,
  "data": {
    "status": "ok",
    "database": "ok",
    "redis": "ok",
    "elasticsearch": "ok",
    "kafka": "ok",
    "storage": "ok"
  }
}
```

Any field other than `"ok"` names exactly which dependency is
unreachable — a wrong host, a missing security-group rule, or a
never-provisioned bucket. Server logs additionally get an `ERROR`-level
"readiness check: X unreachable" line for each failing dependency, so
this can be wired into a deploy-pipeline gate or alerting rule instead of
only being checked by hand. Treat a non-`ok` `/health` response after a
fresh deploy as a blocking failure, not something to investigate later.
