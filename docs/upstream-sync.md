# Syncing upstream Silo into Prairie Apple

Prairie Apple is an AGPL fork of `Silo-Server/silo-apple`. Upstream syncs are
routine, and they are also the main way Prairie loses work. A conflicted file
resolved wholesale to upstream deletes Prairie's hunks, and the code often
still compiles because the Prairie type survives while nothing calls it.
Past losses: the first-run connect list (`ConnectServerListView`), the iOS
Quick Connect and update-status rows, the `X-Prairie-Image-Formats` header on
API requests, iOS trickplay scrub tiles, and Silo's diagnostics host coming
back.

## Rules

- Sync on a `sync/upstream-<date>` branch with a real `git merge upstream/main`
  and land it with **"Create a merge commit"**. Never squash; it drops upstream
  ancestry and the next sync re-conflicts everything.
- **A sync PR merges only with CI green**, including the macOS `Apple
  regression` and `Unit Tests` jobs. A failing test after a sync usually means
  Prairie code was dropped while its test was kept.
- `Prairie invariants` (`scripts/check-prairie-invariants.sh`) must pass. If it
  fails, restore the code. Do not edit the manifest to make it pass.

## After resolving conflicts

1. Rebrand fallout: `SiloAPI` → `PrairieAPI`, `silo*` colors and theme names →
   `prairie*`, `X-Silo-*` → `X-Prairie-*`, `siloserver.org` hosts →
   `prairieserver.org`. Keep wire tokens the server and other clients share
   (`x-silo-original`, `_silocast._tcp`, `_silopair._tcp`,
   `silo-public-diagnostics-v1`) unless the server changes them.
2. Hunk audit: for each Prairie PR, check its added lines still exist in the
   merge result (`gh pr diff <n>`). Upstream moves files, so search the whole
   tree, not only the original path.
3. Reachability: every Prairie screen must still have a caller. Grep for
   `LiveTVChannelListView(`, `QuickConnectView()`, `ConnectServerListView(`.
   A view type with no call site means lost wiring.
4. New upstream tests that assert Silo strings or hosts need the Prairie value.
5. Run `scripts/check-prairie-invariants.sh` and `scripts/ci/check-no-api-v1.sh`
   locally; both run on Linux.

## When you restore something a sync dropped

Add an anchor for it to `scripts/prairie-invariants.txt` in the same PR: the
file, the minimum number of matches, a regex on a stable identifier, and where
it came from. That is what stops the next sync from deleting it again.
