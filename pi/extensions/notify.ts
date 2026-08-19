import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function notify(title: string, body: string): void {
	if (process.env.WT_SESSION) {
		const type = "Windows.UI.Notifications";
		const script = [
			`$mgr = [${type}.ToastNotificationManager, ${type}, ContentType = WindowsRuntime]`,
			`$xml = [${type}.ToastNotificationManager]::GetTemplateContent([${type}.ToastTemplateType]::ToastText01)`,
			`$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('${body}')) > $null`,
			`$mgr::CreateToastNotifier('${title}').Show([${type}.ToastNotification]::new($xml))`,
		].join("; ");
		execFile("powershell.exe", ["-NoProfile", "-Command", script]);
		return;
	}
	if (process.env.KITTY_WINDOW_ID) {
		process.stdout.write(`\x1b]99;i=pi:d=0;${title}\x1b\\`);
		process.stdout.write(`\x1b]99;i=pi:p=body;${body}\x1b\\`);
		return;
	}
	process.stdout.write(`\x1b]777;notify;${title};${body}\x07`);
}

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", async (_event, ctx) => {
		// Terminal escape notifications are valid only in the interactive TUI.
		if (ctx.mode === "tui" && ctx.isIdle()) notify("Pi", "Ready for input");
	});
}
