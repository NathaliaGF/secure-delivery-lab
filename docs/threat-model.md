# Threat model

A short, honest model of what the delivery pipeline defends against. "Control" is something that is
implemented and exercised in this repository; "Residual" is what is still open.

| Threat | Control | Residual |
|---|---|---|
| A dependency or the base image is swapped for a malicious one | Dependencies are hash-locked (`--require-hashes`), the base image is pinned by digest, Dependabot proposes reviewed updates, Trivy scans the built image | A malicious *new* release that passes review and has no known CVE |
| A known-vulnerable package ships | Trivy blocks HIGH/CRITICAL findings that have a fix | Unfixed CVEs are reported but not blocking (`ignore-unfixed`) |
| A secret is committed | secrets-scanner blocks on the tree **and the git history** | Secrets in formats the scanner does not know; anything that already reached a public remote must be rotated |
| An insecure container configuration reaches staging | dockerscan blocks the Dockerfile and compose files; `verify-hardening.sh` checks the **running** container | Settings the checks do not look at |
| The deployed image is not the one that was built and scanned | The scanned image is the one pushed; it is signed with cosign (keyless); deployment and promotion verify the signature against this repository's pipeline identity | A compromise of the pipeline identity itself (see next rows) |
| A third-party action is compromised | Every action is pinned to a commit SHA; Dependabot proposes updates | The pinned code itself can still be malicious when first reviewed |
| The CI token is abused | Top-level `permissions: contents: read`; each job asks only for what it needs; checkout does not persist credentials | `GITHUB_TOKEN` can still push to GHCR in the job that needs it |
| An unreviewed change reaches production | `production` environment with required reviewers (must be enabled in the repository settings) | Not enforced by the code in this repository: it depends on that setting and on branch protection |
| A bad release is promoted | Rollback workflow, digest-only, signature-verified, same approval | Time between detection and rollback |
| A host is deployed with default settings | Ansible role (SSH, firewall, auditd, sysctl, passwords), tested for idempotence and final state | Runtime effects not testable in a container (see the role README) |

## Out of scope

Runtime threat detection, WAF, network segmentation beyond one private network, secrets rotation,
DDoS, physical access, and the security of the GitHub account itself (enable MFA).
