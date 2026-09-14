# Bootstrap and sync Macs with chezmoi

## Problem Statement

I set up a new, employer-managed Mac and want it to feel like my personal Mac within minutes: same shell, same prompt, same fonts, same keyboard remaps, same Finder, Dock, screenshot, trackpad and Desktop behaviour, same git and GitHub tooling, same language runtimes.

Today none of that is reproducible. This repo is a README of commands to paste by hand plus a defaults script from 2023 that has drifted from what my Mac actually does. My fish config, prompt settings, git config, Hammerspoon and Karabiner setups live only on one machine. The two Macs have different usernames, so even copying files would break every hardcoded path. The new Mac is enrolled in MDM, so desktop apps come from the employer and must not be installed or adopted by Homebrew there. And some macOS settings are not scriptable at all, but nobody tells me which ones I still have to click.

Every new machine, and every "why is this different here", costs an afternoon.

## Solution

One public git repo, `caillou/dotfiles`, managed by chezmoi, that turns a fresh Mac into my Mac with one command, and re-syncs any Mac with one command.

The first command installs chezmoi, clones the repo, installs Homebrew (which brings the Command Line Tools), and applies everything: packages, shell, git, asdf, Hammerspoon and Karabiner configs, macOS defaults, Dock, wallpaper, iTerm2. It asks once whether the machine is personal and which optional package groups it should get, detects on its own whether the machine is managed, and remembers the answers. On a managed Mac it installs only command-line tools and fonts, and prints which desktop apps are missing so I can request them from the employer's portal.

At the end it prints the short list of things macOS refuses to let a script do, so I click through those once and I'm done. Re-syncing later is `chezmoi update`.

## User Stories

