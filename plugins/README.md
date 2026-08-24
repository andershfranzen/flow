# Plugins

Drop a directory here with a `plugin.rb`; it is loaded at boot. A plugin is
ordinary Ruby with full access to the app — no manifest, no store, no license
key. See `docs/EXTENDING.md` for the API surface and an example.

This directory is gitignored apart from this file, so your plugins survive
`git pull`. Distribute a plugin as a git repo people clone into here.
