import { Action, ActionPanel, Clipboard, Icon, List, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import { apiRequest, ClipboardResponse } from "./api";

export default function Command() {
  const [items, setItems] = useState<ClipboardResponse[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const data = await apiRequest<ClipboardResponse[]>("/v1/clipboard");
        setItems(data);
      } catch (err) {
        setError(String(err));
      }
    })();
  }, []);

  if (error) {
    return <List><List.EmptyView title="NotchFlow unavailable" description={error} /></List>;
  }

  return (
    <List>
      {items.map((item, index) => (
        <List.Item
          key={`${index}-${item.value.slice(0, 24)}`}
          title={item.value}
          icon={Icon.Clipboard}
          actions={
            <ActionPanel>
              <Action
                title="Copy to Clipboard"
                icon={Icon.Clipboard}
                onAction={async () => {
                  await Clipboard.copy(item.value);
                  await showToast({ style: Toast.Style.Success, title: "Copied" });
                }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
