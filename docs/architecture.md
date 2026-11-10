# Architecture notes

## Why the image is scanned before it is pushed
The pipeline builds the image into the runner's local Docker daemon, runs the gates against that
local image, and only then tags and pushes **that same image**. Building twice (once to scan, once to
push) would let the two differ. The digest used from then on (signing, deployment, promotion) is the
digest that `docker push` reports for the scanned image.

## Why Terraform deploys staging
Deployment is declared in `infra/terraform` rather than scripted in the workflow. The image is a
variable that must be a digest, so a mutable tag cannot be deployed by mistake. The stack is created,
smoke-tested and destroyed in every run, which also proves that the configuration can be applied from
scratch.

## Why the Ansible role never gets "proof" it did not earn
The CI target is a container, so tasks that need systemd or SELinux are skipped there and the README
says so. The verify playbook checks effective state (`sshd -T`, `nft -c`) rather than grepping for the
lines the role wrote, so a vendor file overriding a setting would fail the test.

## Why some exceptions exist
Exceptions are written next to the code with the reason (for example the `checkov:skip` in
`rollback.yml`). A silent suppression is a hidden risk; a documented one is a decision.
