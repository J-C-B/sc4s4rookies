---
name: sc4s4rookies-builder-header
description: >-
  Bumps the Version line and refreshes the Last updated date/time in
  sc4rookies_builder_ubuntu2404_no_splunk.sh before finishing edits or commits.
  Use when changing that script, when the user asks to commit or release, or
  when they mention version, changelog, or script header metadata for sc4s4rookies.
---

# sc4s4rookies builder — header version and date

## When to apply

Whenever `sc4rookies_builder_ubuntu2404_no_splunk.sh` is modified, or the user is about to commit / tag changes that touch this repo’s builder, **update the script header** unless the user explicitly says to skip it.

## Header format (keep consistent)

At the top of `sc4rookies_builder_ubuntu2404_no_splunk.sh`, after the shebang:

```text
# Last updated: <YYYY-MM-DD HH:MM TZ>
# Version <major>.<minor>.<patch>
```

Use the **user’s machine local time** (run `date` in the project environment or ask once if unclear). Preserve their timezone style (e.g. `NZST`, `UTC`) if already present; otherwise use what `date '+%Y-%m-%d %H:%M %Z'` prints.

## Version bumps (semver)

| Change type | Bump |
|-------------|------|
| Typos, comments, docs-only in header/README, trivial fixes | **Patch** (`2.0.0` → `2.0.1`) |
| New behavior, new prompts, dependency URL changes, meaningful script logic | **Minor** (`2.0.1` → `2.1.0`) |
| Breaking behavior, OS/target change, removed steps users relied on | **Major** (`2.1.0` → `3.0.0`) |

If multiple commits land in one session, bump **once** to reflect the **net** change going out, not every intermediate edit.

## Checklist before commit

- [ ] `# Last updated:` reflects **now** (date + time + zone).
- [ ] `# Version` incremented per table above (or user-supplied version).
- [ ] If only `README.md` / `.cursor/` / non-runtime files changed, **still** bump header when the builder script was edited; if **only** docs changed and the `.sh` file was not touched, header update is optional.

## Do not

- Do not embed a fake or stale date; always align **Last updated** with the edit or commit moment.
- Do not skip version bumps on substantive `.sh` changes just because the user did not mention it.