1. As a Mac owner, I want to bootstrap a fresh Mac with a single command, so that I never paste a README by hand again.
2. As a Mac owner, I want to re-sync an existing Mac with a single command, so that a change made on one machine reaches the other without thinking.
3. As a Mac owner, I want to see a diff of what a sync would change before it changes anything, so that a mistake in the repo cannot surprise me.
4. As a user with different usernames on different Macs, I want every path in my config derived from the actual home directory, so that the same files work on both machines.
5. As an employee with a managed Mac, I want the setup to detect MDM enrollment on its own, so that I don't have to remember which mode to run.
6. As an employee with a managed Mac, I want to override the detected mode explicitly, so that detection getting it wrong doesn't block me.
7. As an employee with a managed Mac, I want no desktop apps or App Store apps installed by Homebrew there, so that Homebrew never fights the employer's software distribution.
8. As an employee with a managed Mac, I want a printed list of the apps from my app list that are missing, so that I can request them from the Self Service Portal.
9. As a Mac owner, I want a cask skipped when its app already exists in Applications, so that the bootstrap never aborts on a pre-installed app and never adopts one.
10. As a Mac owner, I want fonts installed on every machine, managed or not, so that my terminal looks the same everywhere.
11. As a Mac owner, I want one curated package list with optional groups such as personal and embedded, so that the work Mac doesn't receive games and synth toolchains.
12. As a Mac owner, I want to answer the group questions once per machine and be able to change them later in a config file, so that the choice is durable and editable.
13. As a Mac owner, I want manually installed packages left alone by the sync, so that experimenting doesn't get undone.
14. As a Mac owner, I want a documented two-step way to add a package to the list, so that the list stays the source of truth.
15. As a fish user, I want fish installed, configured with my abbreviations, prompt, colours and plugins, and registered as my login shell, so that the first terminal I open is mine.
16. As a fish user, I want the settings currently hiding in fish's universal variables moved into versioned files, so that they reach other machines and the dead ones disappear.
17. As a Claude Code user, I want the zsh login profile mirroring the fish environment, so that non-interactive tool shells find Homebrew, asdf and the locale.
18. As a git user, I want my gitconfig with the personal identity as default and an ICFM identity for the ICFM repos folder, so that commits carry the address each client expects.
19. As a git user, I want the identity override to work on a folder that doesn't exist yet, so that the first ICFM clone on a new Mac is already correct.
20. As a GitHub user, I want gh installed, logged in once through the browser, and my aliases in place, so that pull request work is the same on both Macs.
21. As an ssh user, I want a fresh RSA key generated on any Mac that has none, uploaded to GitHub automatically and printed for Azure DevOps, so that keys are never copied between machines and Azure DevOps still accepts them.
22. As an ssh user, I want my ssh client config with agent forwarding and keep-alive, so that remote sessions behave as they do today.
23. As a developer, I want asdf installed from Homebrew with my plugins and global tool versions, so that node and python are present at the versions I use.
24. As a developer, I want the old git-clone asdf on my current Mac retired without losing installed versions, so that migration costs nothing.
25. As a keyboard nerd, I want my Hammerspoon config managed as plain files and my Karabiner rules generated from source inside the same repo, so that keyboard behaviour is versioned with everything else and edited the same way.
26. As a keyboard nerd, I want the Karabiner build skipped when Karabiner isn't installed or hasn't been launched yet, and retried on the next sync, so that a managed Mac without it doesn't fail the sync and a late install still gets its rules.
27. As a Mac user, I want F1 to F12 to be standard function keys and the Fn key alone to do nothing, so that the printed media keys need Fn and nothing pops up by accident.
28. As a Mac user, I want the key repeat fast, press-and-hold off, and smart quotes, dashes, periods and capitalisation off, so that typing code isn't fought by the OS.
29. As a Mac user, I want natural scrolling off and swipe-between-pages off, so that scrolling matches my other Mac.
30. As a trackpad user, I want tap to click, two-finger secondary click, silent light clicks, no force click, no three-finger drag, and my gesture assignments, so that the trackpad behaves identically on both Macs.
31. As a trackpad user, I want the pointer speed set to my usual notch with a best-effort apply and a warning if it didn't stick, so that I only visit the settings pane when the script really couldn't do it.
32. As a Mac user, I want screenshots saved to Downloads as PNG with no floating thumbnail, so that a capture is just a file.
33. As a Finder user, I want new Finder windows to open Downloads, so that Cmd+N lands where my files arrive.
34. As a Finder user, I want Downloads to open in list view with a Date Added column, sorted newest first, so that the latest download is always on top.
35. As a Finder user, I want extensions shown, the status bar on, folders sorted first, no extension-change warning, and no .DS_Store files on network or USB volumes, so that Finder behaves like my other Mac.
36. As a Desktop user, I want a black wallpaper, desktop items hidden, and, should items ever show, my icon size, grid and sort order, so that the Desktop is calm.
37. As a Desktop user, I want clicking the wallpaper to do nothing outside Stage Manager, and widgets hidden on the Desktop, so that a stray click never sweeps my windows away.
38. As a Dock user, I want the Dock hidden with my delay, tiny tiles with magnification, no recents, no launch animation, no hot corners, so that the Dock is out of the way until I want it.
39. As a Dock user, I want the Dock to contain exactly an allow-list of apps plus a Downloads stack in fan view sorted by date added, so that Apple's default set is gone.
40. As a dictation user, I want dictation enabled with the press-Control-twice shortcut and my three languages listed, so that speech-to-text is a double tap away.
41. As a laptop user, I want the Mac to never sleep on the power adapter when the display is off, display sleep at my timings, and no dimming on battery, so that remote sessions and background jobs survive.
42. As a laptop user, I want auto-brightness turned off for every display, with a read-back and a clear manual instruction if the write didn't hold, so that the screen stops adapting. True Tone stays at its default.
43. As an iTerm2 user, I want iTerm2 to load and save its preferences from a folder in the repo, so that profile, font and colours sync in both directions.
44. As a Mac owner, I want a printed checklist of the steps macOS won't let a script do, so that I know exactly what's left after the bootstrap.
45. As a Mac owner, I want every script safe to re-run, so that an interrupted bootstrap resumes with the same command.
46. As a Mac owner, I want no secret in the repo, so that it can stay public and be cloned anonymously on a fresh Mac.
47. As the maintainer, I want a README that explains bootstrap, re-sync, adding a package, adding a defaults key and the manual checklist, so that future me doesn't have to re-derive this conversation.
48. As the maintainer, I want the repo renamed to dotfiles and my current Mac migrated onto it, so that the current Mac is the first machine kept in sync, not an exception.
49. As a Claude Code user, I want the CLI installed by the bootstrap on both Macs, so that a fresh Mac can run it without a manual step.

## Implementation Decisions

### Tooling and repo

