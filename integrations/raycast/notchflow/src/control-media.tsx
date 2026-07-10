import { Action, ActionPanel, List, showToast, Toast } from "@raycast/api";
import { apiRequest } from "./api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="Play / Pause"
        icon="⏯️"
        actions={
          <ActionPanel>
            <Action
              title="Toggle"
              onAction={async () => {
                await apiRequest("/v1/media/play-pause", "POST");
                await showToast({ style: Toast.Style.Success, title: "Toggled playback" });
              }}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Next Track"
        icon="⏭️"
        actions={
          <ActionPanel>
            <Action
              title="Next"
              onAction={async () => {
                await apiRequest("/v1/media/next", "POST");
                await showToast({ style: Toast.Style.Success, title: "Skipped forward" });
              }}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Previous Track"
        icon="⏮️"
        actions={
          <ActionPanel>
            <Action
              title="Previous"
              onAction={async () => {
                await apiRequest("/v1/media/previous", "POST");
                await showToast({ style: Toast.Style.Success, title: "Skipped back" });
              }}
            />
          </ActionPanel>
        }
      />
    </List>
  );
}
