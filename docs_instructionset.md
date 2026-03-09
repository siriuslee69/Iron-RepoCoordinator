# iron Docs Instructionset

Use this workflow whenever an agent modifies library code:

1. Update `.iron/pipeline.json` with current steps and statuses.
2. Keep dependencies explicit in the `children` tree.
3. Set status values to one of: `todo`, `active`, `done`, `blocked`, `failed`.
4. Run `iron show` in a separate terminal while editing.
5. After edits, run `iron docs` to regenerate API map + JSON bridge.

Commands:

- `iron docs --repo .`
- `iron docs --repo . --src ./src --docs-out ./.iron/docs/library_api.md`
- `iron show --pipeline ./.iron/pipeline.json --interval-ms 700`
- `iron show --pipeline ./.iron/pipeline.json --once`

JSON tree requirements for `iron show`:

- Root object may define `name`, `description`, and `root`.
- Each node uses: `id`, `label`, `status`, `details`, `children`.
- `children` is an array of nested nodes.

Maintenance rule:

- If pipeline shape changed, update this instructionset and regenerate docs.
