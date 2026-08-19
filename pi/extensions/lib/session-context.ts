export interface ConversationMessage {
	entryId: string;
	role: string;
	text: string;
}

function contentText(content: unknown): string {
	if (typeof content === "string") return content.trim();
	if (!Array.isArray(content)) return "";
	return content
		.map((part) => {
			if (!part || typeof part !== "object") return "";
			const value = part as { type?: unknown; text?: unknown; thinking?: unknown };
			if (value.type === "text" && typeof value.text === "string") return value.text;
			if (value.type === "thinking" && typeof value.thinking === "string") return value.thinking;
			return "";
		})
		.filter(Boolean)
		.join("\n")
		.trim();
}

export function conversationMessages(entries: readonly unknown[]): ConversationMessage[] {
	const messages: ConversationMessage[] = [];
	for (const raw of entries) {
		if (!raw || typeof raw !== "object") continue;
		const entry = raw as { id?: unknown; type?: unknown; message?: unknown };
		if (entry.type !== "message" || !entry.message || typeof entry.message !== "object") continue;
		const message = entry.message as { role?: unknown; content?: unknown };
		if (typeof message.role !== "string") continue;
		const text = contentText(message.content);
		if (!text) continue;
		messages.push({
			entryId: typeof entry.id === "string" ? entry.id : `message-${messages.length}`,
			role: message.role,
			text,
		});
	}
	return messages;
}

export function recentUserMessages(entries: readonly unknown[], limit = 5): ConversationMessage[] {
	return conversationMessages(entries)
		.filter((message) => message.role === "user")
		.slice(-limit);
}

export function latestAssistantMessage(entries: readonly unknown[]): ConversationMessage | undefined {
	return conversationMessages(entries)
		.filter((message) => message.role === "assistant")
		.at(-1);
}

export function latestUserMessage(entries: readonly unknown[]): ConversationMessage | undefined {
	return recentUserMessages(entries, 1)[0];
}
