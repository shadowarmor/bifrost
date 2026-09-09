# Keep this fork current

The default fork branch is `shadowarmor/bifrost:dev`. Its upstream is `maximhq/bifrost:dev`.

## Automatic update pull requests

[Sync upstream Bifrost](https://github.com/shadowarmor/bifrost/actions/workflows/sync-upstream.yml) runs daily at 05:23 UTC (07:23 South Africa time), or through **Run workflow**. GitHub may delay scheduled runs. The job updates `sync/upstream-dev` by fast-forward only and creates one pull request into `dev`. Later runs update the same PR. It never force-pushes or automatically merges changes.

1. Review the upstream PR and resolve conflicts, retaining this fork's Azure README section, `infra/`, `deploy/`, `scripts/azure/` and workflows.
2. Run [Validate Azure deployment](https://github.com/shadowarmor/bifrost/actions/workflows/azure-deployment.yml) manually with the upstream PR number. It checks GitHub's merged PR ref with a read-only token; a merge conflict must be resolved first. GitHub normally suppresses other workflow triggers for PRs created with the built-in `GITHUB_TOKEN`.
3. Review applicable upstream checks and release notes. Use **Create a merge commit**. Squashing or rebasing sync PRs loses the recorded upstream ancestry and can make old changes appear again.

Repository Actions must be enabled and **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests** must be enabled. The workflow explicitly requests `contents: write` and `pull-requests: write`; the repository default can stay read-only. No personal access token or Azure credentials are required. GitHub can disable scheduled workflows in an inactive public repository after 60 days; re-enable this workflow if that occurs.

The sync job uses only GitHub API calls, not a checkout or execution of upstream code with its write token. Diverged mirror history, rewritten upstream history, permission failures and API errors fail the run rather than overwriting commits. Inspect failed runs before retrying. Keep manual work off `sync/upstream-dev`.

## Local remotes and pulls

Use `origin` for your fork and `upstream` for the original project:

```bash
git clone https://github.com/shadowarmor/bifrost.git
cd bifrost
git remote add upstream https://github.com/maximhq/bifrost.git
git switch dev
git pull --ff-only origin dev
```

After merging an automated sync PR on GitHub, `git pull --ff-only origin dev` brings those updates into your local checkout.

For a manual upstream update, start with a clean working tree:

```bash
git fetch upstream dev
git switch -c sync/manual-upstream origin/dev
git merge --no-ff upstream/dev
# Resolve conflicts, run relevant validation, then push the integration branch.
git push -u origin sync/manual-upstream
gh pr create --repo shadowarmor/bifrost --base dev --head sync/manual-upstream
```

Use a new integration branch name if the example already exists. Do not use `git reset --hard upstream/dev` or force-sync the fork: that would discard the Azure changes.

The authoring workspace was connected to these remotes with a sparse checkout covering the README, workflows, Azure files and config schema. Run `git sparse-checkout disable` from that workspace when you need the complete source tree; a normal fresh clone is already complete.

## Update the deployed Bifrost image

Source synchronization and a running Azure deployment are separate operations. The portal uses the official image digest recorded in `infra/image-lock.json`; source-only changes in this fork are not built into that image.

1. Choose a stable upstream transport release and review its migrations and configuration compatibility.
2. Resolve the matching Docker image tag to its immutable digest, verify `linux/amd64` support, then update `image-lock.json`.
3. Regenerate `infra/azuredeploy.json` with the pinned Bicep compiler, validate and commit both files.
4. Back up PostgreSQL and retain the current image digest and encryption key. Update the Azure deployment with the same environment name, resource group and existing secrets.
5. Test readiness, inference and streaming. A container rollback does not undo database migrations.

Changing the image lock does not redeploy Azure automatically. A deployment using the private-registry CLI path must also import the new digest into ACR before changing the running image.
