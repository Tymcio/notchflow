/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Base URL - From ~/Library/Application Support/NotchFlow/api.json */
  "baseURL": string,
  /** API Token - Copy from NotchFlow Settings → Integrations */
  "apiToken": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `control-media` command */
  export type ControlMedia = ExtensionPreferences & {}
  /** Preferences accessible in the `whats-playing` command */
  export type WhatsPlaying = ExtensionPreferences & {}
  /** Preferences accessible in the `add-quick-note` command */
  export type AddQuickNote = ExtensionPreferences & {}
  /** Preferences accessible in the `clipboard-history` command */
  export type ClipboardHistory = ExtensionPreferences & {}
  /** Preferences accessible in the `show-island` command */
  export type ShowIsland = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `control-media` command */
  export type ControlMedia = {}
  /** Arguments passed to the `whats-playing` command */
  export type WhatsPlaying = {}
  /** Arguments passed to the `add-quick-note` command */
  export type AddQuickNote = {}
  /** Arguments passed to the `clipboard-history` command */
  export type ClipboardHistory = {}
  /** Arguments passed to the `show-island` command */
  export type ShowIsland = {}
}

