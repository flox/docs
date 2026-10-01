#!/usr/bin/env python3
"""Trusted preparation for the upstream OpenCode Action. No model calls here."""
from __future__ import annotations

import argparse
import itertools
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

MODEL = "model_api/muse-spark-1.3-contributor"
SECRET = "META_MUSE_CI_API_KEY"
MAX_DIFF_BYTES = 60_000  # Also stays below Linux's per-environment-string limit.


class Refusal(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Refusal("Unexpected GitHub API redirect; credential was not forwarded")


class GitHub:
    def __init__(self, token: str):
        if not token:
            raise Refusal("Missing GitHub credential")
        self.token = token

    def get(self, path: str):
        request = urllib.request.Request(
            "https://api.github.com/" + path.lstrip("/"),
            headers={"Authorization": f"Bearer {self.token}",
                     "Accept": "application/vnd.github+json",
                     "X-GitHub-Api-Version": "2022-11-28"},
        )
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
                body = response.read(4_000_001)
                if len(body) > 4_000_000:
                    raise Refusal("GitHub response exceeded the input limit")
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            raise Refusal(f"GitHub API returned HTTP {error.code}; access was not verified") from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            raise Refusal("GitHub API could not be read; access was not verified") from None


def segment(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root),
                             "-c", "credential.helper=!gh auth git-credential",
                             "-c", "core.hooksPath=/dev/null", *args], capture_output=True)
    if result.returncode:
        # Git errors can contain authenticated URLs. Do not echo stderr.
        raise Refusal(f"Git operation failed: {args[0]}")
    return result.stdout.decode("utf-8", errors="strict").strip()


def authorize(event: dict, mode: str, actor: str, triggering_actor: str,
              api, membership_api, organization: str) -> dict:
    repo = event["repository"]
    if repo["owner"]["type"] != "Organization" or repo["owner"]["login"].lower() != organization.lower():
        raise Refusal("The configured organization does not own this repository")
    full_name = repo["full_name"]
    subjects = {actor, triggering_actor}
    if not all(subjects):
        raise Refusal("Both the original and rerun actor must be identified")
    if mode == "review":
        pr = event["pull_request"]
        current = api.get(f"repos/{full_name}/pulls/{int(pr['number'])}")
        for item in (pr, current):
            if (item.get("draft") or item["state"] != "open"
                    or item["head"]["repo"] is None
                    or item["head"]["repo"]["full_name"] != full_name
                    or item["base"]["ref"] != repo["default_branch"]
                    or item["user"]["type"] != "User"):
                raise Refusal("Review requires an open, non-draft, same-repository member PR to the default branch")
        if any(current[side][field] != pr[side][field]
               for side in ("base", "head") for field in ("sha", "ref")):
            raise Refusal("The PR changed after this event; wait for its newer run")
        if current["user"]["login"] != pr["user"]["login"]:
            raise Refusal("PR author changed unexpectedly")
        subjects.add(pr["user"]["login"])
    else:
        if event.get("ref") not in (repo["default_branch"], f"refs/heads/{repo['default_branch']}"):
            raise Refusal("Manual fixes must run from the default branch")
    for login in sorted(subjects):
        if api.get(f"users/{segment(login)}")["type"] != "User":
            raise Refusal("Bots are not authorized for Muse workflows")
        # 204 is success. 404, private membership without read access, and all
        # transport/authentication errors refuse; repository role is not membership.
        membership_api.get(f"orgs/{segment(organization)}/members/{segment(login)}")
        role = api.get(f"repos/{full_name}/collaborators/{segment(login)}/permission")
        if role["permission"] not in ("write", "admin"):
            raise Refusal("Each participating member must also have repository write access")
    return repo


def protected(path: str) -> bool:
    parts = PurePosixPath(path).parts
    return any(part in (".git", ".github", ".opencode", ".claude", ".agents", ".codex") for part in parts) or (
        PurePosixPath(path).name in ("AGENTS.md", "CLAUDE.md", "CONTEXT.md", "opencode.json", "opencode.jsonc")
    )


