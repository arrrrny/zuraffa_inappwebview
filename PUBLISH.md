# Publish Configuration for `zuraffa_inappwebview`

<!-- Managed with the publish-manager skill. Edit if the workflow changes. -->

## Package Manager

- **Type**: `pub.dev`
- **Packages** (in publish order — the app package first; the platform core
  and the federated adapters declare their in-family dependencies hosted):
1. `zuraffa_inappwebview`
2. `zuraffa_inappwebview_platform`
3. `zuraffa_inappwebview_android`
4. `zuraffa_inappwebview_ios`
5. `zuraffa_inappwebview_macos`
- **All packages are public**

## Scripts

- **Pre-publish**: `./scripts/prepare_for_publish.sh <version>` — creates `publish-<version>` branch, bumps all package versions + in-family constraints, propagates the root CHANGELOG entry into each package, commits
- **Publish**: `./scripts/publish.sh` — dry-run + publish per package in order, waits for pub.dev propagation (needs flutter/dart on PATH)
- **Post-publish**: `./scripts/push_to_master.sh -f` — merges the publish branch to master, tags, pushes, deletes the branch
- **Restore dev**: not needed — `dependency_overrides` are stripped by pub on publish; nothing to convert back

## Workflow

1. Write the release notes as a `## <version>` entry at the TOP of the root `CHANGELOG.md`
2. `./scripts/prepare_for_publish.sh <version>`
3. `git push origin publish-<version>`
4. `bash scripts/publish.sh` (allow 10-30 min: propagation waits between packages)
5. `bash scripts/push_to_master.sh -f`

## Notes

- `zikzak`-style sibling path overrides never need converting: pub ignores `dependency_overrides` when publishing.
- Sibling packages fail `dart pub publish --dry-run` until their hosted in-family dependencies exist on pub.dev — publish in order and each dry-run goes green in turn.
