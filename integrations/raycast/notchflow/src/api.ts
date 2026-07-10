import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { getPreferenceValues } from "@raycast/api";

type Preferences = {
  baseURL?: string;
  apiToken: string;
};

type ApiConfig = {
  baseURL: string;
};

function readApiConfig(): ApiConfig | null {
  const configPath = `${homedir()}/Library/Application Support/NotchFlow/api.json`;
  if (!existsSync(configPath)) {
    return null;
  }

  try {
    return JSON.parse(readFileSync(configPath, "utf8")) as ApiConfig;
  } catch {
    return null;
  }
}

export function getConfig(): Required<Preferences> {
  const prefs = getPreferenceValues<Preferences>();
  const fromFile = readApiConfig();
  const baseURL = (prefs.baseURL || fromFile?.baseURL || "").replace(/\/$/, "");

  if (!baseURL) {
    throw new Error("Brak adresu API. Uruchom NotchFlow z włączonym Local API lub ustaw Base URL w preferencjach.");
  }

  if (!prefs.apiToken) {
    throw new Error("Brak tokenu API. Skopiuj go z NotchFlow → Ustawienia → Integracje.");
  }

  return {
    baseURL,
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
