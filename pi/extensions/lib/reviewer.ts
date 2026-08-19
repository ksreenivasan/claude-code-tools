import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

export interface ChildReviewOptions {
	model?: string;
	thinking?: string;
	timeoutMs?: number;
	signal?: AbortSignal;
}

function piInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}

	const executable = path.basename(process.execPath).toLowerCase();
	if (!/^(node|bun)(\.exe)?$/.test(executable)) {
		return { command: process.execPath, args };
	}
	return { command: "pi", args };
}

export async function runChildReview(prompt: string, options: ChildReviewOptions = {}): Promise<string> {
	const args = [
		"--no-session",
		"--no-extensions",
		"--no-skills",
		"--no-context-files",
		"--no-builtin-tools",
		"--model",
		options.model ?? process.env.PI_REVIEW_MODEL ?? "openai-codex/gpt-5.6-luna",
		"--thinking",
		options.thinking ?? "low",
		"--print",
		prompt,
	];
	const invocation = piInvocation(args);
	const timeoutMs = options.timeoutMs ?? 120_000;

	return await new Promise<string>((resolve, reject) => {
		const child = spawn(invocation.command, invocation.args, {
			stdio: ["ignore", "pipe", "pipe"],
			env: { ...process.env, PI_REVIEW_CHILD: "1" },
		});
		let stdout = "";
		let stderr = "";
		let timedOut = false;

		const timer = setTimeout(() => {
			timedOut = true;
			child.kill("SIGTERM");
			setTimeout(() => child.kill("SIGKILL"), 2_000).unref();
		}, timeoutMs);
		const abort = () => child.kill("SIGTERM");
		options.signal?.addEventListener("abort", abort, { once: true });

		child.stdout.on("data", (chunk) => {
			if (stdout.length < 128 * 1024) stdout += chunk.toString();
		});
		child.stderr.on("data", (chunk) => {
			if (stderr.length < 32 * 1024) stderr += chunk.toString();
		});
		child.on("error", reject);
		child.on("close", (code) => {
			clearTimeout(timer);
			options.signal?.removeEventListener("abort", abort);
			if (options.signal?.aborted) return reject(new Error("Independent review was aborted"));
			if (timedOut) return reject(new Error(`Independent review timed out after ${timeoutMs}ms`));
			if (code !== 0) return reject(new Error(stderr.trim() || `Independent reviewer exited with code ${code}`));
			resolve(stdout.trim());
		});
	});
}

export function parseJsonObject(text: string): Record<string, unknown> | undefined {
	const trimmed = text.trim();
	const unfenced = trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
	const start = unfenced.indexOf("{");
	const end = unfenced.lastIndexOf("}");
	if (start < 0 || end < start) return undefined;
	try {
		const value = JSON.parse(unfenced.slice(start, end + 1));
		return value && typeof value === "object" && !Array.isArray(value) ? value : undefined;
	} catch {
		return undefined;
	}
}
