# dotfiles

My Macs, in one public repo, applied by [chezmoi](https://www.chezmoi.io).
One command turns a fresh Mac into my Mac; one command re-syncs a Mac that
already has it. The repo holds no secrets, so a new machine can clone it before
it has any credentials.

The checkout lives at `~/repos/caillou/dotfiles` on every machine. It was
called `caillou/mac-setup` until 2026-09-11; GitHub redirects the old URL.

## Set up a fresh Mac

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply \
  --use-builtin-git=on \
  --purge-binary \
  --source ~/repos/caillou/dotfiles \
  caillou
```

That installs chezmoi, clones this repo, and applies it: Homebrew and packages,
fish, git and GitHub, asdf, the Claude Code CLI, Karabiner, macOS defaults,
the Dock, iTerm2, the display settings, and the checklist at the end.

The flags are not decoration:

- `--use-builtin-git=on` is required on a fresh Mac. `/usr/bin/git` is a
  Command Line Tools stub; chezmoi's automatic detection finds it and never
  falls back, and the stub opens the tools dialog and fails. The built-in git
  clones over HTTPS only, which is why this repo is public.
- `--purge-binary` deletes the curl-installed chezmoi once the apply is done.
  The Brewfile lists `chezmoi`, so Homebrew keeps it current from then on.
- `--source` fixes the checkout path. The config template records the path it
  was given, never a literal, so the same template works in CI.

### What it asks

Three questions, once per machine:

| prompt | default | effect |
|---|---|---|
| Managed by an employer | the answer of `profiles status -type enrollment` | no casks, no App Store apps |
| Install the personal package group | no | the personal formulae, casks and App Store apps |
| Install the embedded package group | no | platformio, open-ocd, dfu-util, gcc-arm-embedded |

The answers land in `~/.config/chezmoi/chezmoi.toml` under `[data]`. Edit them
there and the next apply uses the new values; `chezmoi init` never asks again.

Besides the prompts it needs your admin password, more than once. sudo's ticket
expires during `brew bundle` and `asdf install`, and the display step reads
preferences that belong to root on the first apply and after any change; a
settled Mac does not prompt for it. `gh` opens a browser window to
log in to GitHub, and macOS asks once for Automation consent when the wallpaper
is set through System Events.

The Safari settings (the Develop menu and the full URL in the address bar) need
one thing macOS never prompts for: Full Disk Access for the terminal running
the apply. Safari is sandboxed, and without it `defaults` writes to a file
Safari ignores while reporting success. The defaults script checks, skips the
Safari section with a message, and writes it on the next apply once the
terminal has been added under System Settings > Privacy & Security > Full Disk
Access. It quits Safari first, which restores its tabs on the next launch.

### How long

Two steps take almost all of the time and print almost nothing while they work:
the Homebrew installer, which downloads the Command Line Tools when they are
missing, and `brew bundle`. Budget the better part of an hour for the pair on a
fresh Mac, more when the cask list is long. Neither is hung.

Everything is safe to re-run, so an interrupted bootstrap resumes with
`chezmoi apply`. Expect to run it twice anyway: Karabiner writes its config
file only on first launch, so the first apply skips the rules build and the
checklist tells you to launch the app. Launch it, then apply again.

## Re-sync a Mac

```sh
chezmoi update
```

That is `git pull` plus `chezmoi apply`. To look before it changes anything:

```sh
chezmoi diff
```

Alongside the file changes, `chezmoi diff` lists the scripts that would run and
prints their text. What it cannot show is their effect: chezmoi does not run
scripts in a dry run, so reading a script is as close as a preview gets.

Scripts 60, 61 and 62 (defaults, Dock, Downloads view) are change-triggered:
chezmoi re-runs them when their rendered content changes and skips them
otherwise. To force them without editing anything:

```sh
chezmoi state delete-bucket --bucket=entryState
chezmoi apply
```

The usual reason is an apply that ran before the tool it needed was there, for
example a Dock rebuild that skipped because dockutil had not been installed
yet. `entryState` is the bucket chezmoi keys `run_onchange_` scripts in;
`scriptState` is the one for the run-once Homebrew installer, so deleting it
instead re-runs the installer and none of the three.

A macOS upgrade is the other reason. The upgrade to 27 put Apple's default
wallpaper back and emptied the Desktop icon settings, and a change-triggered
script cannot know that: its text did not change, so it does not run. After a
major upgrade, delete the bucket and apply, then read the checklist.

`entryState` also holds what chezmoi last wrote to each file, the record behind
the "has changed since chezmoi last wrote it" prompt. Deleting the bucket
deletes that too, so the apply right after it rewrites a hand-edited file
without asking. Run `chezmoi diff` first and `chezmoi re-add` anything worth
keeping.

## Editing loop

Edit the real file in the home directory, the way you would without chezmoi.
Then:

```sh
chezmoi status                         # which targets drifted
chezmoi diff ~/.config/fish/config.fish
chezmoi re-add ~/.config/fish/config.fish
```

`chezmoi re-add` copies the file back into the repo. With no argument it
re-adds every modified plain file. It refuses templates, which is the point of
keeping almost nothing templated.

`chezmoi edit ~/.config/fish/config.fish` skips the round trip and opens the
source file directly; add `--apply` to write the result out at the same time.

Commit and push from the source directory:

```sh
chezmoi cd
git add -A && git commit && git push
exit
```

On the other Mac, `chezmoi update`. If both machines changed the same file,
chezmoi refuses to overwrite silently; `chezmoi merge ~/.config/fish/config.fish`
opens a three-way merge of the destination (the file in the home directory),
the target (the rendered source) and the source file itself.

## Two fish rules

**Settings go in a file, never in a universal variable.** Put them in
`~/.config/fish/config.fish`, or in a snippet under `~/.config/fish/conf.d/`,
which fish reads first. `set -U` writes to `~/.config/fish/fish_variables`,
which fish rewrites at will and this repo does not manage, so a universal
variable stays on the machine where you set it. `conf.d/00-settings.fish` is
where the ones worth keeping ended up.

**Themes are the exception, but not through `fish_config theme save`.** Fish's
own manual marks that subcommand "not recommended", and the reason is the rule
above: it writes the colours to universal variables, so they land in
`fish_variables` and stay on one machine. The theme this repo carries is
`conf.d/fish_frozen_theme.fish`, the `set --global fish_color_*` lines fish
wrote when it moved theme variables out of universal scope, and it is a managed
file like any other. So changing the theme is a normal edit: try one with
`fish_config theme choose <name>`, which lasts for the session and writes
nothing, then put the colours you keep into `conf.d/fish_frozen_theme.fish`,
`chezmoi re-add`, commit.

Plugins are declared in `~/.config/fish/fish_plugins`, one repo per line.
`jorgebucaran/fisher` is the fourth line on purpose: `fisher update` installs
exactly the list it is given, so leaving fisher out of its own list uninstalls
fisher. Script 20 installs fisher when it is missing and runs `fisher update`
whenever the file's hash changes.

## Which files are templates

A file is a template when it needs something only chezmoi knows: the source
directory path, a machine fact, or the hash of another file. That is chezmoi's
own config (`.chezmoi.toml.tmpl`), the Brewfile, the shared script preamble
(`.chezmoitemplates/facts.sh`) and everything in `.chezmoiscripts/`.

Everything that lands in the home directory is a plain file and uses `$HOME` or
`~`, never a template variable, so the two Macs with their different usernames
read the same bytes and `chezmoi re-add` round-trips every edit.

Templates are edited on the repo side and applied outwards. There is no way
back from the rendered copy.

## Adding a package

Formulae, taps and fonts live in `.chezmoitemplates/Brewfile`, in a core block
and two blocks guarded by the `personal` and `embedded` flags. Fonts are casks
but belong in the Brewfile because they install on every Mac, a managed one
included.

Either order works:

```sh
brew install glow           # try it, then write it down
$EDITOR .chezmoitemplates/Brewfile
```

or add the line first and let `chezmoi apply` install it. The packages script
renders the Brewfile, appends the rows for this machine, and runs
`brew bundle` only when the result's hash changed or the last run failed.

A formula from a third-party tap needs the tap line written as
`tap "user/repo", trusted: true`. Since Homebrew 6 an untrusted tap is not
loaded at all, and a fresh Mac has never run `brew trust`, so the trust has
to travel with the Brewfile.

Casks and App Store apps are not in the Brewfile. They are rows in
`.chezmoidata/apps.yaml`, because two scripts read them:

```yaml
- { kind: cask, name: "obsidian", app: "Obsidian.app", group: core }
- { kind: mas, name: "409183694", app: "Keynote.app", group: core }
```

`kind` is cask or mas, `name` the cask name or the App Store id, `app` the
bundle in `/Applications` (empty when the package installs none, as with
ngrok), `group` one of core, personal, embedded. The packages script appends
the rows that belong on this machine, and only on an unmanaged Mac. A cask is
left out when its app is already in `/Applications` and Homebrew did not put it
there, so `brew bundle` never adopts or overwrites an app you installed by
hand. On a managed Mac the same table becomes the Self Service request list.

The generated Brewfile is at `~/.local/state/dotfiles/Brewfile`, not
`~/.Brewfile`. It is exactly what `brew bundle` ran with, appended casks
included, which makes it the file to check drift against:

```sh
brew bundle cleanup --file ~/.local/state/dotfiles/Brewfile
```

That lists what is installed but no longer in the list; `--force` actually
removes it. Nothing automates this, by design. Never edit that copy either, it
is rewritten on every apply.

Language runtimes are not packages. node and python are pinned in
`~/.tool-versions`, which asdf reads as the global default. Change the version
there, commit, apply; the asdf script adds the plugin and installs the version
but never runs `asdf set`, which would fight the managed file.

## Adding a macOS setting

Find the key by diffing the whole defaults database around the change:

```sh
defaults read >/tmp/before
# flip the setting in System Settings
defaults read >/tmp/after
diff /tmp/before /tmp/after
```

[macos-defaults.com](https://macos-defaults.com) and the nix-darwin defaults
modules are the two catalogues still maintained in 2026. The mathiasbynens
script is a catalogue only; it has not been updated since 2020.

The setting goes in `.chezmoiscripts/run_onchange_after_60-defaults.sh.tmpl`,
in the section for its domain (keyboard, input sources, scrolling, trackpad,
screenshots, Finder, Safari, window manager, Dock, Control Center, wallpaper,
dictation, power). Write it with the
type macOS stored, which the diff shows you: `-bool`, `-int`, `-float`,
`-string`.

Order matters in that script. It quits System Settings first, because System
Settings holds its panes in memory and writes them back on quit, undoing
everything. Then the writes. Then `activateSettings -u`, the private tool that
makes keyboard, trackpad and pointer values take effect without logging out.
Then `killall Finder Dock SystemUIServer TextInputMenuAgent ControlCenter`,
the five processes that cache what was written. If your key belongs to some other process, kill it there too.

Nested values that `defaults write` cannot express go through
`defaults export`, an edit, and `defaults import` on that domain. The dictation
hotkey is the example: its parameter is larger than a signed 64-bit integer.
Never edit a plist file directly, cfprefsd's cache will clobber it.

Two things that look like defaults but are not. The Dock's contents come from
`.chezmoidata/dock.yaml`, one app path per line, rebuilt by script 61.
Downloads opening in list view sorted by Date Added is a `.DS_Store` record,
written by the Python module in `.downloads-view/`.

All three scripts are change-triggered, so editing the script or the data file
is what makes them run. See the re-sync section for forcing a run without an
edit.

## Karabiner

The rules are TypeScript, not JSON. `.karabiner/` holds a
[karabiner.ts](https://github.com/evan-liu/karabiner.ts) project: `src/index.ts`
with the rules, a `package.json` asking for karabiner.ts `^1.38.0`, and a
committed `package-lock.json` pinning it to exactly 1.38.0 so every machine
builds the same rules. The folder is dot-prefixed, so chezmoi ignores it
instead of writing it into the home directory.

`npm run build` runs the file, which writes the rules into the "Default
profile" of `~/.config/karabiner/karabiner.json` and leaves Karabiner's other
settings alone. That file is never committed: Karabiner rewrites it whenever it
feels like it, and it ignores a symlink in its place.

Script 50 runs on every apply. It skips, with a message, unless
Karabiner-Elements is installed and has written its config file, which it does
on first launch. Otherwise it hashes `src/index.ts` plus the lockfile and runs
`npm ci` and `npm run build` when that hash changed or no successful build is
recorded. A Karabiner installed or launched later gets its rules on the next
sync.

To iterate without applying:

```sh
cd ~/repos/caillou/dotfiles/.karabiner
npm run dev      # tsx watch src/index.ts, rebuilds on save
npm run update   # bump karabiner.ts deliberately, then commit the lockfile
```

Under `npm run dev` each save rebuilds and Karabiner picks the rules up itself,
so a change is live without an apply.

After a wake-from-sleep the daemons sometimes need a kick: the fish function
`karabinerRestart` does it.

## Hammerspoon

`~/.hammerspoon` is three plain Lua files, applied like any other dotfile:
`init.lua`, `windows.lua` (the Ctrl+S window-layout modal) and
`status-message.lua`. No installer, no Lua toolchain, no tests. `init.lua`
watches the folder and reloads itself, so `chezmoi apply` is the whole edit
loop; Shift+Ctrl+backtick reloads by hand.

`~/.hammerspoon/Spoons` is never managed. Hammerspoon writes there at runtime.

`init.lua` installs the `hs` command line tool into `~/.local`. The installer
is two `ln -s` calls and creates no directories, so `dot_local/bin/.keep` and
`dot_local/share/man/man1/.keep` make chezmoi create `~/.local/bin` and
`~/.local/share/man/man1` on the first apply, before Hammerspoon ever loads.
A `.keep` file creates its folder and is never written itself.

A Hammerspoon from the portal runs translocated until its quarantine flag is
cleared, and its `hs` installer links into the throwaway copy, so the link
dies at the next restart. The quarantine script removes a link that dangles
or points into a translocated copy, and relaunches a translocated Hammerspoon
from `/Applications`, whose `init.lua` then writes a link that lasts.

Hammerspoon shows a dock icon and no menu bar icon. `init.lua` sets both
through `hs.dockIcon` and `hs.menuIcon`, which write the same preferences as
the two checkboxes in its settings window. Reload with Shift+Ctrl+backtick,
open the console by clicking the dock icon or with `hs -c "hs.openConsole()"`.

## iTerm2

iTerm2 loads its preferences from `.iterm2/` in this repo instead of
`~/Library/Preferences`. Script 63 sets four keys: `PrefsCustomFolder` and
`LoadPrefsFromCustomFolder` name the folder and switch to it, and the two
`NoSyncNeverRemindPrefsChangesLostForFile` keys turn "your changes will be
lost" into "save automatically". It skips when iTerm2 is not installed yet,
and it leaves the keys alone while iTerm2 is running: a running iTerm2 would
save the stock preferences it holds in memory over the repo plist on its next
quit. Quit iTerm2 and run `chezmoi apply` again.

The consequence is worth knowing: iTerm2 rewrites
`.iterm2/com.googlecode.iterm2.plist` when it quits, so changing a setting in
the UI shows up as repo drift. Quit iTerm2, `git status`, commit the plist like
any other edit. Those same four keys are excluded from what iTerm2
writes there, so no machine path or username reaches the committed file.

The same write-back loses an inbound change: run `chezmoi update` from inside
iTerm2 and the pulled plist survives only until iTerm2 quits, when it saves the
preferences it still holds in memory over the file. When the other Mac may have
changed iTerm2 settings, pull from another terminal, or quit iTerm2 first.

## Managed Macs

`managed` is answered once at init from `profiles status -type enrollment` and
stored in `~/.config/chezmoi/chezmoi.toml`. No script re-detects it, so
correcting a wrong guess means editing `managed = true` or `managed = false`
there and applying again.

On a managed Mac the apply installs formulae and fonts and nothing else. Casks
and App Store apps are never appended to the Brewfile, so Homebrew cannot fight
the employer's software distribution. Instead the report at the end lists the
apps from `.chezmoidata/apps.yaml`, in the groups this machine enabled, whose
bundle is missing from `/Applications` right now. That list is computed live,
not remembered from an earlier run. Rows that install no app bundle are left
out, because a portal of apps cannot hand you a binary like ngrok.

Apps that arrive later are picked up on the next apply. iTerm2, Karabiner and
Hammerspoon are each gated on being installed, so the sync neither fails nor
forgets them.

An app from the portal keeps the quarantine attribute its download got, and
nothing ever moves it in the Finder, so macOS runs it from a throwaway copy
under `/private/var/folders/.../AppTranslocation/` with a new path on every
launch. `run_after_55-quarantine.sh.tmpl` clears the flag on every app the
table names that carries it, through sudo when the bundle belongs to root.
An app that has been launched and approved by Gatekeeper is left alone: it
carries `com.apple.provenance`, runs from `/Applications` already, and SIP
refuses to strip its flag even for root. A Homebrew cask ends up in that
state too, since Cask writes a quarantine record of its own. A settled Mac
is not prompted. The script runs on a managed Mac only, where the portal is
an installer.

VS Code from the portal comes without the `code` command. The Homebrew cask
links it into `/opt/homebrew/bin`; a Self Service install links nothing. So
`dot_local/bin/symlink_code.tmpl` links `~/.local/bin/code` to the launcher
inside the app bundle. The template renders empty while the app is missing,
and chezmoi creates nothing from an empty symlink, so a Mac without VS Code
carries no dangling link and the apply after the app arrives adds it. lazygit's
managed config opens files in VS Code through that same `code` command, so it
works on both kinds of Mac once the launcher is there.

## Manual checklist

Some of macOS cannot be set by a script. `run_after_90-report.sh.tmpl` runs
last on every apply and prints the items that apply to the machine in front of
you. The full list is here.

Every apply, while the app is installed:

- **Approve Karabiner-Elements** in System Settings: Privacy & Security >
  Input Monitoring for Karabiner-Core-Service and Accessibility for
  Karabiner-Elements; and under General > Login Items & Extensions the two
  background services, "Karabiner-Elements Privileged Daemons" and
  "Karabiner-Elements Non-Privileged Agents", plus the driver extension.
  Those are the names since Karabiner 15; older releases asked for
  `karabiner_grabber` and `karabiner_observer` instead. Whether an approval was
  already given lives in the TCC database, which no script may read, so this is
  printed as long as the app is there.
- **Approve Hammerspoon** in the same pane: Accessibility, plus Input
  Monitoring when a hotkey does not fire.
- **Launch Karabiner-Elements once**, while
  `~/.config/karabiner/karabiner.json` does not exist. Karabiner creates the
  file and its Default profile on first launch; the next apply builds the rules
  into it.
- **Turn dictation on once.** Press Control twice, accept the consent dialog,
  then let the language models for en_US, fr_CH and de_CH download in System
  Settings > Keyboard > Dictation.

Until the script that writes it records success in `~/.local/state/dotfiles/`:

- **Check the tracking speed** in System Settings > Trackpad and > Mouse. The
  defaults script writes it and reads it back through `hidutil`; the item
  disappears once the read-back agreed and left `pointer-speed-applied`.
- **Turn "Automatically adjust brightness" off** in System Settings > Displays,
  on every display. The display script does this through root's CoreBrightness
  preferences and reads it back (`auto-brightness-applied`).

Once, on a Mac that generated its own ssh key (`ssh-key-generated`):

- **Paste the public key into Azure DevOps**, under User settings > SSH public
  keys > New key. Azure DevOps has no API for keys, so this is the one upload
  that stays manual; GitHub gets the same key from `gh ssh-key add`. The report
  prints the key. Once it is pasted, stop the reminder with
  `rm ~/.local/state/dotfiles/ssh-key-generated`.

On an unmanaged Mac whose last package run failed (`packages-status`):

- **Finish the package install.** The report says what `brew bundle` exited
  with and names the entries still missing, then `chezmoi apply` again. A
  signed-out App Store is the usual cause: sign in there and re-run.

On a managed Mac:

- **Request the missing apps from the Self Service Portal.** The report lists
  them, as described above.

Every apply, while Homebrew is installed:

- **Upgrade the Homebrew packages** with `brew update && brew upgrade` when you
  want the latest versions. `brew bundle` installs what the Brewfile names and
  leaves an installed package at whatever version it has, so the apply never
  upgrades anything.

The apply asks for your admin password more than once by design: the sudo
ticket expires during the long steps, and the display module reads preferences
that belong to root until `auto-brightness-applied` records that the flag is
off. After that it does not prompt.

## Layout

```
.chezmoi.toml.tmpl         prompts and machine facts, rendered to ~/.config/chezmoi/chezmoi.toml
.chezmoidata/apps.yaml     casks and App Store apps: kind, name, app, group
.chezmoidata/dock.yaml     the Dock allow-list, in order
.chezmoitemplates/Brewfile formulae, taps and fonts
.chezmoitemplates/facts.sh shared script preamble: environment, predicates, markers
.chezmoiscripts/           everything the apply runs, see below
.downloads-view/           the Python module that writes the Downloads .DS_Store record
.iterm2/                   iTerm2's preferences folder, loaded and saved in place
.karabiner/                karabiner.ts source for the keyboard rules
dot_config/private_fish/   fish; `private_` means mode 0700
dot_config/lazygit/        lazygit's config; its state and PR cache next to it are never managed
dot_hammerspoon/           init.lua, windows.lua, status-message.lua
dot_local/                 the `code` symlink and the folders the `hs` installer needs
dot_*                      the rest of the home directory, `dot_` standing in for the leading dot
docs/PRDs/                 the PRD and the research behind all of this
tests/                     bats suites, the Python unit tests, shellcheck and the secrets check
```

Scripts are numbered because chezmoi runs them in alphabetical order. The
two-digit prefix is the whole ordering rule, so `ls .chezmoiscripts` is the
current list and adding a script means adding one file with a free number:

| prefix | what runs there |
|---|---|
| `00` | the Homebrew installer, once, before any file is written |
| `10` | packages |
| `2x` | shells: fish plugins, the login shell |
| `3x` | GitHub and ssh |
| `4x` | developer tools: asdf, the Claude Code CLI |
| `5x` | keyboard, and the quarantine flag on apps from the portal |
| `6x` | macOS settings: defaults, Dock, Downloads view, iTerm2, display |
| `90` | the report, last |

Two rules behind the names. The Homebrew installer is the only `before`
script and the only one without the shared preamble, because chezmoi keys a
run-once script by its rendered content and an edit to the preamble would
re-run the installer. And only pure writers use `run_onchange_`: chezmoi
records a change-triggered script as done the moment it exits zero, so a script
that skipped because its tool was missing would never be retried. Every other
script runs on every apply and decides for itself, keeping its input hash and
its outcome in `~/.local/state/dotfiles/`.

That state directory is also where the generated Brewfile and the markers the
report reads live. Deleting a marker makes the report mention its item again.

## Tests

```sh
bats --jobs "$(sysctl -n hw.ncpu)" tests   # one bats file alone: bats tests/iterm2.bats
uv run --with ds_store python3 -m unittest discover -s tests
tests/shellcheck-scripts.sh
tests/secrets-check.sh
```

`--jobs` needs GNU `parallel`, which the Brewfile installs. Every test runs in
its own temporary tree, so the files run side by side without touching each
other.

Nothing there touches the machine it runs on: `HOME` and the XDG variables
point into a temporary tree, and brew, dockutil, asdf, fish and Finder are
stubs. The same four run on every commit through lefthook, and CI runs them on
a macOS runner plus a dry-run apply. The pre-commit hook is not something a
clone carries: it lives in the checkout's `.git`, and chezmoi's built-in git
creates no hooks folder at all. Script 11 installs it on every apply where it
is missing, so a bootstrapped Mac commits through the hook from the first
sync on.

## History

The design, the alternatives that lost, and every captured value are in
[docs/PRDs/2026-09-10-chezmoi-mac-bootstrap/](docs/PRDs/2026-09-10-chezmoi-mac-bootstrap/):
[prd.md](docs/PRDs/2026-09-10-chezmoi-mac-bootstrap/prd.md) for the decisions,
[research-notes.md](docs/PRDs/2026-09-10-chezmoi-mac-bootstrap/research-notes.md)
for the sources and the readings they came from.

Two archived repos hold what did not move here:
[caillou/keyboard](https://github.com/caillou/keyboard) has the Hammerspoon
space-fn engine and its Lua test suite, and
[caillou/karabiner.ts](https://github.com/caillou/karabiner.ts) has the
original starter project the `.karabiner/` folder came from.