- chezmoi manages the files. Files are copied, never symlinked: macOS 14 and later rewrite symlinked preference files, and Karabiner ignores changes to a symlinked config.
- Bootstrap follows chezmoi's canonical pattern: the official installer, then `init --apply` with the built-in git enabled and the installer's `--purge-binary` flag, so the curl-installed binary is removed once Homebrew's takes over. The built-in git is required because a fresh Mac's `/usr/bin/git` is a stub that opens the Command Line Tools dialog and fails; chezmoi's automatic fallback doesn't trigger because the stub counts as present.
- The built-in git clones over HTTPS only, so the repo stays public and contains no secrets by construction.
- The existing GitHub repo `caillou/mac-setup` is renamed to `caillou/dotfiles`. GitHub redirects the old URL.
- The chezmoi source directory is `~/repos/caillou/dotfiles` on every machine. The bootstrap passes it with `--source`; the config template records whatever path was passed (`.chezmoi.sourceDir`), never a literal, so the same template works on the CI runner. It is the only repo the setup needs: the Hammerspoon config is managed as files and the Karabiner source lives in a project directory inside it. The former `caillou/keyboard` and `caillou/karabiner.ts` repos are archived with a pointer to dotfiles; their history and the keyboard repo's test suite stay there.
- chezmoi itself is listed in the Brewfile so Homebrew keeps it current.
- Re-sync is plain `chezmoi update`. No alias, no wrapper.

### Machine facts and configuration data

- The config template detects enrollment with `profiles status -type enrollment` and uses the result as the default of a once-only prompt for `managed`, so the stored answer survives re-inits and can be edited in the config file. All prompts have defaults; CI passes `--promptDefaults`.
- The config template prompts once for group flags, initially `personal` and `embedded`, and records them. Names are finalised when the package list is sorted.
- The Intune MDM and the ManageEngine self-service agent coexist on the work Mac; detection uses only the generic enrollment command, never a vendor agent.
- A small shell library provides pure predicates used by several scripts: is managed, is app bundle present in Applications, is command available, is key already at value. It lives in chezmoi's templates directory and is inlined into every script with a template include, because scripts are separate processes that cannot source a file that may not be applied yet. The same include sets up the environment every script needs: Homebrew's shellenv and the asdf shims on the path, since scripts run in plain `sh` without the user's shell config.
- Scripts record outcomes for the final report as marker files in a state directory under `~/.local/state/dotfiles/` (ssh key generated, pointer speed applied, auto-brightness applied, last package-run status). Scripts whose outcome depends on machine state also keep their own input hash there, so they run on every apply and exit early when nothing changed; chezmoi's change-triggered mode is reserved for pure writers, because chezmoi records a change-triggered script as done the moment it exits zero, which would turn a skipped or half-failed run into a permanent skip.

### Homebrew and packages

- A run-once "before" script guarded to macOS runs `sudo -v` and the official Homebrew installer, which installs the Command Line Tools headlessly when missing. No separate tools wait loop.
- One templated Brewfile: a core section for every machine, then blocks guarded by the `personal` and `embedded` flags. Formulae and fonts always. Casks and App Store entries only when not managed. The cask lines are appended by the packages script at run time from the cask table, keeping only casks whose app bundle is absent from Applications or whose Caskroom entry exists (a Homebrew-installed cask stays listed, so `brew bundle cleanup` remains meaningful); doing this in the script keeps the template pure and testable and the rendered file's hash stable.
- The cask and App Store lists are data, not prose: a chezmoi data file with one row per entry giving the Homebrew name or App Store id, the app bundle name and the group. The packages script and the managed-Mac report both read it. The reviewed classification is in the research notes.
- `brew bundle` adopts existing casks on its own, so the presence filter above is what keeps story 9 true. `brew bundle` continues past failing entries and exits non-zero at the end; the packages script records that exit status as a marker instead of propagating it, so a signed-out App Store or a flaky download never aborts the apply, and the report says "sign in to the App Store and re-run" when the status was non-zero. No pre-check of the App Store sign-in: the `mas` command no longer offers one.
- The list is the classification reviewed with the user and recorded in the research notes: core, personal, embedded, and a drop list. Duplicate casks are dropped.
- The packages script runs on every apply, hashes the rendered Brewfile plus the cask table into its marker, and runs `brew bundle` only when the hash changed or the last run failed. Cleanup is never automated; `brew bundle cleanup` is a documented manual check.
- Homebrew never adopts an existing app. On a managed Mac the report script prints the casks from the app list whose apps are missing, read live from Applications; the packages script prints nothing of the kind.

