# rhoai-init Quay tagging safeguards (RHOAIENG-97056)

## Context sources

| Input | Source | Notes |
| --- | --- | --- |
| Event type (`pull_request` / `push`) | PipelineRun annotation `pipelinesascode.tekton.dev/event-type` | Also mirrored in `results.tekton.dev/recordSummaryAnnotations` (`eventType`) for legacy detection in 0.1 slack/CPE logic |
| Governing repository | `pipelinesascode.tekton.dev/repo-url` | Target repository for PAC (fork PRs keep RHDS target URL; `source-repo-url` is the fork clone source and is not used for authorization) |
| Build branch | `build.appstudio.redhat.com/target_branch` | Matches release branch names such as `rhoai-3.6` and `rhoai-3.6-ea.1` |
| Primary publication image | Task param `image-output` (pipeline `output-image`) | Parsed into registry, namespace, name, and tag |
| Additional publication tags | Task param `additional-tags` (pipeline `additional-tags`) | Tag strings only; validated with the same rules as the primary tag |

## Execution order

`rhoai-init` remains the first task in RHOAI container/FBC pipelines (`runBefore` clone/build). Safeguards run immediately after required parameters are present and **before** CPE derivation, Slack formatting, or any downstream task (including `init` / `buildah` / `apply-tags`).

## Interface change

Version **0.4** adds optional `additional-tags` (array, default `[]`). Konflux-central pipeline CRDs pass `$(params.additional-tags[*])` into `rhoai-init` so additional tags cannot bypass validation.

## Tests

`konflux-tekton-tasks/rhoai-init/scripts/validate-quay-tagging_test.sh` exercises the shared shell logic used in 0.4.
