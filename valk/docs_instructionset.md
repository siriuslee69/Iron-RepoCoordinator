# Valkyrie Docs Instructionset

Use this workflow whenever an agent modifies library code:

1. Update `valk/pipeline.json` with current steps and statuses.
2. Keep dependencies explicit in the `children` tree.
3. Set status values to one of: `todo`, `active`, `done`, `blocked`, `failed`.
4. Run `val show` in a separate terminal while editing.
5. After edits, run `val docs` to regenerate API map + JSON bridge.

Commands:

- `val docs --repo .`
- `val docs --repo . --src ./src --docs-out ./valk/docs/library_api.md`
- `val show --pipeline ./valk/pipeline.json --interval-ms 700`
- `val show --pipeline ./valk/pipeline.json --once`

JSON tree requirements for `val show`:

- Root object may define `name`, `description`, and `root`.
- Each node uses: `id`, `label`, `status`, `details`, `children`.
- `children` is an array of nested nodes.

Maintenance rule:

- If pipeline shape changed, update this instructionset and regenerate docs.
