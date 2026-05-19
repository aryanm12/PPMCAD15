# Feature Branch -> Staging: Gated Merge Pipeline

A design walkthrough of a gated CI pipeline:

---

# Part 1 - The Question

## Original ask (paraphrased)

> A developer pushes code to their personal branch. That branch needs to merge into a shared `staging` branch. Before the merge happens, a pipeline must verify security, code quality, tests, and other checks. If everything passes, the merge proceeds. If anything fails, the responsible developer is notified by email.

## What's really being asked

This is a **gated integration** problem with five sub-problems:

| # | Sub-problem | What it really means |
|---|---|---|
| 1 | **Branch hygiene** | How do we name and structure branches so the pipeline knows which ones to validate? |
| 2 | **Trigger model** | When does the pipeline run? On every push? Only at merge time? Both? |
| 3 | **Validation stages** | What checks must pass, in what order, and which can run in parallel? |
| 4 | **Enforcement** | Who actually blocks the merge when a check fails? The pipeline, or something else? |
| 5 | **Feedback loop** | How does the right person learn about a failure quickly enough to fix it? |


## Constraints and assumptions worth stating for this question

- **Branch model:** trunk-based with short-lived feature branches, plus a shared `staging` integration branch and a `main` production branch.
- **Team size:** small-to-medium (this changes whether you need merge queues, covered later).
- **Cost sensitivity:** CI minutes cost money; we want fast feedback but not at the price of running every tool on every keystroke.

---

# Part 2 - Tool-Agnostic Answer

This section describes the design. Any modern CI system can implement it.

## 2.1 Branch strategy

**Rule:** personal-name branches (`vikram`, `john-stuff`) are an anti-pattern. They tell you *who* but not *what*, they don't survive team turnover (people joining and leaving the team over time. A good naming convention is one where the names still work after the people who created them are gone.), and most important can't be filtered by a pipeline trigger.

**Use prefix-based naming:**

```
main                        <- production, protected
  ↑ Always should be Pull Request (PR) gated
staging                     <- integration, protected, what This is the ask, which we will gate now
  ↑ PR (gated)
feature/<ticket>-<slug>     <- short-lived, one per unit of work
bugfix/<ticket>-<slug>
hotfix/<ticket>-<slug>
chore/<slug>
```

The prefix is what lets the CI system match `feature/**`, `bugfix/**`, `hotfix/**` with a glob. The ticket ID gives traceability back to a tracker.

## 2.2 The two-trigger model

**This is the most important architectural decision.** Run two pipelines, not one:

| Pipeline | When it runs | Goal | Target duration |
|---|---|---|---|
| **A - Fast feedback** | On every push to a feature branch | Catch obvious failures early; keep the developer in flow | <=> 5 min |
| **B - Merge gate** | When a PR is opened/updated against `staging` | The full validation suite; this is the gate | <= 20 min |

Why two? 
-> Because a single heavy pipeline on every push wastes CI minutes and slows developers down

-> A single light pipeline at PR time provides no early feedback. 

-> The split lets each pipeline have one clear purpose.

**Pipeline A - fast feedback (push to `feature/**`):**
- Compile / build
- Lint / format check
- Unit tests
- Secret scan (cheap, fast)

**Pipeline B - merge gate (PR to `staging`):**
- Everything from A
- SAST (static application security testing)
- SCA (software composition analysis - third-party dependencies)
- Container scan (if applicable)
- Code quality + coverage gate
- Integration tests
- (Optionally) deploy to ephemeral preview env and smoke test

## 2.3 Validation stages in Pipeline B

Run scanners in **parallel jobs**, not sequentially. A failing SAST scan shouldn't prevent the developer from also seeing failing tests in the same run, all the problems should be visible at once, not one at a time.

```
                    ┌─-> build + unit tests
                    ├─-> SAST (CodeQL / Semgrep)
   PR opened ─────> ├─-> SCA (Snyk / Dependabot /OSV-Scanner)
                    ├─-> secret scan
                    ├─-> container scan (Trivy) depends on build
                    ├─-> code quality gate (SonarQube)
                    └─-> integration tests, depends on build
                                │
                                ▼
                    All green? -> merge enabled
                    Any red?   -> notify author, merge blocked
```