### Shell

- fish config is written with home-relative paths (`~`, `$HOME`) and is not a template, so `chezmoi re-add` works on it. Abbreviations, locale, pager, path additions, Homebrew shellenv, asdf init and the Karabiner restart function are managed.
- The frozen theme file that fish 4.3 generated from the Ayu Dark colours is managed as a plain conf.d file. A new conf.d file holds the settings currently in universal variables that are worth keeping: XDG config home, emoji width, and the Pure prompt options that differ from Pure's defaults. Which Pure options differ is determined by diffing against Pure's defaults during the migration.
- The universal variables file is not managed. Migration on the current Mac erases the dead entries: BrowserStack, pyenv, Spacefish, the 28 colour variables superseded by the theme file.
- Plugins are z, Pure and fzf via fisher, declared in the `fish_plugins` file, which carries `jorgebucaran/fisher` as a fourth line: fisher rewrites the file with itself included after every run and uninstalls whatever the file omits, so leaving fisher out would uninstall fisher. A change-triggered script installs fisher if absent and runs `fisher update`.
- fish becomes the login shell: appended to `/etc/shells` if missing, then `chsh`, both guarded. On an account whose password is federated (Platform SSO) `chsh` can reject the local password; the script then falls back to `sudo dscl . -create /Users/$USER UserShell <fish>`.
- The zsh login profile, zshrc, bash profile and readline config are managed as today, written with home-relative paths. The asdf line changes to the Homebrew asdf form.
- No dotfile target is a template except chezmoi's own config and the Brewfile; the iTerm2 pointer and the scripts are templates because they need the source path, machine facts or change hashes. Every other file, including the defaults script, is plain and uses `$HOME`, so edits made in the home directory can be copied back with `chezmoi re-add`.

### Git, GitHub, ssh

- gitconfig: personal identity as default, `pull.ff only`, default branch main, comment char `|`, a conditional include for `~/repos/icfm/` pointing at an ICFM identity file managed at `~/.config/git/icfm.gitconfig`. The BKW and Apprentice overrides are dropped. The global ignore is managed.
- gh's `config.yml` with the `co` alias is managed; `hosts.yml` holds the token and is never managed. The GitHub script runs on every apply and does nothing once logged in and the key is registered; otherwise it runs the browser login (`--web`, host github.com, ssh protocol, requesting the key-upload scope), uploads the ssh key (`gh ssh-key add` is idempotent), and switches the dotfiles checkout's origin from the HTTPS URL the built-in git cloned to the ssh URL, so pushes from the new Mac work. The login is gated on `gh auth token`, a local read, before `gh auth status`, so an offline settled Mac is never sent to the browser; the trade-off is that a token revoked on github.com no longer re-logs-in on its own and needs `gh auth login` by hand. The same script seeds `known_hosts` for github.com from `gh api meta` over TLS, never from `ssh-keyscan`, which would be trust on first use on an employer network.
- ssh: one RSA 4096 key generated when the ssh folder has no key, because Azure DevOps accepts RSA only and has no API for adding keys. The public key is uploaded to GitHub via gh and printed for manual paste into Azure DevOps. The ssh client config (agent forwarding, keep-alive, identity file) is a plain managed file, not a template: nothing in it varies per machine.

### asdf

- Homebrew asdf (0.16 line, Go). Plugins nodejs and python, global versions pinned in the managed `~/.tool-versions`, legacy version files enabled. A change-triggered script adds plugins and installs the pinned versions; it never runs `asdf set`, because the versions file is managed and would drift. The stray `~/.nvmrc` in the home folder is removed in the migration so the tool-versions file is the only global source.
- Migration on the current Mac removes the sourcing of the git-clone install; the data directory with installed versions is kept and reused.

### Claude Code

- The CLI is installed with Anthropic's native installer (`curl -fsSL https://claude.ai/install.sh | bash`, downloaded to a file and checked first), on every Mac, managed or not: it is a command-line tool, not a desktop app, and the managed Mac needs it as much as the personal one. The installer keeps its versions under `~/.local/share/claude` and links the current one at `~/.local/bin/claude`.
- The script is guarded on `claude` being on PATH or that link existing, and does nothing when it is. The CLI updates itself, so nothing keeps it current and no version is pinned anywhere.
- Not the Homebrew cask: it lags behind the CLI's own releases, and casks are never installed on the managed Mac, so the Brewfile route would not reach the machine that needs it.
- Claude Code's configuration, skills and memory stay out of scope; this installs the binary only.

