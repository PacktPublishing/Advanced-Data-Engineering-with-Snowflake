# Summary

<!-- One paragraph: what changed and why. Keep the PR under ten files and about
500 lines of SQL and YAML so the review fits in roughly thirty minutes. -->

## Models changed

<!-- List each model and the kind of data change: a new column, a new filter, a
changed materialization, a changed grain. -->

| Model | Change | Type of data change |
|-------|--------|---------------------|
|       |        |                     |

## Tests

- [ ] Generic tests added or updated for new columns
- [ ] Singular test added for any new cross-column or business invariant
- [ ] Unit test added or updated when transformation logic changed
- [ ] `dbt build --select state:modified+` passes locally (or `sqlmesh plan dev`)

## Row-count change

<!-- Paste the row counts before and after, per changed model. A model that
compiles, passes tests, and returns zero rows has a hidden bug. -->

| Model | Rows before | Rows after | Expected? |
|-------|-------------|------------|-----------|
|       |             |            |           |

## Diff output

<!-- dbt: paste or link the `audit_helper_compare` output from the CI run.
     SQLMesh: paste or link the `sqlmesh table_diff prod:dev` output. -->

## Contracts and interfaces

- [ ] No breaking change to a contracted model, or a new version was added
      (`versions:` entry plus `latest_version`) so consumers can migrate
- [ ] Column descriptions updated for anything new or renamed

## AI-assisted changes

<!-- If an assistant generated any of this, confirm the review checklist from
     Chapter 6, section 4.5. -->

- [ ] Every referenced column verified against the live catalog
- [ ] Filters compared against a similar existing model
- [ ] Materialization chosen deliberately, not inherited from the default
- [ ] Incremental and snapshot SQL reviewed line by line
