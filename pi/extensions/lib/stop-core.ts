import { parseJsonObject } from "./reviewer.ts";

export interface CompletionVerdict {
	verdict: "COMPLETE" | "PREMATURE" | "UNCERTAIN";
	reason: string;
}

export function parseCompletionVerdict(text: string): CompletionVerdict | undefined {
	const value = parseJsonObject(text);
	const verdict = typeof value?.verdict === "string" ? value.verdict.toUpperCase() : undefined;
	const reason = value?.reason;
	if (verdict !== "COMPLETE" && verdict !== "PREMATURE" && verdict !== "UNCERTAIN") return undefined;
	if (typeof reason !== "string" || !reason.trim()) return undefined;
	return { verdict, reason: reason.trim() };
}
