import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { parseJsonObject } from "./reviewer.ts";

export interface RiskMatch {
	risky: boolean;
	reason?: string;
}

export interface SafetyVerdict {
	outcome: "allow" | "ask" | "deny";
	reason: string;
}

const DISPOSABLE_DIRECTORY_NAMES = new Set([
	".cache",
	".mypy_cache",
	".pytest_cache",
	".ruff_cache",
	".tmp",
	".tox",
	"__pycache__",
	"build",
	"cache",
	"coverage",
	"dist",
	"temp",
	"test-output",
	"test-results",
	"tmp",
]);

const COMMAND_RISKS: Array<[RegExp, string]> = [
	[/\brm\s+(?:[^\n;&|]*\s)?(?:-[^\s]*[rR][^\s]*|--recursive)\b/, "recursive deletion"],
	[/\bgit\s+reset\s+--hard\b/, "destructive Git reset"],
	[/\bgit\s+clean\b[^\n;&|]*(?:--force\b|(?:^|\s)-[^\s]*f)/, "permanent removal of untracked files"],
	[/\bgit\s+(?:restore\b|checkout\s+--(?:\s|$))/, "discarding uncommitted Git changes"],
	[/\bgit\s+stash\s+(?:drop|clear)\b/, "permanent removal of Git stash entries"],
	[/\bgit\s+branch\s+-[^\s]*D\b/, "forced deletion of a local Git branch"],
	[/\bgit\s+push\b[^\n;&|]*(?:--force(?:-with-lease)?|-f\b|--delete\b)/, "destructive remote Git operation"],
	[/\bgit\s+push\b/, "externally visible Git push"],
	[/\bgh\s+(?:repo\s+delete|pr\s+(?:create|merge|close)|issue\s+(?:create|close|delete))\b/, "externally visible GitHub mutation"],
	[/\bterraform\s+(?:destroy|apply)\b/, "infrastructure mutation"],
	[/\bkubectl\s+(?:delete|apply|replace|patch)\b/, "cluster mutation"],
	[/\b(?:sudo|launchctl\s+(?:bootout|bootstrap|kickstart)|systemctl\s+(?:stop|disable|restart))\b/, "privileged or host service mutation"],
	[
		/\bcurl\b[^\n;&|]*(?:(?:-X|--request)\s*(?:POST|PUT|PATCH|DELETE)\b|(?:--data(?:-[a-z]+)?|-d|--form|-F|--upload-file|-T)\b)/i,
		"external HTTP mutation",
	],
	[/\bhttps?\b\s+(?:POST|PUT|PATCH|DELETE)\b/i, "external HTTP mutation"],
];

