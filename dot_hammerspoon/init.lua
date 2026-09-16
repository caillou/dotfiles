-- Install the `hs` CLI tool into ~/.local — XDG path, no sudo needed. Lets the
-- config be reloaded/inspected from a terminal: `hs -c "hs.reload()"`.
-- cliInstall refuses to repair a half-installed state: if
-- `hs.ipc.cliStatus(os.getenv('HOME') .. '/.local')` returns false even though
-- `hs -c "1+1"` works, run `hs.ipc.cliUninstall(...)` then reload — do not just
-- re-run cliInstall.
require("hs.ipc")
hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")

-- Hammerspoon lives in the Dock, not the menu bar. Both calls write the
-- preference behind the settings checkboxes, so the window agrees, and both
-- are no-ops once the state is set. Without the menu: Shift+Ctrl+backtick
-- reloads, `hs -c "hs.openConsole()"` or a click on the dock icon opens the
-- console.
hs.dockIcon(true)
hs.menuIcon(false)

-- Use Shift+Control+` to reload Hammerspoon config
hs.hotkey.bind({ "shift", "ctrl" }, "`", nil, function()
  hs.reload()
end)

-- Auto-reload when any .lua file changes. chezmoi writes these files in place,
-- so one watcher on the config folder is enough: there is no symlink for
-- FSEvents to refuse to follow. ~/.hammerspoon/Spoons is below the watched
-- folder but unmanaged -- Hammerspoon writes there itself, and nothing here
-- loads a Spoon, so it stays quiet.
local function reloadOnLua(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end

-- global on purpose: local would be GC'd and stop the watcher
configWatcher = hs.pathwatcher.new(hs.configdir, reloadOnLua):start()

require("windows")

-- hs.alert draws its own on-screen overlay rather than going through macOS
-- Notification Center, which silently drops notifications sent during config
-- load. (hs.notify delivers fine for standalone sends, just not at load time.)
hs.alert.show("Ready to rock 🤘")
