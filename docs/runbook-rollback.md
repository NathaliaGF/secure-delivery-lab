# Runbook: roll back production

When: the version behind `:prod` misbehaves and you want the previous one back.

1. Find the digest of the version you want. Open the earlier `pipeline` run that promoted it;
   the `promote` job summary says ``production now points to `ghcr.io/…@sha256:…` ``.
   Alternatively: **Packages → secure-delivery-lab** lists every `sha-<commit>` tag with its digest.
2. **Actions → rollback → Run workflow**, paste `ghcr.io/<owner>/secure-delivery-lab@sha256:<digest>`.
3. A reviewer approves the `production` environment.
4. The workflow rejects anything that is not pinned by digest, **verifies the signature**, and
   retags `:prod` to that digest. The summary confirms the new target.
5. Verify: `docker buildx imagetools inspect ghcr.io/<owner>/secure-delivery-lab:prod`
   must show the digest you chose.

Do not rebuild from an old commit to "roll back": a rebuild produces a different image that was never
scanned or signed. Roll back by digest.