function isExactDisposableRecursiveDelete(command: string, cwd: string): boolean {
	if (/[;&|<>\n`$*?\[\]{}]/.test(command)) return false;
	const parts = command.trim().split(/\s+/);
	if (parts[0] !== "rm") return false;

	let recursive = false;
	let optionsDone = false;
	const targets: string[] = [];
	for (const part of parts.slice(1)) {
		if (!optionsDone && part === "--") {
			optionsDone = true;
			continue;
		}
		if (!optionsDone && part.startsWith("-")) {
			if (part === "--recursive") {
				recursive = true;
				continue;
			}
			if (part === "--force") continue;
			if (!/^-+[rRfF]+$/.test(part)) return false;
			if (/[rR]/.test(part)) recursive = true;
			continue;
		}
		optionsDone = true;
		targets.push(part);
	}
	if (!recursive || targets.length !== 1) return false;

	const target = path.resolve(cwd, targets[0]);
	const resolvedCwd = path.resolve(cwd);
	try {
		const metadata = fs.lstatSync(target);
		if (!metadata.isDirectory() || metadata.isSymbolicLink()) return false;

		const canonicalTarget = fs.realpathSync(target);
		const canonicalCwd = fs.realpathSync(resolvedCwd);
		const canonicalHome = fs.realpathSync(os.homedir());
		if (canonicalTarget === canonicalCwd || canonicalTarget === canonicalHome || canonicalTarget === path.parse(canonicalTarget).root) {
			return false;
		}

		const protectedRoots = [
			path.join(os.homedir(), ".pi", "agent"),
			path.join(os.homedir(), ".codex"),
			path.join(os.homedir(), ".claude"),
			path.join(os.homedir(), ".ssh"),
			path.join(os.homedir(), ".aws"),
			path.join(os.homedir(), ".config", "gh"),
		]
			.filter((root) => fs.existsSync(root))
			.map((root) => fs.realpathSync(root));
		if (protectedRoots.some((root) => canonicalTarget === root || canonicalTarget.startsWith(`${root}${path.sep}`))) {
			return false;
		}

		const inWorkingDirectory = canonicalTarget.startsWith(`${canonicalCwd}${path.sep}`);
		const temporaryRoots = [os.tmpdir(), "/tmp", "/private/tmp", "/var/tmp"]
			.filter((root) => fs.existsSync(root))
			.map((root) => fs.realpathSync(root));
		const inTemporaryRoot = temporaryRoots.some((root) => canonicalTarget.startsWith(`${root}${path.sep}`));
		return (inWorkingDirectory && DISPOSABLE_DIRECTORY_NAMES.has(path.basename(canonicalTarget))) || inTemporaryRoot;
	} catch {
		return false;
	}
}

function protectedPathReason(rawPath: string, cwd: string): string | undefined {
	const resolved = path.resolve(cwd, rawPath.replace(/^~(?=$|\/)/, os.homedir()));
	const home = os.homedir();
	const protectedRoots = [
		path.join(home, ".pi", "agent"),
		path.join(home, ".codex"),
		path.join(home, ".claude"),
		path.join(home, ".ssh"),
		path.join(home, ".aws"),
		path.join(home, ".config", "gh"),
	];
	if (protectedRoots.some((root) => resolved === root || resolved.startsWith(`${root}${path.sep}`))) {
		return "agent configuration, hooks, skills, extensions, sessions, or credentials";
	}
	const base = path.basename(resolved).toLowerCase();
	if (base === ".env" || base.startsWith(".env.") || /(?:auth|credential|secret|token).*(?:json|ya?ml|toml)$/i.test(base)) {
		return "credential or secret-bearing file";
	}
	return undefined;
}

function normalizeGitDirectoryOption(command: string): string {
	return command.replace(
		/\bgit\s+-C\s+(?:"[^"\n]*"|'[^'\n]*'|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|[^\s;&|]+)\s+/g,
		"git ",
	);
}

function withoutCachedPatchHeredoc(command: string): string {
	const lines = command.split("\n");
	const start = lines.findIndex((line) => /\bgit\s+apply\s+--cached\b/.test(line) && /<<-?\s*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?\s*$/.test(line));
	if (start < 0) return command;
	const marker = lines[start].match(/<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\s*$/)?.[1];
	if (!marker) return command;
	const end = lines.findIndex((line, index) => index > start && line.trim() === marker);
	if (end < 0) return command;
	return [...lines.slice(0, start + 1), ...lines.slice(end + 1)].join("\n");
}

function shellProtectedPathRisk(command: string): string | undefined {
	const home = os.homedir();
	const normalized = command
		.replaceAll("${HOME}", home)
		.replaceAll("$HOME", home)
		.replace(/~(?=\/)/g, home);
	const mentionsProtectedPath = [
		`${home}/.pi/agent`,
		`${home}/.codex`,
		`${home}/.claude`,
		`${home}/.ssh`,
		`${home}/.aws`,
		`${home}/.config/gh`,
		".pi/agent",
		".codex/",
		".claude/",
		".ssh/",
		".aws/",
		".config/gh/",
	].some((value) => normalized.includes(value));
	if (!mentionsProtectedPath) return undefined;

	const mutation = /(?:^|[;&|]\s*|\s)(?:rm|mv|cp|install|truncate|chmod|chown|mkdir|tee|sed\s+-i|perl\s+-i|python(?:3)?|node|ruby)\b|(?:^|[^<])>{1,2}(?!>)/;
	return mutation.test(normalized) ? "shell mutation of agent configuration, hooks, skills, extensions, or credentials" : undefined;
}

export function classifyToolCall(toolName: string, input: Record<string, unknown>, cwd: string): RiskMatch {
	if (toolName === "bash") {
		const command = typeof input.command === "string" ? input.command : "";
		if (isExactDisposableRecursiveDelete(command, cwd)) return { risky: false };
		const protectedRisk = shellProtectedPathRisk(withoutCachedPatchHeredoc(command));
		if (protectedRisk) return { risky: true, reason: protectedRisk };
		const riskCommand = normalizeGitDirectoryOption(command);
		for (const [pattern, reason] of COMMAND_RISKS) {
			if (pattern.test(riskCommand)) return { risky: true, reason };
		}
		return { risky: false };
	}

	if (toolName === "write" || toolName === "edit") {
		if (typeof input.path !== "string") return { risky: false };
		const reason = protectedPathReason(input.path, cwd);
		return reason ? { risky: true, reason } : { risky: false };
	}

	return { risky: false };
}

export function parseSafetyVerdict(text: string): SafetyVerdict | undefined {
	const value = parseJsonObject(text);
	const outcome = value?.outcome;
	const reason = value?.reason;
	if (outcome !== "allow" && outcome !== "ask" && outcome !== "deny") return undefined;
	if (typeof reason !== "string" || !reason.trim()) return undefined;
	return { outcome, reason: reason.trim() };
}
