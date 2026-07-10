# NotchFlow Raycast Extension

Raycast commands for the NotchFlow local API.

## Commands

1. **Control Media** — play/pause, next, previous
2. **What's Playing** — current track status
3. **Add Quick Note** — POST to `/v1/notes`
4. **Clipboard History** — browse local clipboard entries
5. **Show Island** — expand the notch panel

## Development

```bash
npm install
npm run dev
```

Configure **API Token** in Raycast extension preferences. **Base URL** is optional — the extension reads `~/Library/Application Support/NotchFlow/api.json` automatically. Default port: `47821`.
