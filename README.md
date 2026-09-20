# VoidPaste GitHub Action

Create an ephemeral paste on [voidpaste.com](https://voidpaste.com) from a workflow. Calls real `POST /api/v1/pastes` with a Bearer API key. Response envelope is `{ paste, warnings }`.

**Public repo:** [`fleames/voidpaste-action`](https://github.com/fleames/voidpaste-action)  
**Canonical copy in the monorepo:** `integrations/github-action/`

## Minimal workflow

```yaml
name: Share failure log
on:
  workflow_dispatch:

jobs:
  paste:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Upload log
        id: vp
        uses: fleames/voidpaste-action@v1
        with:
          api-key: ${{ secrets.VP_API_KEY }}
          path: ./build.log
          title: CI log ${{ github.run_id }}
          language: log
          visibility: unlisted
          expiration: 1d
          idempotency-key: ${{ github.run_id }}-${{ github.job }}

      - name: Use URL
        run: echo "Paste at ${{ steps.vp.outputs.url }}"
```

Store a key from [Dashboard → API Keys](https://voidpaste.com/dashboard/api-keys) as repository secret `VP_API_KEY` (scopes `pastes:write`).

## Inputs

| Input | Required | Default | Notes |
|-------|----------|---------|-------|
| `api-key` | yes | — | `vp_live_…` secret |
| `content` | one of content/path | — | Inline body |
| `path` | one of content/path | — | File to upload (≤ 1 MB) |
| `title` | no | | |
| `language` | no | | e.g. `go`, `log` |
| `visibility` | no | `unlisted` | `public` \| `unlisted` \| `private` \| `password` |
| `expiration` | no | `1d` | `10m` / `1h` / `1d` / `1w` / `1M` / `never` / relative |
| `burn` | no | `false` | Prefer expiry for CI + chat links |
| `password` | if visibility=password | | Prefer secrets |
| `idempotency-key` | no | | Retries replay the same paste for 24h |
| `api-base` | no | `https://voidpaste.com` | |

## Outputs

| Output | Example |
|--------|---------|
| `id` | paste public id |
| `url` | `https://voidpaste.com/p/{id}` — share this |
| `raw_url` | `https://voidpaste.com/raw/{id}` — **unsafe for burn pastes in Slack/Discord** (crawlers may fetch and burn) |

The step writes the paste link to `$GITHUB_STEP_SUMMARY`.

## Chat safety

- Share `/p/{id}`, not `/raw/{id}`, especially for burn pastes.
- Prefer short **expiration** over **burn** when the link may be unfurled in Slack/Discord.

More recipes: https://voidpaste.com/docs/integrations
