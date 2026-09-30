# create-jira-on-build-failure

Tekton Task that automatically creates or updates a Jira issue in RHOAIENG when a Konflux pipeline fails.

## Behavior

- **One card per component per version**: Deduplicates by Konflux component name + RHOAI version. If an open card already exists for the same component and version, a comment is added instead of creating a duplicate.
- **Smart component assignment**: If the build task (`build-container` or `build-images`) failed, the Jira issue is assigned to the component team's Jira component (via embedded mapping from `ps_modules.json`). If a different task failed (scans, prefetch, SAST, etc.), the issue is assigned to `DevOps`.
- **Labels**: Every card gets `rhoai-sustaining` and `zstream-build-failure`, plus `component:<base-name>` and `version:<rhoai-version>` for dedup.
- **Metadata attachment**: A `build-failure-metadata.yaml` file is attached with structured build data.
- **All relevant links** are included in the Jira description:
  - Build Log (PipelineRun logs on Konflux console)
  - Commit (GitHub commit that triggered the build)
  - GitHub Repo (source repository)
  - Konflux Component (component page in Konflux console)

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `component-name` | Yes | | Konflux component name (e.g., `odh-kserve-controller-v3-4`) |
| `display-name` | No | `""` | Human-readable display name from `rhoai-init` |
| `rhoai-version` | Yes | | RHOAI version (e.g., `3.4` or `3.4.1`) |
| `pipelinerun-name` | Yes | | PipelineRun name |
| `git-url` | Yes | | Source repository URL |
| `revision` | Yes | | Git commit SHA |
| `output-image` | Yes | | Fully qualified output image reference |
| `build-task-status` | Yes | | Status of the build task (`Failed`/`Succeeded`/`None`) |
| `jira-project` | No | `RHOAIENG` | Jira project key |
| `dry-run` | No | `false` | When `true`, logs actions without hitting Jira |

## Results

| Result | Description |
|---|---|
| `jira-issue-key` | Created/updated Jira issue key (empty if failed or skipped) |
| `jira-action` | `created`, `updated`, or `skipped` |

## Secret Setup

The task requires a Kubernetes secret named `rhoai-jira-automation` in each tenant namespace.

### Required Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rhoai-jira-automation
  namespace: <tenant-namespace>
type: Opaque
stringData:
  token: "<jira-personal-access-token>"
```

### Setup Steps

1. **Create a Jira service account** (or use an existing one) with permission to:
   - Search issues (`/rest/api/2/search`)
   - Create issues (`/rest/api/2/issue`)
   - Add comments (`/rest/api/2/issue/{key}/comment`)
   - Add attachments (`/rest/api/2/issue/{key}/attachments`)

2. **Generate a Personal Access Token (PAT)** at:
   `https://issues.redhat.com/secure/ViewProfile.jspa` > Personal Access Tokens

3. **Create the secret in both tenants**:

   ```bash
   # Public tenant
   oc create secret generic rhoai-jira-automation \
     --from-literal=token="<YOUR_JIRA_PAT>" \
     -n rhoai-tenant

   # Private tenant
   oc create secret generic rhoai-jira-automation \
     --from-literal=token="<YOUR_JIRA_PAT>" \
     -n rhoai-private-tenant
   ```

4. **Verify** the secret is accessible:
   ```bash
   oc get secret rhoai-jira-automation -n rhoai-tenant
   oc get secret rhoai-jira-automation -n rhoai-private-tenant
   ```

## Pipeline Integration

The task is wired into the `finally` block of both shared pipelines:

- `container-build.yaml` — `build-task-status` = `$(tasks.build-container.status)`
- `multi-arch-container-build.yaml` — `build-task-status` = `$(tasks.build-images.status)`

### When Conditions

The task only runs when:
1. `pipeline-success-indicator.status != Succeeded` (pipeline failed)
2. `rhoai-init.results.skip-slack-message == false` (not a PR pipeline)
3. `params.disable-jira-notifications != true` (not opted out)

### Opt-Out

To disable Jira notifications for a specific component, add to its PipelineRun YAML:
```yaml
- name: disable-jira-notifications
  value: "true"
```

## Component Mapping

The embedded mapping (169 entries) is derived from:
- `gitlab.cee.redhat.com/prodsec/product-definitions` — `ps_modules.json` `openshift-ai.components.override`
- 7 manual overrides for components not in `ps_modules.json`

A reference copy of the mapping is maintained at `konflux-central/config/component-jira-mapping.yaml`.

To update the mapping when new components are added:
1. Check the latest `ps_modules.json` for the `openshift-ai` module
2. Update the `declare -A COMPONENT_MAP` in the task script
3. Update `konflux-central/config/component-jira-mapping.yaml`
