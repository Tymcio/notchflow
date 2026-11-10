# Homebrew tap

`Casks/notchflow.rb` is the cask for a personal tap. The official `homebrew/cask`
repository only accepts self-submitted apps with at least 75 GitHub stars, 30 forks
or 30 watchers, so NotchFlow starts in its own tap.

## The tap

Published at [Tymcio/homebrew-tap](https://github.com/Tymcio/homebrew-tap). Keep `Casks/notchflow.rb`
here and there in sync. Users install with:

```bash
brew tap tymcio/tap
brew trust --cask tymcio/tap/notchflow   # Homebrew 7 asks once for third-party casks
brew install --cask notchflow
```

The cask uses `version :latest` (always the latest release download), and Sparkle updates the app,
so the tap does not need a new commit for every release.

## Check it locally

```bash
brew style packaging/homebrew/Casks/notchflow.rb
```

## Moving to homebrew/cask later

Once the repository passes the notability threshold, submit the cask to
`Homebrew/homebrew-cask` with a pinned `version` and `sha256` (the official repo does not
accept `:latest` for apps with versioned downloads). `brew bump-cask-pr` keeps it current.