### Hammerspoon

- `~/.hammerspoon` is managed directly by chezmoi as plain files: `init.lua`, `windows.lua` (the Ctrl+S window-layout modal), and `status-message.lua` (on-screen overlay). No symlink, no installer, no Lua toolchain, no tests: the keyboard repo's space-fn engine, spec suite, Makefile, luarocks tree, lefthook, stylua and EmmyLua stubs are not carried over and remain in the archived repo.
- `init.lua` is trimmed to: install the `hs` command line into `~/.local`, reload hotkey, a single change watcher on the config folder, `require` of the windows module, ready alert. The symlink-following watcher and the EmmyLua spoon are dropped. The two lines in the windows module that pause and resume space-fn are removed.
- `~/.hammerspoon/Spoons` is never managed; Hammerspoon writes there at runtime.

### Karabiner

- The karabiner.ts source (one TypeScript file, package file, lockfile, a `.gitignore` for `node_modules`) lives in a dot-prefixed project directory inside the dotfiles repo, which chezmoi ignores without any rule. The Karabiner script runs on every apply, gated on Karabiner being installed and having created its config file (first launch), and keeps a hash of the source and lockfile in its marker: when the hash changed or no successful build is recorded, it puts the asdf shims on the path, runs `npm ci` and the build, which writes the rules into Karabiner's own config file, preserving Karabiner's other settings. A Karabiner installed after the first sync gets its rules on the next sync. The generated JSON is never in the repo because Karabiner rewrites it.
- The build targets Karabiner's "Default profile", which Karabiner creates on first launch, so no profile has to be created by hand. Karabiner still needs to have been launched once; the manual checklist says so.
- Dependencies are pinned in the lockfile rather than tracking `latest`. Tooling choice (karabiner.ts versus alternatives) is confirmed by the research recorded in the notes.
- The step is guarded on the Karabiner app being present.

### macOS defaults

One change-triggered script (a pure writer, so chezmoi's change trigger is correct here), plain POSIX sh using `$HOME`, that quits System Settings first, writes everything, runs the private `activateSettings -u` as the logged-in user so input settings apply without logout, then restarts Finder, Dock and SystemUIServer. Nested values that `defaults write` cannot express (the dictation hotkey entry, whose parameter exceeds a signed 64-bit integer) go through `defaults export`, an edit, and `defaults import` on that domain, the same route as the display module, so the preferences daemon never disagrees with the file. Values are the current Mac's:

- Keyboard: standard function keys on; Fn key alone does nothing; key repeat 2, initial repeat 15; press-and-hold off; full keyboard access; automatic capitalisation, smart dashes, period substitution and smart quotes off.
- Scrolling: natural scrolling off; swipe between pages off.
- Trackpad, written to the built-in and Bluetooth trackpad domains and the global and per-host copies: tap to click; two-finger secondary click; three-finger tap off; force click off with silent clicking and lightest firmness; pinch, rotate, smart zoom on; four-finger horizontal and vertical swipes; two-finger edge swipe for Notification Centre; five-finger pinch for Launchpad; three-finger drag off. Pointer speed 0.6875 for trackpad and mouse, applied best-effort, read back through hidutil, warning printed if unchanged.
- Screenshots: location Downloads, PNG, thumbnail off.
- Finder: new window target Downloads; column view as the global default, which Downloads overrides to list view through the `.DS_Store` record; extensions shown; status bar; folders first; no extension-change warning; no .DS_Store on network and USB volumes; internal drives hidden on the Desktop, external and removable shown; save and print panels expanded; save to disk rather than iCloud; Desktop icon view arranged by kind with the current icon size, grid spacing, text size and label position.
- Window manager: click wallpaper to show desktop only in Stage Manager; desktop items hidden; widgets hidden on the Desktop and left visible in Stage Manager; the Stage Manager strip never auto-hidden; tiled windows without margins; no Option-key tiling accelerator; an application's windows shown all at once rather than one at a time.
- Dock: autohide on with a 0.5 s delay; tile size 16; magnification on, large size 128; bottom; no recents; no launch animation; all four hot corners off.
- Wallpaper: the system solid black. The wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) records the provider, so the script first checks whether a solid colour choice is already set and skips the write; otherwise it sets every desktop to the black solid-colour image that ships with macOS through System Events, which prompts once for Automation consent on a fresh Mac and never again.
- Dictation: enabled, shortcut press Control twice, preferred languages en_US, fr_CH, de_CH. First activation consent and language model downloads are on the manual checklist.
- Power, via pmset with sudo: on adapter never sleep, display sleep 10 minutes; on battery display sleep 15 minutes, no dimming. sudo's ticket expires during the long package and asdf steps, so a full bootstrap asks for the password more than once; the README says so.
- Dropped from the old script: the Safari and Messages tweaks (need Full Disk Access, and the Do Not Track header is obsolete), quarantine disabling (a security setting and likely MDM policy), and the accessibility zoom keys (need Full Disk Access). Locale and language lists are not written.

