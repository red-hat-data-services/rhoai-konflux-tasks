# create-jira-on-build-failure

Tekton Task that automatically creates or updates a Jira issue in RHOAIENG when a Konflux pipeline fails.

## Behavior

- **One card per component per version**: Deduplicates by Konflux component name + RHOAI version. If an open card already exists for the same component and version, a comment is added instead of creating a duplicate.
- **Smart component assignment**: If the build task (`build-container` or `build-images`) failed, the Jira issue is assigned to the component team's Jira component using the mapping in [konflux-central `config/component-jira-mapping.yaml`](https://github.com/red-hat-data-services/konflux-central/blob/main/config/component-jira-mapping.yaml). If a different task failed (scans, prefetch, SAST, etc.), the issue is assigned to `DevOps`.
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
| `component-mapping-url` | No | konflux-central `main` mapping YAML | URL of the Konflux-to-Jira mapping (single source of truth in konflux-central) |

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
2. `rhoai-init.results.cluster-mismatch == false` (expected cluster)
3. `params.enable-jira-failure-notification == true` (not opted out)

### Opt-Out

To disable Jira notifications for a specific component, add to its PipelineRun YAML:
```yaml
- name: enable-jira-failure-notification
  value: "false"
```

## Component Mapping

The mapping lives in **one place**: [`konflux-central/config/component-jira-mapping.yaml`](https://github.com/red-hat-data-services/konflux-central/blob/main/config/component-jira-mapping.yaml).

The task fetches that file at runtime (`component-mapping-url`). Do not duplicate entries in this task.

To add or change a component:
1. Check the latest `ps_modules.json` `openshift-ai.components.override` in prodsec product-definitions
2. Update only `konflux-central/config/component-jira-mapping.yaml`
