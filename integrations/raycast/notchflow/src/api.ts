import { getPreferenceValues } from "@raycast/api";

type Preferences = {
  baseURL: string;
  apiToken: string;
};

export function getConfig(): Preferences {
  const prefs = getPreferenceValues<Preferences>();
  return {
    baseURL: prefs.baseURL.replace(/\/$/, ""),
    apiToken: prefs.apiToken,
  };
}

export async function apiRequest<T>(path: string, method: "GET" | "POST" = "GET", body?: unknown): Promise<T> {
  const { baseURL, apiToken } = getConfig();
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${apiToken}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    throw new Error(`NotchFlow API error (${response.status})`);
  }

  return (await response.json()) as T;
}

export type StatusResponse = {
  playing: boolean;
  title: string;
  premium: boolean;
  islandVisible: boolean;
};

export type NoteResponse = { text: string };
export type ClipboardResponse = { value: string };
