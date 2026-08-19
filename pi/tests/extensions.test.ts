import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { classifyToolCall, parseSafetyVerdict } from "../extensions/lib/safety-core.ts";
import { conversationMessages, latestAssistantMessage, latestUserMessage } from "../extensions/lib/session-context.ts";
import { parseCompletionVerdict } from "../extensions/lib/stop-core.ts";
import safetyReviewExtension from "../extensions/safety-review.ts";
import stopNannyExtension from "../extensions/stop-nanny.ts";

const disposableRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pi-safety-core-"));
const outsideRoot = fs.mkdtempSync(path.join(os.homedir(), ".pi-safety-outside-"));
fs.mkdirSync(path.join(disposableRoot, "build"));
fs.mkdirSync(path.join(disposableRoot, "cache"));
fs.symlinkSync(path.join(disposableRoot, "cache"), path.join(disposableRoot, "cache-link"));
fs.mkdirSync(path.join(outsideRoot, "cache"));
fs.symlinkSync(outsideRoot, path.join(disposableRoot, "outside-link"));
process.once("exit", () => {
	fs.rmSync(disposableRoot, { recursive: true, force: true });
	fs.rmSync(outsideRoot, { recursive: true, force: true });
});

assert.equal(classifyToolCall("bash", { command: "npm test" }, disposableRoot).risky, false);
assert.equal(classifyToolCall("bash", { command: "rm -rf build" }, disposableRoot).risky, false);
assert.equal(classifyToolCall("bash", { command: `rm -rf ${path.join(disposableRoot, "cache")}` }, process.cwd()).risky, false);
assert.equal(classifyToolCall("bash", { command: "rm -rf cache-link" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "rm -rf outside-link/cache" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "rm -rf build/*" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "rm -rf $TARGET" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: `rm -rf ${disposableRoot}` }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "rm -rf /" }, disposableRoot).risky, true);

const inheritedHome = process.env.HOME;
const isolatedHome = path.join(disposableRoot, "isolated-home");
for (const directory of [".ssh/cache", ".codex/tmp", ".pi/agent/build"]) {
	fs.mkdirSync(path.join(isolatedHome, directory), { recursive: true });
}
try {
	process.env.HOME = isolatedHome;
	assert.equal(os.homedir(), isolatedHome);
	for (const target of [".ssh/cache", ".codex/tmp", ".pi/agent/build"]) {
		assert.equal(classifyToolCall("bash", { command: `rm -rf ${target}` }, isolatedHome).risky, true);
	}
} finally {
	if (inheritedHome === undefined) delete process.env.HOME;
	else process.env.HOME = inheritedHome;
}

assert.equal(classifyToolCall("bash", { command: "git push origin main" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "git push --force origin main" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "git reset --hard HEAD~1" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "terraform destroy -auto-approve" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "launchctl bootout gui/501/dev.example" }, disposableRoot).risky, true);
assert.equal(classifyToolCall("bash", { command: "git clean --force -d" }, process.cwd()).risky, true);
assert.equal(classifyToolCall("bash", { command: "git restore src/index.ts" }, process.cwd()).risky, true);
assert.equal(classifyToolCall("bash", { command: "git checkout -- ." }, process.cwd()).risky, true);
assert.equal(classifyToolCall("bash", { command: "curl -d '{\"ok\":true}' https://example.com" }, process.cwd()).risky, true);
assert.equal(classifyToolCall("bash", { command: "git status" }, process.cwd()).risky, false);
assert.equal(
	classifyToolCall(
		"bash",
		{ command: "git apply --cached - <<'PATCH'\nDocumentation mentions ~/.codex/AGENTS.md and ~/.claude/settings.json.\nPATCH" },
		process.cwd(),
	).risky,
	false,
);
assert.equal(
	classifyToolCall("bash", { command: "sed -i '' 's/x/y/' ~/.pi/agent/settings.json" }, process.cwd()).risky,
	true,
);
assert.equal(
	classifyToolCall("bash", { command: "python3 -c 'write config' $HOME/.claude/settings.json" }, process.cwd()).risky,
	true,
);
assert.equal(classifyToolCall("edit", { path: "src/index.ts" }, process.cwd()).risky, false);
assert.equal(
	classifyToolCall("write", { path: path.join(os.homedir(), ".pi/agent/settings.json") }, process.cwd()).risky,
	true,
);
assert.equal(classifyToolCall("write", { path: ".env" }, process.cwd()).risky, true);

