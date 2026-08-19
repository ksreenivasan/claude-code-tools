#!/usr/bin/env python3
"""Codex Stop hook that asks a separate Codex run whether work is complete."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any


IGNORED_USER_PREFIXES = ("# AGENTS.md instructions", "<environment_context>")


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, separators=(",", ":")))


def message_text(payload: dict[str, Any]) -> str:
    parts: list[str] = []
    for item in payload.get("content", []):
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if isinstance(text, str) and item.get("type") in {"input_text", "output_text"}:
            parts.append(text)
    return "\n".join(parts).strip()


def transcript_context(path: str | None) -> tuple[list[str], list[str]]:
    if not path:
        return [], []

    transcript = Path(path)
    if not transcript.is_file():
        return [], []

    user_messages: list[str] = []
    task_updates: list[str] = []
    try:
        with transcript.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("type") != "response_item":
                    continue
                payload = event.get("payload")
                if not isinstance(payload, dict):
                    continue

                if payload.get("type") == "message" and payload.get("role") == "user":
                    text = message_text(payload)
                    if text and not text.startswith(IGNORED_USER_PREFIXES):
                        user_messages.append(text)

                if payload.get("type") == "custom_tool_call":
                    name = str(payload.get("name", ""))
                    if name.rsplit("__", 1)[-1] in {"update_plan", "create_goal", "update_goal"}:
                        arguments = payload.get("arguments", "")
                        task_updates.append(f"{name}: {arguments}")
    except OSError:
        return [], []

    return user_messages[-5:], task_updates[-8:]


def git_context(cwd: str | None) -> str:
    if not cwd:
        return ""
    try:
        repository = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    root = repository.stdout.strip()
    if repository.returncode != 0 or not root:
        return ""
    commands = (["git", "status", "--short"], ["git", "diff", "--stat"])
    sections: list[str] = []
    for command in commands:
        try:
            result = subprocess.run(
                command,
                cwd=root,
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        output = result.stdout.strip()
        if output:
            sections.append(f"$ {' '.join(command)}\n{output[:2000]}")
    return "\n\n".join(sections)


def build_prompt(
    user_messages: list[str],
    task_updates: list[str],
    last_assistant_message: str,
    repo_state: str,
) -> str:
    recent = ("\n\n---\n\n".join(user_messages) or "(unavailable)")[-6000:]
    tasks = ("\n".join(task_updates) or "(no plan/goal updates found)")[-2500:]
    repo = (repo_state or "(not a Git repository or no visible changes)")[-2500:]
    assistant = (last_assistant_message or "(unavailable)")[-4000:]
    return f"""You are an independent completion reviewer for a coding agent.
Decide whether the agent is genuinely finished with the user's latest request.
Do not call tools. Judge only the evidence below.

Classify as:
- COMPLETE: all requested work is done and verified, or the agent is genuinely blocked on necessary user input.
- PREMATURE: safe in-scope work, verification, cleanup, or an explicitly requested next step remains.
- UNCERTAIN: the evidence does not establish either conclusion.

Rules:
- Weight the latest real user message most heavily.
- A progress update, partial result, design discussion, or promise to do more is not completion.
- An optional "let me know" question does not excuse unfinished work.
- A necessary clarifying question or a concrete blocker may be COMPLETE.
- Do not invent requirements beyond the user's request.

RECENT USER MESSAGES (latest last)
{recent}

PLAN OR GOAL UPDATES
{tasks}

REPOSITORY STATE
{repo}

LAST ASSISTANT MESSAGE
{assistant}
"""


def codex_binary() -> str | None:
    configured = os.environ.get("CODEX_STOP_NANNY_CODEX")
    if configured:
        return configured
    found = shutil.which("codex")
    if found:
        return found
    app_binary = Path("/Applications/ChatGPT.app/Contents/Resources/codex")
    return str(app_binary) if app_binary.is_file() else None


def evaluate(prompt: str) -> dict[str, str] | None:
    injected = os.environ.get("CODEX_STOP_NANNY_TEST_RESULT")
    if injected:
        try:
            result = json.loads(injected)
            return result if isinstance(result, dict) else None
        except json.JSONDecodeError:
            return None

    binary = codex_binary()
    if not binary:
        return None

    schema = {
        "type": "object",
        "properties": {
            "verdict": {"type": "string", "enum": ["COMPLETE", "PREMATURE", "UNCERTAIN"]},
            "reason": {"type": "string"},
        },
        "required": ["verdict", "reason"],
        "additionalProperties": False,
    }
    with tempfile.TemporaryDirectory(prefix="codex-stop-nanny-") as temporary:
        schema_path = Path(temporary) / "schema.json"
        output_path = Path(temporary) / "result.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")
        env = os.environ.copy()
        env["CODEX_STOP_NANNY_CHILD"] = "1"
        command = [
            binary,
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--model",
            os.environ.get("CODEX_STOP_NANNY_MODEL", "gpt-5.6-luna"),
            "-c",
            'model_reasoning_effort="low"',
            "--output-schema",
            str(schema_path),
            "--output-last-message",
            str(output_path),
            "-C",
            temporary,
            "-",
        ]
        try:
            subprocess.run(
                command,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
                env=env,
            )
            result = json.loads(output_path.read_text(encoding="utf-8"))
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            return None
    return result if isinstance(result, dict) else None


def log_result(session_id: str, verdict: str, reason: str) -> None:
    try:
        log_dir = Path.home() / ".codex" / "stop-nanny"
        log_dir.mkdir(parents=True, exist_ok=True)
        with (log_dir / f"{session_id or 'unknown'}.log").open("a", encoding="utf-8") as handle:
            handle.write(f"{verdict}: {reason[:1000]}\n")
    except OSError:
        pass


def main() -> int:
    if os.environ.get("CODEX_STOP_NANNY_CHILD") == "1":
        emit({})
        return 0

    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        emit({})
        return 0

    if hook_input.get("stop_hook_active") is True:
        emit({})
        return 0

    users, tasks = transcript_context(hook_input.get("transcript_path"))
    prompt = build_prompt(
        users,
        tasks,
        str(hook_input.get("last_assistant_message") or ""),
        git_context(hook_input.get("cwd")),
    )

    result = evaluate(prompt)
    if result is None:
        result = evaluate(prompt)

    session_id = str(hook_input.get("session_id") or "unknown")
    if result is None:
        verdict = "PREMATURE"
        reason = "Completion review failed twice; make one final completion and verification pass."
    else:
        verdict = str(result.get("verdict", "UNCERTAIN")).upper()
        reason = str(result.get("reason", "No reason supplied.")).strip()

    log_result(session_id, verdict, reason)
    if verdict == "COMPLETE":
        emit({})
        return 0

    if verdict == "PREMATURE":
        continuation = f"The independent stop reviewer found unfinished work: {reason} Continue the task and verify it before stopping."
    else:
        continuation = f"Completion is unclear: {reason} Re-check the latest request, continue any safe in-scope work, and ask the user only if genuinely blocked."
    emit({"decision": "block", "reason": continuation})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
