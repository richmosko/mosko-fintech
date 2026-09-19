— because `PGRST_DB_SCHEMAS=public,graphql_public,pfin` is correct.

Some other place, an operator's shell snippet quotes the value: `PGRST_DB_SCHEMAS="pfin"` or, in a single-quoted form, `PGRST_DB_SCHEMAS='public,graphql_public'` — both wrong, both quoted, and both must be caught even though a correct unquoted example is also present in this same file.
