import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { runChildReview } from "./lib/reviewer.ts";
import { conversationMessages, latestAssistantMessage, latestUserMessage } from "./lib/session-context.ts";
import { parseCompletionVerdict, type CompletionVerdict } from "./lib/stop-core.ts";

function completionPrompt(userMessages: string[], lastAssistant: string, repositoryState: string): string {
	return `You are an independent completion reviewer for a coding agent.
Do not call tools. Return exactly one JSON object:
{"verdict":"COMPLETE|PREMATURE|UNCERTAIN","reason":"short explanation"}

COMPLETE means all work requested by the latest real user message is done and verified, or progress is genuinely blocked on necessary user input.
PREMATURE means safe in-scope implementation, verification, cleanup, or an explicitly requested next step remains.
UNCERTAIN means the available evidence does not establish either conclusion.
A progress update or promise to do more is not completion. Do not invent requirements beyond the request. Weight the latest user message most heavily.

RECENT USER MESSAGES (latest last)
${userMessages.length > 0 ? userMessages.join("\n\n---\n\n") : "(unavailable)"}

REPOSITORY STATE
${repositoryState || "(not a Git repository or no visible changes)"}

LAST ASSISTANT MESSAGE
${lastAssistant.slice(-6_000)}
`;
}

async function gitState(pi: ExtensionAPI, cwd: string): Promise<string> {
	const root = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 3_000 });
	if (root.code !== 0 || !root.stdout.trim()) return "";
	const repository = root.stdout.trim();
	const [status, diff] = await Promise.all([
		pi.exec("git", ["status", "--short"], { cwd: repository, timeout: 3_000 }),
		pi.exec("git", ["diff", "--stat"], { cwd: repository, timeout: 3_000 }),
	]);
	return [status.stdout.trim() && `$ git status --short\n${status.stdout.trim()}`, diff.stdout.trim() && `$ git diff --stat\n${diff.stdout.trim()}`]
		.filter(Boolean)
		.join("\n\n")
		.slice(-5_000);
}

async function evaluate(prompt: string): Promise<CompletionVerdict> {
	const injected = process.env.PI_EXTENSION_TEST_MODE === "1" ? process.env.PI_STOP_NANNY_TEST_RESULT : undefined;
	if (injected) return parseCompletionVerdict(injected) ?? { verdict: "UNCERTAIN", reason: "Invalid injected verdict." };

	let lastError = "Completion reviewer returned no valid verdict.";
	for (let attempt = 0; attempt < 2; attempt++) {
		try {
			const result = parseCompletionVerdict(await runChildReview(prompt));
			if (result) return result;
		} catch (error) {
			lastError = error instanceof Error ? error.message : String(error);
		}
	}
	return { verdict: "UNCERTAIN", reason: `${lastError} Make one final completion and verification pass.` };
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_REVIEW_CHILD === "1" || process.env.PI_STOP_NANNY_DISABLED === "1") return;

	const reviewedAssistantIds = new Set<string>();
	const nudgedUserCycles = new Set<string>();

	pi.on("agent_settled", async (_event, ctx) => {
		const branch = ctx.sessionManager.getBranch();
		const user = latestUserMessage(branch);
		const assistant = latestAssistantMessage(branch);
		if (!user || !assistant || reviewedAssistantIds.has(assistant.entryId)) return;
		reviewedAssistantIds.add(assistant.entryId);

		// A bad review can request at most one continuation for a real user prompt.
		if (nudgedUserCycles.has(user.entryId)) return;

		const users = conversationMessages(branch)
			.filter((message) => message.role === "user")
			.slice(-5)
			.map((message) => message.text);
		ctx.ui.setStatus("stop-nanny", "checking completion…");
		let verdict: CompletionVerdict;
		try {
			verdict = await evaluate(completionPrompt(users, assistant.text, await gitState(pi, ctx.cwd)));
		} finally {
			ctx.ui.setStatus("stop-nanny", undefined);
		}
		if (verdict.verdict === "COMPLETE") return;

		nudgedUserCycles.add(user.entryId);
		const continuation =
			verdict.verdict === "PREMATURE"
				? `The independent completion reviewer found unfinished work: ${verdict.reason} Continue the task and verify it before stopping.`
				: `Completion is unclear: ${verdict.reason} Re-check the latest request, continue any safe in-scope work, and ask the user only if genuinely blocked.`;
		pi.sendMessage(
			{
				customType: "stop-nanny",
				content: continuation,
				display: true,
			},
			{ deliverAs: "followUp", triggerTurn: true },
		);
	});
}
