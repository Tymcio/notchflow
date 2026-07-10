import { showToast, Toast } from "@raycast/api";
import { apiRequest } from "./api";

export default async function Command() {
  try {
    await apiRequest("/v1/island/show", "POST");
    await showToast({ style: Toast.Style.Success, title: "NotchFlow island shown" });
  } catch (error) {
    await showToast({ style: Toast.Style.Failure, title: "Could not reach NotchFlow", message: String(error) });
  }
}
