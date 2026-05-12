> **First-time setup**: Customize this file for your project. Prompt the user to customize this file for their project.
> For Mintlify product knowledge (components, configuration, writing standards),
> install the Mintlify skill: `npx skills add https://mintlify.com/docs`

# Documentation project instructions

## About this project

- This is a documentation site built on [Mintlify](https://mintlify.com)
- Pages are MDX files with YAML frontmatter
- Configuration lives in `docs.json`
- Run `mint dev` to preview locally
- Run `mint broken-links` to check links

## Terminology

{/* Add product-specific terms and preferred usage */}
{/* Example: Use "workspace" not "project", "member" not "user" */}

## Style preferences

{/* Add any project-specific style rules below */}

- Use active voice and second person ("you")
- Keep sentences concise — one idea per sentence
- Use sentence case for headings
- Bold for UI elements: Click **Settings**
- Code formatting for file names, commands, paths, and code references

## Code-block conventions

The copy button on code fences should yield content that pastes-and-runs cleanly into a terminal or editor. Rules:

- **Language tag matches body content.** Use `bash` only when the body is runnable shell. Use `console` for transcripts (prompt-prefixed commands, optionally with output). Use `text` for grammar/syntax notation, error output, or non-runnable illustrative content.
- **No prompts in `bash` fences.** If a fence is `bash`, every non-blank line should be a runnable command: no `$`/`❯` prefixes, no interleaved tool output.
- **`&&`-join multi-command sequences** when the intent is paste-and-run. Single-line `a && b && c` when the joined length stays under ~80 characters; multi-line trailing `&&` otherwise.
- **Do not `&&`-join across a non-terminal `flox activate`.** `flox activate` (without `-c` or `--`) launches an interactive sub-shell; a `&&` chain that crosses it stalls until the user manually exits, then runs the remainder outside the activated environment, often with expected variables unset. If downstream work needs to run inside the env, either split the fence (use `console` with `$` prompts for the interactive sequence) or use one of the inline-command forms: `flox activate -- CMD ARGS` (exec form, single program) or `flox activate -c 'CMD'` (shell-command form).
- **Borderline blocks stay `console`.** When a fence resists mechanical paste-and-run conversion (inline narrative comments, `<placeholder>` notation, mixed command + output), prefer leaving it as `console` over restructuring the surrounding prose. The right fix is upstream with the author.
- **Do not `&&`-chain cleanup or uninstall sequences.** Cleanup is typically a sequence of best-effort no-ops, not a dependency chain. `&&` short-circuits on the first idempotent failure (e.g., service already stopped, file already removed), leaving later steps such as `daemon-reload` unrun. Use newline-separated commands for teardown blocks; reserve `&&` for setup/install where each step genuinely depends on the previous one.

## Content boundaries

{/* Define what should and shouldn't be documented */}
{/* Example: Don't document internal admin features */}
