# Threat model (STRIDE, delivery path)

Scope: from a commit in an application repository to a running pod. Out of scope: runtime application vulnerabilities, cluster control-plane hardening, and the GitHub/Sigstore platforms themselves.

## Assets

- Source code and build definitions
- Container images in GHCR
- The GitOps environment state (`gitops/environments/*`)
- The Kubernetes cluster and its workloads

## Trust boundaries

1. Developer workstation → GitHub (push / PR)
2. GitHub Actions runner → GHCR / Sigstore (publish, sign)
3. GitOps repository → Argo CD (desired state)
4. Kubernetes API → Kyverno admission → kubelet / registry

## Threats and mitigations

| STRIDE | Threat | Mitigation | Residual risk |
|---|---|---|---|
| **S**poofing | An image built outside CI is pushed to GHCR under the right name | Kyverno `ImageValidatingPolicy` requires a keyless signature whose identity is `secure-container.yml@refs/heads/main`, issued by GitHub's OIDC provider | Compromise of the `main` branch of this repo. Mitigate with branch protection and required reviews. |
| **T**ampering | Tag re-pointed to a different image after approval | Environments pin digests; Kyverno `verifyDigest` + `mutateDigest` | — |
| **T**ampering | A third-party GitHub Action is hijacked | All actions pinned to full commit SHAs; tool binaries checksum-verified | SHA pins need deliberate updates (Dependabot can raise them) |
| **R**epudiation | Who promoted what? | Promotion is a Git commit by `promote.yml`; the run records the actor and the verified digest; Rekor provides a public signing record | — |
| **I**nformation disclosure | Secrets committed to source | gitleaks on the full history blocks the pipeline; Trivy secret scanner | Secrets already in history must be rotated, not just removed |
| **I**nformation disclosure | SBOM reveals components | SBOM is published intentionally (transparency); no secrets in images | — |
| **D**enial of service | A workload without limits exhausts the node | `require-resources` policy | CPU limits not required by design (avoids throttling) |
| **E**levation of privilege | Container escape via privileged or root containers | `disallow-privileged`, `require-non-root`, `disallow-privilege-escalation`; the app chart also sets a read-only root FS and drops all capabilities | Kernel zero-days. Consider gVisor or Kata for untrusted workloads. |
| **E**levation of privilege | Untested image reaches prod | `promote.yml`: prod accepts only the digest currently in dev; GitHub environment `prod` can require reviewers | — |

## Assumptions

- Branch protection on `main` in this repo and the application repos (required PR review, required status checks).
- The `prod` GitHub environment is configured with required reviewers.
- Kyverno runs with `failurePolicy: Fail` for image verification, so a registry or Rekor outage blocks new pods rather than admitting unverified ones.
