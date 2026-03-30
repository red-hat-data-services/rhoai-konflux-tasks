# add-oci-annotations

A Tekton Task that adds OCI manifest annotations to a previously pushed OCI artifact (e.g., a Helm chart).

## Why

The `build-helm-chart-oci-ta` task uses `helm push`, which does not support injecting custom annotations or labels into the OCI manifest. This task fills that gap by patching the manifest after the push, similar to how `buildah` supports a `LABELS` parameter for container image builds.

## How it works

1. Pulls the OCI artifact from the registry into a local [OCI image layout](https://github.com/opencontainers/image-spec/blob/main/image-layout.md) using `skopeo copy`
2. Patches the manifest's `.annotations` field with the provided key-value pairs using `jq` (existing annotations are preserved)
3. Recalculates the manifest digest and updates the OCI layout index
4. Pushes the modified artifact back to the same image reference using `skopeo copy`

The chart content (layers, config) is unchanged -- only the manifest metadata is modified. The registry deduplicates the identical blobs, so only the new manifest is actually uploaded.

**Important:** The manifest digest will change as a result of the modification. Downstream tasks should consume this task's `IMAGE_DIGEST` result rather than the original build task's digest.

## Parameters

| Name | Type | Description |
|------|------|-------------|
| `IMAGE_URL` | `string` | Full image reference, e.g. `quay.io/org/repo:tag` |
| `ANNOTATIONS` | `array` | Annotations to add, each in `key=value` format |

## Results

| Name | Description |
|------|-------------|
| `IMAGE_URL` | Image URL (same as input) |
| `IMAGE_DIGEST` | New SHA256 digest of the annotated manifest |

## Usage

Reference the task via the git resolver in your pipeline:

```yaml
- name: add-oci-annotations
  params:
    - name: IMAGE_URL
      value: $(tasks.build-helm-chart.results.IMAGE_URL)
    - name: ANNOTATIONS
      value:
        - "com.redhat.component=my-component"
        - "vendor=Red Hat, Inc."
        - "version=v1.0.0"
  runAfter:
    - build-helm-chart
  taskRef:
    resolver: git
    params:
      - name: url
        value: https://github.com/red-hat-data-services/rhoai-konflux-tasks.git
      - name: revision
        value: <commit-sha>
      - name: pathInRepo
        value: konflux-tekton-tasks/add-oci-annotations/0.1/add-oci-annotations.yaml
```

Downstream tasks should reference the annotated image:

```yaml
- name: some-scan-task
  params:
    - name: image-url
      value: $(tasks.add-oci-annotations.results.IMAGE_URL)
    - name: image-digest
      value: $(tasks.add-oci-annotations.results.IMAGE_DIGEST)
  runAfter:
    - add-oci-annotations
```

## Testing locally

You can verify the task logic without Konflux by running the script against a local registry:

```bash
# Start a local registry
podman run -d -p 5050:5000 --name test-registry registry:2

# Create and push a test chart
helm create test-chart
helm package test-chart
helm push test-chart-0.1.0.tgz oci://localhost:5050/test --plain-http

# Check manifest before
skopeo inspect --raw --tls-verify=false docker://localhost:5050/test/test-chart:0.1.0 | jq .annotations

# Run the annotation logic (add --src-tls-verify=false / --dest-tls-verify=false
# to the skopeo copy commands in the script for local HTTP registries)

# Check manifest after
skopeo inspect --raw --tls-verify=false docker://localhost:5050/test/test-chart:0.1.0 | jq .annotations

# Verify chart is still pullable
helm pull oci://localhost:5050/test/test-chart --version 0.1.0 --plain-http

# Cleanup
podman rm -f test-registry
```