assert.deepEqual(parseSafetyVerdict('{"outcome":"allow","reason":"requested and scoped"}'), {
	outcome: "allow",
	reason: "requested and scoped",
});
assert.deepEqual(parseSafetyVerdict('```json\n{"outcome":"ask","reason":"target unclear"}\n```'), {
	outcome: "ask",
	reason: "target unclear",
});
assert.equal(parseSafetyVerdict("not json"), undefined);

assert.deepEqual(parseCompletionVerdict('{"verdict":"premature","reason":"tests remain"}'), {
	verdict: "PREMATURE",
	reason: "tests remain",
});
assert.equal(parseCompletionVerdict('{"verdict":"DONE","reason":"no"}'), undefined);

const entries = [
	{ id: "u1", type: "message", message: { role: "user", content: [{ type: "text", text: "Do the work" }] } },
	{ id: "a1", type: "message", message: { role: "assistant", content: [{ type: "text", text: "Done" }] } },
];
assert.equal(conversationMessages(entries).length, 2);
assert.equal(latestUserMessage(entries)?.entryId, "u1");
assert.equal(latestAssistantMessage(entries)?.text, "Done");

const ui = {
	setStatus() {},
	notify() {},
	async confirm() {
		return false;
	},
};

let safetyHandler: ((event: any, ctx: any) => Promise<any>) | undefined;
safetyReviewExtension({
	on(name: string, handler: typeof safetyHandler) {
		if (name === "tool_call") safetyHandler = handler;
	},
} as any);
assert.ok(safetyHandler);
process.env.PI_EXTENSION_TEST_MODE = "1";
process.env.PI_SAFETY_REVIEW_TEST_RESULT = '{"outcome":"deny","reason":"must not run for routine work"}';
for (const command of ["npm test", "rm -rf build"]) {
	assert.equal(
		await safetyHandler(
			{ toolName: "bash", input: { command } },
			{
				cwd: disposableRoot,
				hasUI: false,
				signal: undefined,
				ui,
				sessionManager: { getBranch: () => entries },
			},
		),
		undefined,
	);
}
assert.deepEqual(
	await safetyHandler(
		{ toolName: "bash", input: { command: "rm -rf /" } },
		{
			cwd: disposableRoot,
			hasUI: false,
			signal: undefined,
			ui,
			sessionManager: { getBranch: () => entries },
		},
	),
	{ block: true, reason: "must not run for routine work" },
);
process.env.PI_SAFETY_REVIEW_TEST_RESULT = '{"outcome":"ask","reason":"target unclear"}';
assert.deepEqual(
	await safetyHandler(
		{ toolName: "bash", input: { command: "git push origin main" } },
		{
			cwd: process.cwd(),
			hasUI: false,
			signal: undefined,
			ui,
			sessionManager: { getBranch: () => entries },
		},
	),
	{ block: true, reason: "target unclear" },
);
delete process.env.PI_SAFETY_REVIEW_TEST_RESULT;

const inheritedStopNannyDisabled = process.env.PI_STOP_NANNY_DISABLED;
delete process.env.PI_STOP_NANNY_DISABLED;
let settledHandler: ((event: any, ctx: any) => Promise<void>) | undefined;
const continuations: unknown[] = [];
stopNannyExtension({
	on(name: string, handler: typeof settledHandler) {
		if (name === "agent_settled") settledHandler = handler;
	},
	async exec() {
		return { code: 1, stdout: "", stderr: "" };
	},
	sendMessage(message: unknown) {
		continuations.push(message);
	},
} as any);
assert.ok(settledHandler);
process.env.PI_STOP_NANNY_TEST_RESULT = '{"verdict":"PREMATURE","reason":"tests remain"}';
const stopContext = {
	cwd: process.cwd(),
	ui,
	sessionManager: { getBranch: () => entries },
};
await settledHandler({}, stopContext);
assert.equal(continuations.length, 1);
const secondEntries = [
	...entries,
	{ id: "a2", type: "message", message: { role: "assistant", content: [{ type: "text", text: "Tests now pass" }] } },
];
await settledHandler({}, { ...stopContext, sessionManager: { getBranch: () => secondEntries } });
assert.equal(continuations.length, 1, "Stop nanny must nudge at most once per real user prompt");
delete process.env.PI_STOP_NANNY_TEST_RESULT;
delete process.env.PI_EXTENSION_TEST_MODE;
if (inheritedStopNannyDisabled === undefined) {
	delete process.env.PI_STOP_NANNY_DISABLED;
} else {
	process.env.PI_STOP_NANNY_DISABLED = inheritedStopNannyDisabled;
}

console.log("Pi port unit tests passed.");