### Dock allow-list

- dockutil from Homebrew. The script removes all persistent apps and re-adds the allow-list in order, then the Downloads folder in the others section as a stack, fan view, sorted by date added. Seed allow-list: Freeform, iPhone Mirroring, Numbers. Change-triggered, so the Dock is only rebuilt when the list changes.

### Downloads view writer

- A small Python module, run through `uv run --with ds_store` (uv is a core formula), ensures the Downloads record in the home folder's `.DS_Store` has view style list and a list-view blob with sort column Date Added descending and Date Added visible. It merges into an existing record, falls back to the captured blob when none exists, and writes nothing when already correct. It runs after `killall Finder` (closing all windows, so Finder's cache can't overwrite it) and is followed by a second Finder restart, both tolerant of Finder not running. Verified working on macOS 26.6 on both Macs.
- The record shape, from the prototype, is the decision: three entries on the `Downloads` key of the parent folder's store, `vstl` of type `type` with value `Nlsv`, `vSrn` of type `long` with value 1, and `lsvC` of type `blob` holding a binary plist with `sortColumn` `dateAdded`, `viewOptionsVersion` 1, and a `columns` list where each column has `identifier`, `visible`, `ascending`, `width`. Finder 26 reads `lsvC`; the legacy `lsvp` record is never written.
- AppleScript cannot do this: Finder's scripting dictionary has no Date Added column.

### iTerm2

- A dot-prefixed preferences folder inside the chezmoi source directory, so iTerm2 writes straight into the repo and chezmoi ignores it as a target. The iTerm2 script runs on every apply, gated on iTerm2 being installed (it may arrive later via Self Service on the managed Mac), and sets the custom-folder path (from the source directory variable), the load-from-folder flag, and both keys that make iTerm2 save changes back on quit without asking. Migration exports the current preferences into that folder. The old Ayu Dark colour file is kept there as reference.

### Display settings

- Auto-brightness is stored in root's CoreBrightness preferences as one `AutoBrightnessEnable` flag per display entry (confirmed on the personal Mac, where the two entries that carry the key have it false and two carry no key at all). The display script runs on every apply: `sudo -H defaults export` of that domain, set the flag to false on every display entry, `sudo -H defaults import` only if something changed, and only then restart the brightness daemon; read back; mark success or print the manual instruction. Never edit the plist file directly. Display identifiers differ per machine, so the script iterates the entries. Reading needs sudo, so one prompt per apply is accepted. It is a true no-op only where every entry already carries the flag as false; a keyless entry means auto-brightness is on, so the first apply on such a Mac writes the flag, imports once and restarts the daemon, and only the applies after that are no-ops.
- True Tone has no key in that file on the personal Mac, meaning it was never toggled and sits at Apple's default, on. The setup leaves it alone.
- The script never fails the apply.

### Manual-steps report

- The report runs on every apply and prints a checklist. Whatever it can compute live it computes: the managed-Mac missing-apps list comes from the data table and the current contents of Applications, not from an earlier run; markers cover only what can't be recomputed. Contents: admin password prompts explained; Privacy & Security approvals for Karabiner and Hammerspoon (Input Monitoring, Accessibility, driver extension); Azure DevOps ssh key paste; App Store sign-in on personal Macs; Self Service requests on managed Macs; first dictation activation; pointer speed and auto-brightness to verify; Karabiner first launch.

### README

The README is the operating manual and is written together with the repo. Sections, in order:

