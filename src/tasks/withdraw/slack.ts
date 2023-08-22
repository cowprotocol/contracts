import { WebClient } from "@slack/web-api";

const { SLACK_TOKEN } = process.env;

export async function sendSlackMessage(
  channel: string,
  linkToProposal: string,
): Promise<void> {
  if (!SLACK_TOKEN) {
    throw Error("SLACK_TOKEN environment variable is not set");
  }
  const web = new WebClient(SLACK_TOKEN);
  const response = await web.chat.postMessage({
    channel,
    text: `<!here> please sign & execute the fee withdrawal transaction: ${linkToProposal}`,
  });
  if (!response.ok) {
    console.error(`Failed to send slack message: ${response}`);
  }
}
