# AGENTS

Project guidance for Codex and collaborating agents in this repository.

## General

- Prefer concise, implementation-first responses: make the change, then summarize briefly.
- Keep explanations short and actionable.
- State assumptions explicitly when needed, and ask only essential clarifying questions.

## Environment

- Primary OS is Windows.
- Prefer PowerShell-native commands and scripts for automation tasks.
- Preserve compatibility with Windows PowerShell 5.1 unless this repo explicitly targets PowerShell 7+.

## Code Changes

- Make minimal, surgical edits that solve the root cause.
- Preserve existing naming, file structure, and public interfaces unless change is requested.
- Avoid unrelated refactors, new dependencies, and formatting churn.
- Keep scripts idempotent where practical, and fail with clear errors.

## PowerShell Conventions

- Use approved verbs and clear parameter names.
- Prefer `-ErrorAction Stop` in operational paths where failures should halt execution.
- Validate user input and file paths before side effects.
- Never write secrets to logs or console output.

## Workflow

- Use feature/bugfix branches for work; avoid direct commits to `main`, `master`, or `develop`.
- Before significant changes, provide a short plan and confirm direction.
- After edits, run the smallest relevant validation first, then broaden only as needed.
- If validation cannot run, state exactly what was not run and why.

## Codebase Exploration (jcodemunch)

Use jcodemunch tools first for codebase exploration and navigation. These are registered as pi extension tools with the `jcodemunch_` prefix. Fall back to other search tools only after a relevant jcodemunch attempt cannot answer.

If the repo is not yet indexed, run `jcodemunch_index_folder` with path `D:/code/adlabv2` before anything else. The index persists across sessions in `~/.code-index/`.

Preferred order:
1. `jcodemunch_list_repos` — confirm the repo is indexed
2. `jcodemunch_get_repo_outline` or `jcodemunch_get_file_tree` — broad discovery
3. `jcodemunch_search_symbols` — find functions, classes, methods by name or keyword
4. `jcodemunch_get_symbol` / `jcodemunch_get_symbols` or `jcodemunch_get_file_content` — targeted reads
5. `jcodemunch_search_text` — string-level fallback when symbol search is insufficient
6. `jcodemunch_get_file_outline` — inspect a specific file's symbol hierarchy without reading the full file

Rules:
- Do not start with generic grep/file search when jcodemunch can answer.
- For broad discovery, start with repo outline before deep reads.
- For implementation lookups, prefer `jcodemunch_search_symbols` before `jcodemunch_search_text` or bash grep.
- After significant code changes, run `jcodemunch_invalidate_cache` then re-index so the index stays accurate.
- When delegating to subagents, require the same jcodemunch-first workflow.
- If the user explicitly requests another tool, follow that request.