## 2.4 Tool selection - pick a stack, don't run them all

There is heavy overlap between security tools. Running CodeQL + Snyk Code + SonarQube SAST all at once finds 90% of the same issues three times and triples your CI bill.

| Category | Free / cheap option | Premium option | Notes |
|---|---|---|---|
| **SAST** | CodeQL (free on public repos), Semgrep OSS | Snyk Code, SonarQube Enterprise, Checkmarx | Pick **one**. CodeQL is excellent if you have GitHub Advanced Security; Semgrep is the strong OSS alternative |
| **SCA (3rd party dependencies check)** | Dependabot, OSV-Scanner, Trivy fs | Snyk Open Source, Sonatype Nexus IQ | Dependabot opens fix PRs automatically - keep it on regardless |
| **Secret scanning** | Gitleaks, GitHub native | GitGuardian | Both pipelines should run this - secrets in commits are catastrophic |
| **Container** | Trivy (open source) | Snyk Container, Wiz | Trivy is the default; pin to commit SHA (see §2.7) |
| **Quality / coverage** | SonarQube Community | SonarQube Developer/Enterprise, Codacy | The quality *gate* is the value - coverage thresholds that fail the build |

**Sensible default stack** for a private team-sized repo:
- Semgrep (SAST)
- Dependabot + Snyk Open Source (SCA, two layers because SCA is where vulns actually live)
- Gitleaks (secrets)
- Trivy (containers, if you ship them)
- SonarQube Enterprise or OSS (quality gate)

Five tools, distinct jobs, minimal overlap.

## 2.5 Enforcement - the pipeline does *not* block the merge

A CI pipeline only **reports** status (green/red). What actually **blocks the merge button** is a separate mechanism in the platform:

| Platform | Mechanism |
|---|---|
| GitHub | Branch protection rules or Rulesets (required status checks) |
| GitLab | Protected branches + "Pipelines must succeed" + push rules |
| Bitbucket | Branch permissions + merge checks |
| Azure DevOps | Branch policies + required build validation |
| Jenkins-fronted | Usually GitHub/GitLab does the gating; Jenkins reports the status |

Without the platform-level gate, a red pipeline is **advisory only** - anyone with push access could merge anyway. So the design has two halves:

1. **Pipeline:** runs checks, publishes pass/fail per job
2. **Platform protection rule:** lists the job names whose pass status is *required* before the merge button is enabled

These must be configured together. A name change in the pipeline silently breaks the gate.

## 2.6 Feedback - notifying the right person

Most CI systems already email the commit author on failure by default. That's often enough. When you want richer notifications:

| Channel | When to use it |
|---|---|
| **Default platform email** | Solo work, simple flow |
| **Custom email step (SMTP/SES/SendGrid)** | When you need rich HTML, multiple recipients, or routing by branch prefix |
| **Slack / Teams DM or channel** | Highest signal - devs read chat faster than email |
| **PR comment** | Visible to reviewers too, not just the author |
| **Status badge / dashboard** | For team-wide visibility, low individual urgency |

A reasonable pattern: **PR comment for normal failures + Slack channel ping if `main`/`staging` itself breaks.**

## 2.7 Cross-cutting hardening principles

These apply regardless of tool choice:

- **Default-deny permissions.** CI tokens should have the minimum scope needed per job.
- **Concurrency control.** Cancel in-progress runs when a new commit lands on the same branch - saves cost and avoids stale results.
- **No secrets on untrusted code paths.** If you accept PRs from forks, never expose secrets to workflows that check out PR head code.
- **Required signed commits + linear history** on protected branches for auditability.
- **CODEOWNERS** so the right humans (not just any approver) review sensitive paths.

## 2.8 The full flow, end to end

```
1.  Dev branches:  feature/JIRA-1234-add-payment-api  from  staging
2.  Dev pushes commits
        -> Pipeline A runs (fast feedback, <5 min)
        -> green/red shown on commit
3.  Dev opens PR  ->  staging
        -> Pipeline B runs (full pipeline, parallel jobs, <20 min)
4.  Outcome:
    a. All green + required reviewer approved + branch up-to-date
           -> merge button enabled
           -> Lead (or auto-merge bot) merges (squash or rebase for linear history)
           -> feature branch auto-deleted
           -> merge to staging triggers a separate deploy workflow (out of scope here)
    b. Any check red
           -> notify-on-failure job fires (email/Slack/PR comment)
           -> platform protection rule keeps merge button disabled
           -> dev fixes, pushes again -> back to step 2
```