- Setup: the one-line bootstrap, what it asks (group flags), what it detects (managed), what it prompts for (admin password, gh browser login), and how long the Command Line Tools and Homebrew steps take.
- Re-sync: `chezmoi update`, `chezmoi diff` to preview, and `chezmoi state delete-bucket --bucket=entryState` to force the change-triggered writers when one skipped because the tool it needed was missing. `entryState` is the bucket chezmoi keys `run_onchange_` scripts in; `scriptState` is the run-once bucket, so deleting that one re-runs the Homebrew installer instead.
- Editing loop: edit a file in place, `chezmoi status` and `chezmoi diff` to see drift, `chezmoi re-add` to copy it back (or `chezmoi edit` to skip that step), commit and push from `chezmoi cd`, `chezmoi update` on the other Mac. `chezmoi merge` for conflicts.
- Two fish rules: settings go in `config.fish` or `conf.d`, never `set -U`, because universal variables are not synced; themes are the exception, changed by editing `conf.d/fish_frozen_theme.fish` and `chezmoi re-add`, because fish 4.8's `fish_config theme save` writes the colours to universal variables and they would stay on one machine.
- Template rule: which files are templates and why, and that those are edited on the repo side, never re-added.
- Adding a package: `brew install`, then add the line to the matching Brewfile block and commit; or add the line first and `chezmoi apply`. `brew bundle cleanup` as the periodic drift check.
- Adding a macOS setting: how to find a key (defaults diff before and after a change in System Settings, macos-defaults.com, nix-darwin modules), where to add it in the defaults script, and which process to restart.
- Managed Mac notes: what is skipped, how to override detection, how to read the missing-apps list.
- Manual checklist: the same list the final script prints.
- Layout: what lives where in the source directory, and the numbering of scripts.

### Migration of the current Mac

- One issue, run as a reviewed runbook. It starts with the repo: rename it on GitHub and move the local checkout to `~/repos/caillou/dotfiles`. Then the config, because this Mac stores `personal = false` in `~/.config/chezmoi/chezmoi.toml` and the template asks through `promptBoolOnce`, which a second `chezmoi init` does not ask again: hand-edit the file to `personal = true`, then `chezmoi init --source ~/repos/caillou/dotfiles` to regenerate it against the repo. Then the backup, before anything changes: `tmutil localsnapshot`, a `defaults export` of every domain the defaults script writes, since cfprefsd caches them and a tar of the plist files can be stale, and a tar of every target `chezmoi managed` lists plus all of `~/.config/fish`, since chezmoi keeps no backups.
- Then the work chezmoi cannot do: switch the iTerm2 non-ASCII font to the cask; set both iTerm2 profiles back to "Home directory" before exporting the prefs into the repo, because the export otherwise carries `/Users/caillou`; confirm the three Hammerspoon files and the Karabiner source in the repo match the live ones; `fisher self-uninstall` the fisher 3 on this Mac, whose presence makes script 20 skip the fisher 4 bootstrap and run a subcommand fisher 3 does not have; purge the dead universal variables and remove `~/.nvmrc`; remove the two Hammerspoon symlinks, `keyboard` and `EmmyLua.spoon`.
- Then apply in two steps: `chezmoi apply --exclude scripts`, open a new fish and check the abbreviations and `node --version`, the prompt staying bare until fisher 4 arrives with the scripts; then `chezmoi apply` for the scripts, which bootstraps fisher 4, restarts Finder, Dock and SystemUIServer, asks once for Automation consent for System Settings, and imports the display flag once because two display entries carry no `AutoBrightnessEnable` key. Apply once more; that run has to be a no-op, with an empty `chezmoi diff` and no display import. Then confirm node and python still resolve now that asdf comes from Homebrew, and archive `caillou/keyboard` and `caillou/karabiner.ts` on GitHub with a README pointer before removing their local checkouts. The commands, in order, are in `issues/04. migrate this mac.md`.
- `chezmoi diff` previews files only, not script effects, which is why the apply is split. The repo files written by the earlier issues are the source of truth; nothing is adopted from the home directory.

### Ordering and idempotency