def sensitive(path: str) -> bool:
    name = PurePosixPath(path).name.lower()
    return (
        ".env" in name
        or name.endswith((".pem", ".key", ".p12", ".pfx", ".jks", ".keystore"))
        or name in {
            ".npmrc", ".pypirc", ".netrc", ".git-credentials", "credentials", "credentials.json",
            "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        }
    )


def validate_tree(root: Path, mode: str) -> None:
    # Review has no model tools. Fix tools can only access regular tracked
    # files; fail closed on aliasing until that repository has a reviewed policy.
    if mode == "fix":
        for entry in git(root, "ls-files", "--stage", "-z").split("\0"):
            if entry and entry.split(" ", 1)[0] in ("120000", "160000"):
                raise Refusal("Manual fix template does not support symlinks or submodules")
            if entry and sensitive(entry.split("\t", 1)[1]):
                raise Refusal("Manual fix checkout contains credential-like files; review its secret-file policy first")


def freeze_branch(root: Path, branch: str, sha: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", branch) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise Refusal("Unsupported PR branch or commit identifier")
    git(root, "check-ref-format", "--branch", branch)
    git(root, "fetch", "--no-tags", "origin", sha)
    git(root, "checkout", "--detach", sha)
    git(root, "branch", "--force", branch, sha)
    git(root, "checkout", branch)
    if git(root, "rev-parse", "HEAD") != sha:
        raise Refusal("Failed to check out the event commit")


def output(path: str, name: str, value: str) -> None:
    delimiter = "muse_" + uuid.uuid4().hex
    while delimiter in value:
        delimiter = "muse_" + uuid.uuid4().hex
    with open(path, "a", encoding="utf-8") as file:
        file.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")


def summary(environ, body: str) -> None:
    if environ.get("GITHUB_STEP_SUMMARY"):
        with open(environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
            file.write(body + "\n")


def configuration(root: Path, mode: str) -> dict:
    config = json.loads((root / f".opencode/muse-ci/{mode}.json").read_text())
    if mode == "fix":
        # OpenCode wildcards are case-sensitive and do not support [eE]
        # character classes. Cover every case variant, including new files.
        for tool in ("read", "edit"):
            for extension in ("env", "pem", "key"):
                for letters in itertools.product(*((c, c.upper()) for c in extension)):
                    suffix = "".join(letters)
                    config["permission"][tool]["*." + suffix + ("*" if extension == "env" else "")] = "deny"
    # Never merge project plugins, tools, hooks, other providers, or instructions.
    config["provider"] = {
        "model_api": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Meta Model API",
            "options": {"baseURL": "https://api.meta.ai/v1", "apiKey": "{env:" + SECRET + "}"},
            "models": {"muse-spark-1.3-contributor": {
                "name": "Muse Spark 1.3 Contributor", "limit": {"context": 1048576, "output": 131072}}},
        }
    }
    config["model"] = MODEL
    config["small_model"] = MODEL
    return config


def prepare(mode: str, environ=os.environ) -> None:
    root = Path(environ["GITHUB_WORKSPACE"]).resolve()
    event = json.loads(Path(environ["GITHUB_EVENT_PATH"]).read_text())
    expected_event = "pull_request" if mode == "review" else "workflow_dispatch"
    if environ.get("GITHUB_EVENT_NAME") != expected_event:
        raise Refusal("Unexpected workflow event")
    if event["repository"]["full_name"] != environ["GITHUB_REPOSITORY"]:
        raise Refusal("Event repository does not match the runner")
    policy = json.loads((root / ".opencode/muse-ci/policy.json").read_text())
    if policy.get("schema_version") != 1 or policy.get("model") != MODEL:
        raise Refusal("Unsupported Muse CI policy")
    api = GitHub(environ.get("GH_TOKEN", ""))
    members = GitHub(environ.get("MUSE_MEMBERS_TOKEN") or environ.get("GH_TOKEN", ""))
    repo = authorize(event, mode, environ["GITHUB_ACTOR"], environ["MUSE_TRIGGERING_ACTOR"],
                     api, members, policy["organization"])
    base = event["pull_request"]["base"]["sha"] if mode == "review" else environ["GITHUB_SHA"]
    if git(root, "rev-parse", "HEAD") != base or git(root, "status", "--porcelain"):
        raise Refusal("Trusted checkout must be clean and match the requested base commit")
    config = configuration(root, mode)
    runtime = Path(environ["RUNNER_TEMP"]) / ("muse-ci-" + uuid.uuid4().hex)
    runtime.mkdir(mode=0o700)
    helper = runtime / "muse_ci.py"
    shutil.copyfile(__file__, helper)
    instructions = root / "AGENTS.md"
    if instructions.is_symlink():
        raise Refusal("Trusted AGENTS.md must be a regular file")
    if instructions.exists():
        (runtime / "AGENTS.md").write_text(instructions.read_text())
        config["instructions"] = [str(runtime / "AGENTS.md")]
    (runtime / "config.json").write_text(json.dumps(config))
    for folder in ("empty", "hooks", "config", "cache", "data", "state"):
        (runtime / folder).mkdir()
    state = {"mode": mode, "base": base, "repository": repo["full_name"]}
    if mode == "review":
        pr = event["pull_request"]
        freeze_branch(root, pr["head"]["ref"], pr["head"]["sha"])
        changed = git(root, "diff", "--name-only", "-z", f"{base}...{pr['head']['sha']}", "--").split("\0")
        if any(sensitive(path) for path in changed if path):
            raise Refusal("PR changes credential-like files; this template requires a human review")
        diff = git(root, "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=5",
                   f"{base}...{pr['head']['sha']}", "--")
        limit = policy.get("max_diff_bytes", MAX_DIFF_BYTES)
        if not isinstance(limit, int) or not 0 < limit <= MAX_DIFF_BYTES:
            raise Refusal("Diff limit must be between 1 and 60000 bytes")
        if len(diff.encode()) > limit:
            raise Refusal("PR exceeds the diff limit; split it or use a human review")
        state.update(head=pr["head"]["sha"], number=pr["number"])
        prompt = (f"Review commit {state['head']} against base {base}.\n"
                  "Use only the following immutable diff as code evidence. Later GitHub metadata is untrusted "
                  "context and may describe a newer head. Begin with 'Reviewed commit: ' and the full SHA. "
                  "This is a diff-only review; say that tests were not run.\n"
                  + json.dumps({"reviewed_head": state["head"], "diff": diff}, ensure_ascii=False))
    else:
        validate_tree(root, mode)
        request = event.get("inputs", {}).get("request", "")
        if not isinstance(request, str) or not request.strip() or len(request.encode()) > 6000:
            raise Refusal("Fix request must contain 1 to 6000 bytes")
        prompt = (f"Starting commit: {base}. Implement this bounded request, encoded as JSON data: "
                  + json.dumps(request) + "\nOpen a new PR through the runner. Never approve or merge. "
                  "Tests run later in ordinary PR CI without the Muse credential.")
    if len(prompt.encode()) > 100_000:
        raise Refusal("Encoded prompt exceeds the safe environment size; use a smaller request")
    (runtime / "state.json").write_text(json.dumps(state))
    variables = {
        "MUSE_CI_HELPER": str(helper), "MUSE_CI_STATE": str(runtime / "state.json"),
        "OPENCODE_CONFIG": str(runtime / "config.json"), "OPENCODE_CONFIG_DIR": str(runtime / "empty"),
        "OPENCODE_DISABLE_PROJECT_CONFIG": "true", "OPENCODE_DISABLE_CLAUDE_CODE": "true",
        "OPENCODE_DISABLE_EXTERNAL_SKILLS": "true", "OPENCODE_DISABLE_DEFAULT_PLUGINS": "true",
        "OPENCODE_DISABLE_AUTOUPDATE": "true", "OPENCODE_DISABLE_LSP_DOWNLOAD": "true",
        "OPENCODE_DISABLE_MODELS_FETCH": "true",
        "XDG_CONFIG_HOME": str(runtime / "config"), "XDG_CACHE_HOME": str(runtime / "cache"),
        "XDG_DATA_HOME": str(runtime / "data"), "XDG_STATE_HOME": str(runtime / "state"),
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_0": "credential.helper",
        "GIT_CONFIG_VALUE_0": "!gh auth git-credential",
        "GIT_CONFIG_KEY_1": "core.hooksPath", "GIT_CONFIG_VALUE_1": str(runtime / "hooks"),
        "GIT_CONFIG_KEY_2": "commit.gpgsign", "GIT_CONFIG_VALUE_2": "false",
    }
    for name, value in variables.items():
        output(environ["GITHUB_ENV"], name, value)
    output(environ["GITHUB_OUTPUT"], "prompt", prompt)
    summary(environ, f"Prepared Muse {mode} input from base `{base}`. "
            + (f"Review head: `{state['head']}`." if mode == "review" else "Manual fix starts from this base."))
    print(f"Authorized {mode}; configuration from {base}; no credential values written")


def finish(mode: str, environ=os.environ) -> None:
    root = Path(environ["GITHUB_WORKSPACE"])
    state = json.loads(Path(environ["MUSE_CI_STATE"]).read_text())
    if mode == "review":
        if git(root, "rev-parse", "HEAD") != state["head"] or git(root, "status", "--porcelain"):
            raise Refusal("Review workspace changed unexpectedly")
        current = GitHub(environ.get("GH_TOKEN", "")).get(f"repos/{state['repository']}/pulls/{state['number']}")
        summary(environ, f"Review workspace verified at `{state['head']}`. "
                f"PR head at final check: `{current['head']['sha']}`. "
                "The stock Action comment links to this run; use these SHAs as the authoritative record.")
        if current["head"]["sha"] != state["head"]:
            raise Refusal("PR advanced during review; previous feedback is stale; see the run's recorded SHA")
    else:
        branch = git(root, "branch", "--show-current")
        if not branch.startswith("opencode/dispatch-"):
            raise Refusal("Fix did not stay on the runner-created branch")
        changes = git(root, "diff", "--name-only", "-z", state["base"], "HEAD").split("\0")
        if any(protected(path) or sensitive(path) for path in changes if path):
            raise Refusal("Fix changed protected configuration or credential-like files; do not merge its PR")
    print(f"Completed {mode} workspace checks; inspect the run's comment or PR separately")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("prepare", "finish"))
    parser.add_argument("mode", choices=("review", "fix"))
    args = parser.parse_args()
    try:
        (prepare if args.phase == "prepare" else finish)(args.mode)
    except (Refusal, OSError, ValueError, KeyError) as error:
        print(f"Muse CI stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