That's the full design. Now we implement it.

---

# Part 3 - Reference Implementation in GitHub Actions

The architecture above maps cleanly onto GitHub Actions. The mapping:

| Design concept | GitHub Actions construct |
|---|---|
| Pipeline A trigger | `on: push: branches: ['feature/**', ...]` |
| Pipeline B trigger | `on: pull_request: branches: [staging]` |
| Parallel scanner jobs | Independent `jobs:` (no `needs:` between them) |
| Sequential dependency | `jobs.<name>.needs: [other-job]` |
| Cost control | `concurrency:` block, `cancel-in-progress: true` |
| Default-deny perms | `permissions:` block at workflow or job level |
| Platform enforcement | Branch protection rule on `staging` listing required job names |
| Failure notification | A job with `if: failure()` and `needs: [...all gating jobs]` |

## 3.1 Sample Pipeline A - fast feedback

`.github/workflows/feature-push.yml`

```yaml
name: Feature Branch CI

on:
  push:
    branches:
      - 'feature/**'
      - 'bugfix/**'
      - 'hotfix/**'

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  fast-checks:
    name: fast-checks
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Set up JDK
        uses: actions/setup-java@8df1039502a15bceb9433410b1a100fbe190c53b  # v4.5.0
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Compile
        run: mvn -B compile

      - name: Lint
        run: mvn -B spotless:check

      - name: Unit tests
        run: mvn -B test

      - name: Secret scan
        uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7  # v2.3.6
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 3.2 Sample Pipeline B - merge gate

`.github/workflows/pr-to-staging.yml`

```yaml
name: PR to Staging

on:
  pull_request:
    branches: [staging]
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read
  security-events: write
  pull-requests: write
  actions: read