- Scripts carry explicit attributes: the Homebrew installer is the only `before` script, is guarded by `command -v brew` before it asks for sudo, and does not include the shared preamble (chezmoi keys run-once scripts by content, so a preamble edit would re-run it). Every other script is `after`, so all dotfiles are in place before scripts run. Pure writers (defaults, Dock, Downloads view) use chezmoi's change trigger; every other script runs on every apply and keeps its own hash and outcome in the state directory. Two-digit prefixes fix the order: 10 packages, 20 fish plugins, 21 login shell, 30 GitHub and ssh, 40 asdf, 45 Claude Code, 50 Karabiner build, 60 defaults, 61 Dock, 62 Downloads view, 63 iTerm2, 64 display, 90 report. The exact filenames are fixed in the skeleton issue. Hammerspoon files are applied with the other dotfiles and need no script.

## Testing Decisions

A good test checks observable behaviour through the module's interface and never its internals. For this repo that means: given machine facts, is the rendered output right; given a file, is the written record right; given stubbed commands, does a predicate answer correctly. Tests never install packages or write real preferences.

- The Downloads view writer gets Python unit tests against a temporary `.DS_Store`: writes the record, reads it back, asserts the three entries and the decoded sort column. This makes the earlier manual check permanent.
- The machine facts library gets bats tests with stubbed `profiles`, `ls` and `command`, covering managed and unmanaged, app present and absent, key set and unset.
- The Brewfile and the defaults script get template render tests: `chezmoi execute-template` with `--override-data` renders them for managed and unmanaged times personal on and off (embedded on and off), and the tests assert which blocks and entries appear. App presence is filtered in the packages script, not the template, so it is tested with bats and a stubbed Applications directory.
- Every shell script passes shellcheck. A GitHub Actions job on a macOS runner installs chezmoi, initialises from the checkout with fake config data, and runs a dry-run apply. Dry-run validates templates and file targets only; chezmoi does not execute scripts in dry-run. Script ordering is therefore asserted by a bats test over the script filenames and attributes, and script content by rendering each script with `chezmoi execute-template` and checking the expected commands.
- Prior art: the archived keyboard repo's busted suite and lefthook config are the model for "tests plus pre-commit lint" in a personal repo. The Lua files themselves are not unit-tested in dotfiles; the window-layout modal is verified by use.
- The repo carries a secrets check in its test suite: no gh `hosts.yml`, no private key material, no token-shaped strings anywhere in the source directory.
- Not tested automatically: the effect of defaults writes, the Homebrew install, and the Dock rebuild. Those are verified by hand on the new Mac after the first bootstrap, and the pointer-speed persistence across a reboot is checked then.

## Out of Scope

- Claude Code configuration, skills, agents and memory; the CLI binary itself is installed by the bootstrap. Memory folders are named after absolute project paths that include the username, so they cannot sync between these two Macs. Claude config gets its own, probably private, repo later.
- VS Code, which already uses Settings Sync.
- Syncing project repositories.
- Secrets management. The repo holds none; ssh keys are per machine; Bitwarden is personal-Mac only and not wired in.
- Installing desktop apps on the managed Mac, and anything MDM policy forbids.
- Granting privacy permissions; macOS never lets a script do this.
- Locale, language and region settings, login items, Safari and Messages preferences.
- Intel Macs and Linux. Homebrew paths assume Apple Silicon.
- Automated package cleanup.
- Space-fn and the Lua test suite; both remain in the archived keyboard repo.
- True Tone; left at its default.

## Further Notes

- The fully fresh path, a Mac with no Command Line Tools at all, is not exercised before the first real bootstrap: the new Mac already has the tools. The Homebrew installer's headless tools install is documented behaviour, not something we verified.
- The old defaults script from 2023 is the seed for the defaults module; most of its keys are still valid on macOS 26.6 and were confirmed against the current Mac.
- A live test during research briefly changed and then restored the trackpad, mouse and double-click keys on the current Mac; the final state was verified identical to the original.
- The pointer speed keys were reported broken on macOS 26.1 because System Settings stopped writing them. Writing them still takes effect when followed by `activateSettings -u`, verified on 26.6.2, but whether the settings slider reflects the value and whether it survives a reboot is unverified.
- Candidates for later: locale settings, LinearMouse for external mice, mise as an asdf replacement, Bitwarden-backed secrets on the personal Mac, a private Claude config repo, Hammerspoon-driven setup helpers (dropped from this PRD: the wallpaper no longer needs them and the `hs` command's auto-launch flag does the opposite of what was first assumed).
- Useful references for new defaults keys: macos-defaults.com and the nix-darwin defaults modules, both actively maintained in 2026. The mathiasbynens script is unmaintained since 2020 and serves as a catalogue only.
