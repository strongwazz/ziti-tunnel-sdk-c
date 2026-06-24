# Releasing this fork

This fork tracks upstream [openziti/ziti-tunnel-sdk-c](https://github.com/openziti/ziti-tunnel-sdk-c)
and ships **Windows-only** binaries whose version matches the upstream release
(our `v1.15.1` == ziti's `v1.15.1` source + our edits).

> This replaces upstream's release process (CPack/Artifactory/Docker/Release
> Drafter), none of which the fork uses.

## What the fork changes

The entire fork patch is small and lives on `main`:

- `programs/ziti-edge-tunnel/netif_driver/windows/tun.c` — Windows adapter
  renamed to **EdgeConnect** (alias `edgeconnect-tun*`, type "EdgeConnect Tunnel").
- `.github/workflows/fork-release.yml` — builds the 3 Windows presets and
  attaches the zips to the GitHub Release. This file does not exist upstream.
- Upstream CI workflows are **deleted** (all-platform builds, Linux packaging,
  container images, OpenZiti Mattermost/CLA/nix, Release Drafter). Only
  `fork-release.yml` and `linters.yml` remain.
- `scripts/cut-fork-release.sh`, this file.

## One-time setup (fresh clone)

```bash
git remote -v   # need origin -> your fork AND upstream -> openziti
# if upstream is missing:
git remote add upstream https://github.com/openziti/ziti-tunnel-sdk-c.git
```

## Cutting a release (e.g. 9000.0.0)

```bash
# 1. fork edits current on main and pushed
git switch main && git push origin main

# 2. build the release branch + tag from upstream's tag of the same version
scripts/cut-fork-release.sh 9000.0.0

# 3. push branch + tag (tag is force-moved off upstream's commit onto ours)
git push origin release-v9000.0.0
git push --force origin v9000.0.0

# 4. publish the Release ON THE FORK -> triggers fork-release.yml (the Windows build)
#    (the script prints this exact line with --repo/--target filled in)
gh release create v9000.0.0 --repo <your-fork> --target release-v9000.0.0 \
  --title v9000.0.0 --generate-notes
```

Publishing the GitHub Release is what fires `fork-release.yml`; pushing the tag
alone does not build anything.

## How the script handles conflicts

`cut-fork-release.sh` branches from upstream's real `vX.Y.Z` commit, replays the
fork commits, and force-moves the tag onto our commit (so `git describe` yields a
clean `X.Y.Z`).

- **Expected, auto-resolved:** upstream's tag still contains the CI workflow
  files we delete, producing modify/delete conflicts. The script keeps them
  deleted and continues.
- **Real, manual:** if upstream rewrote `tun.c` (the only source file we patch),
  the script aborts:

  ```text
  UNRESOLVED conflict [UU]: programs/.../tun.c
  ```

  Fix the rename by hand, `git add` it, `git cherry-pick --continue`, then either
  re-run the script or finish with `git tag -f -a vX.Y.Z`.

## Gotchas

- `gh` defaults to the `upstream` remote and will 404 if you omit `--repo`. The
  script's printed command includes `--repo <your-fork>` derived from `origin`.
- The tag push is `--force` because the tag is moved off upstream's commit. This
  only affects your fork's `origin`; upstream is never pushed to. Avoid re-cutting
  a version others have already pulled.
