import { Action, ActionPanel, Form, showToast, Toast, useNavigation } from "@raycast/api";
import { apiRequest } from "./api";

export default function Command() {
  const { pop } = useNavigation();

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Save Note"
            onSubmit={async (values: { text: string }) => {
              if (!values.text.trim()) {
                await showToast({ style: Toast.Style.Failure, title: "Note cannot be empty" });
                return;
              }
              await apiRequest("/v1/notes", "POST", { text: values.text.trim() });
              await showToast({ style: Toast.Style.Success, title: "Note saved" });
              pop();
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextArea id="text" title="Note" placeholder="Type your quick note…" />
    </Form>
  );
}
