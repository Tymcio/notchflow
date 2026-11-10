# Homebrew tap

`Casks/notchflow.rb` is the cask for a personal tap. The official `homebrew/cask`
repository only accepts self-submitted apps with at least 75 GitHub stars, 30 forks
or 30 watchers, so NotchFlow starts in its own tap.

## Publish the tap (one time)

1. Create a public GitHub repository named `homebrew-tap` under the same account.
2. Copy `Casks/notchflow.rb` into it as `Casks/notchflow.rb` and push.
3. Users install with:

   ```bash
   brew install --cask tymcio/tap/notchflow
   ```

The cask uses `version :latest` and `auto_updates true`: Sparkle updates the app, so the
tap does not need a new commit for every release.

## Check it locally

```bash
brew style packaging/homebrew/Casks/notchflow.rb
```

## Moving to homebrew/cask later

Once the repository passes the notability threshold, submit the cask to
`Homebrew/homebrew-cask` with a pinned `version` and `sha256` (the official repo does not
accept `:latest` for apps with versioned downloads). `brew bump-cask-pr` keeps it current.