jobs:
  build-and-test:
    name: build-and-test
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          fetch-depth: 0   # SonarQube needs full history for blame
      - uses: actions/setup-java@8df1039502a15bceb9433410b1a100fbe190c53b  # v4.5.0
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      - name: Build + test + coverage
        run: mvn -B verify
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@b4b15b8c7c6ac21ea08fcf65892d2ee8f75cf882  # v4.4.3
        with:
          name: test-results
          path: '**/target/surefire-reports/'

  # SAST - Semgrep OSS replaces CodeQL.
  # Free on private repos (no GHAS license needed). Use the `auto` config to
  # pull in language-appropriate rule packs, or pin to specific packs like
  # `p/owasp-top-ten`, `p/java`, `p/security-audit` for reproducibility.
  sast-semgrep:
    name: sast-semgrep
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      security-events: write
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - name: Semgrep scan
        uses: semgrep/semgrep-action@713efdd345f3035192eaa63f56867b88e63e4e5d  # v1
        with:
          config: >-
            p/security-audit
            p/owasp-top-ten
            p/java
          # Fail the build on any finding of ERROR severity.
          # Adjust as you triage: use --severity=ERROR initially, broaden later.
          generateSarif: "1"
      - name: Upload Semgrep SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@4e828ff8d448a8a6e532957b1811f387a63867e8  # v3.27.4
        with:
          sarif_file: semgrep.sarif

  # A leaked secret on a PR is high-impact enough that it should block merge, not
  # just warn on push.
  secrets-scan:
    name: secrets-scan
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          fetch-depth: 0   # Gitleaks scans full history; shallow checkout misses commits
      - name: Gitleaks scan
        uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7  # v2.3.6
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # SCA - Snyk Open Source.
  # Note: Dependabot is NOT a CI job. It runs independently from
  # .github/dependabot.yml and opens PRs for vulnerable / outdated dependencies.
  # Snyk here is the *gating* SCA layer: it blocks this PR if a high-severity
  # dependency vulnerability is detected at merge time.
  sca-dependencies:
    name: sca-dependencies
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-java@8df1039502a15bceb9433410b1a100fbe190c53b  # v4.5.0
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      - name: Snyk dependency scan
        uses: snyk/actions/maven@cdb760004ba9ea4d525f2e043745dfe85bb9077e  # master pinned
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high --fail-on=upgradable

  # Container scan - only meaningful if the service ships a container image.
  # Remove this job entirely for non-containerized apps (libraries, plain JARs, etc).
  container-scan:
    name: container-scan
    runs-on: ubuntu-latest
    timeout-minutes: 10
    needs: build-and-test
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - name: Build image
        run: docker build -t app:${{ github.sha }} .
      - name: Trivy scan
        uses: aquasecurity/trivy-action@18f2510ee396bbf400402947b394f2dd8c87dbb0  # SHA-pinned - see hardening note
        with:
          image-ref: app:${{ github.sha }}
          severity: CRITICAL,HIGH
          exit-code: '1'
          ignore-unfixed: true
          format: sarif
          output: trivy.sarif
      - name: Upload Trivy SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@4e828ff8d448a8a6e532957b1811f387a63867e8  # v3.27.4
        with:
          sarif_file: trivy.sarif

  # Quality gate - SonarQube.
  # Use SonarQube Developer/Enterprise (paid) for deeper SAST and branch analysis.
  # Use SonarQube Community (self-hosted, free) for OSS deployment 
  code-quality:
    name: code-quality
    runs-on: ubuntu-latest
    timeout-minutes: 15
    needs: build-and-test
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          fetch-depth: 0
      - uses: actions/setup-java@8df1039502a15bceb9433410b1a100fbe190c53b  # v4.5.0
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      - name: SonarQube scan
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
        run: |
          mvn -B verify sonar:sonar \
            -Dsonar.projectKey=my-project \
            -Dsonar.qualitygate.wait=true

  notify-on-failure:
    name: notify-on-failure
    runs-on: ubuntu-latest
    needs: [build-and-test, sast-semgrep, secrets-scan, sca-dependencies, container-scan, code-quality]
    if: failure()
    steps:
      - name: Email PR author
        uses: dawidd6/action-send-mail@2cea9617b09d79a095af21254fbcb7ae95903dde  # v3.12.0
        with:
          server_address: smtp.gmail.com
          server_port: 465
          secure: true
          username: ${{ secrets.SMTP_USERNAME }}
          password: ${{ secrets.SMTP_PASSWORD }}
          subject: "❌ PR #${{ github.event.pull_request.number }} failed checks"
          to: ${{ github.event.pull_request.user.email }}
          from: CI Bot <ci@example.com>
          html_body: |
            <h2>Your PR failed one or more required checks</h2>
            <p><b>PR:</b> <a href="${{ github.event.pull_request.html_url }}">#${{ github.event.pull_request.number }} - ${{ github.event.pull_request.title }}</a></p>
            <p><b>Branch:</b> ${{ github.head_ref }} -&gt; ${{ github.base_ref }}</p>
            <p><b>Run:</b> <a href="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}">View details</a></p>
```

## 3.3 Platform enforcement - branch protection

In **Settings -> Branches -> Add branch protection rule** for `staging`:

- ☑ Require a pull request before merging (1+ approvals, dismiss stale)
- ☑ Require status checks to pass before merging
  - ☑ Require branches to be up to date
  - Required checks (these are the **job names** from Pipeline B):
    - `build-and-test`
    - `sast-codeql`
    - `sca-dependencies`
    - `container-scan`
    - `code-quality`
- ☑ Require conversation resolution before merging
- ☑ Require linear history
- ☑ Do not allow bypassing the above settings

Without this step, Pipeline B's output is advisory only. Anyone with push could still merge a red PR.

## 3.4 GitHub Actions–specific gotchas

- **Job name = required-check name.** Rename a job and you silently break the gate. Pick names you won't change.
- **Skipped jobs report as "Success".** A job filtered out by `if:` or path filter won't block the merge - but a workflow entirely filtered out stays "Pending" forever. If you use path filters on a required workflow, add a status-aggregator job that always runs.
- **`pull_request_target`** changed semantics on 2025-12-08; it now always uses the default branch's workflow file. Use plain `pull_request` unless you specifically need secrets on fork PRs.
- **Pin third-party actions to SHAs**, not tags. The Trivy supply-chain compromise (March 2026) is the canonical cautionary tale.

---