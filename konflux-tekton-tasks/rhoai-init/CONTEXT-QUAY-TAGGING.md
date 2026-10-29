# rhoai-init Quay tagging safeguards (RHOAIENG-97056)

## Context sources

| Input | Source | Notes |
| --- | --- | --- |
| Event type (PR-like / push-like) | PipelineRun annotation `pipelinesascode.tekton.dev/event-type` | **Push-like** (`push`, `incoming`): release publication rules. **PR-like** (`pull_request`, `pull_request_labeled`, `on-comment`, `retest-comment`, `test-comment`): no release tags to `quay.io/rhoai`. `on-comment` is PaC for `/build-konflux` and similar comment triggers. Also mirrored in `results.tekton.dev/recordSummaryAnnotations` (`eventType`) for legacy slack/CPE logic in rhoai-init. |
| Governing repository | `pipelinesascode.tekton.dev/repo-url` | Target repository for PAC (fork PRs keep RHDS target URL; `source-repo-url` is the fork clone source and is not used for authorization) |
| Build branch | `build.appstudio.redhat.com/target_branch` | Matches release branch names such as `rhoai-3.6` and `rhoai-3.6-ea.1` |
| Primary publication image | Task param `image-output` (pipeline `output-image`) | Parsed into registry, namespace, name, and tag |
| Additional publication tags | Task param `additional-tags` (pipeline `additional-tags`) | Forwarded via step `args` (`$(params.additional-tags[*])`) because Tekton does not expand array params in `env.value`; assembled as `ADDITIONAL_TAGS` in the script before validation |

## Execution order

`rhoai-init` remains the first task in RHOAI container/FBC pipelines (`runBefore` clone/build). Safeguards run immediately after required parameters are present and **before** CPE derivation, Slack formatting, or any downstream task (including `init` / `buildah` / `apply-tags`).

## Interface change

Version **0.4** adds optional `additional-tags` (array, default `[]`). Konflux-central pipeline CRDs pass `$(params.additional-tags[*])` into `rhoai-init` so additional tags cannot bypass validation.

## Tests

`konflux-tekton-tasks/rhoai-init/scripts/validate-quay-tagging_test.sh` exercises the shared shell logic used in 0.4.
