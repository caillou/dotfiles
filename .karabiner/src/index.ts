import {
  ifApp,
  ifVar,
  map,
  ModifierParam,
  rule,
  ToKeyParam,
  withModifier,
  writeToProfile,
} from 'karabiner.ts'

type Shortcut = [ToKeyParam, ModifierParam?]

const macTabs = {
  prevTab: ['[', ['left_command', 'left_shift']] as Shortcut,
  nextTab: [']', ['left_command', 'left_shift']] as Shortcut,
}

// `to` output is not re-remapped, so these reach Windows as Ctrl(+Shift)+Tab.
const windowsTabs = {
  prevTab: ['tab', ['left_control', 'left_shift']] as Shortcut,
  nextTab: ['tab', 'left_control'] as Shortcut,
}

const navKeys = (
  modifier: ModifierParam,
  { prevTab, nextTab }: { prevTab: Shortcut; nextTab: Shortcut },
) =>
  withModifier(
    modifier,
    'any',
  )([
    map('j').to('left_arrow'),
    map('k').to('down_arrow'),
    map('l').to('right_arrow'),
    map('i').to('up_arrow'),
    map('h').to('delete_or_backspace'),
    map('u').to(...prevTab),
    map('o').to(...nextTab),
    map('v').to('v', ['left_control', 'left_option']),
  ])

// Microsoft Remote Desktop and Jump Desktop; Karabiner ORs the array.
const ifRemoteDesktop = ifApp([
  '^com\\.microsoft\\.rdc\\.macos$',
  '^com\\.p5sys\\.jump\\.mac\\.',
])

const ifCaps = ifVar('caps-ctrl')

// A caps_lock sent from to_if_alone has to be held, see the first rule below.
// 200 ms is the value in Karabiner's to_if_alone documentation.
const capsLockTap = { hold_down_milliseconds: 200 }

writeToProfile('Default profile', [
  rule('Right ⌘ layer', ifRemoteDesktop.unless()).manipulators([
    navKeys({ right: '⌘' }, macTabs),
  ]),
  rule('Right ⌥ layer').manipulators([
    withModifier('right_option')([
      map('v').to('v', ['left_control', 'left_option']),
    ]),
  ]),
  rule('CAPS_LOCK to esc/control', ifRemoteDesktop.unless()).manipulators([
    // ⇧ + caps held is ⇧⌃; tapped alone it is the real caps lock. It comes
    // first so ⇧ does not fall into the `any` catch-all. Karabiner lifts a
    // mandatory modifier for as long as the output is a modifier, so ⇧ is
    // held again explicitly. caps_lock is optional so the tap still matches
    // (and turns caps lock off) while caps lock is on. to_if_alone posts key
    // down and key up at the same instant, and macOS ignores a caps lock
    // press that short, so the key is held for the duration Karabiner's
    // docs recommend.
    map('caps_lock', 'shift', 'caps_lock')
      .to('left_control', 'left_shift')
      .toIfAlone('caps_lock', undefined, capsLockTap),
    map('caps_lock', null, 'any').to('left_control').toIfAlone('escape'),
  ]),

  rule('Remote Desktop', ifRemoteDesktop).manipulators([
    map('left_command', null, 'any').to('left_control'),
    map('right_command', null, 'any').to('right_control'),
    map('left_control', null, 'any').to('left_command'),
    map('4', ['left_control', 'left_shift']).to('4', [
      'left_command',
      'left_shift',
    ]),
    withModifier('left_control')([
      map('tab').to('tab', ['left_command']).condition(ifCaps.unless()),
    ]),
    // Plain ⌘q stays ⌘q: quits the client. ctrl+q for Windows is on caps+q,
    // and ⌘⇧q goes to Windows too instead of opening the macOS log-out dialog.
    map('q', 'left_control').condition(ifCaps.unless()).to('q', 'left_command'),
    // ⌘⇧k stays ⌘⇧k; ctrl+shift+k for Windows is on caps+⇧+k.
    map('k', ['left_control', 'shift'])
      .condition(ifCaps.unless())
      .to('k', ['left_command', 'left_shift']),
    // Command + Option + i opens dev tools.
    map('i', ['left_control', 'left_option']).to('i', [
      'left_shift',
      'left_control',
    ]),
    // Both ⌘ (= both ⌃ here) + j/l/i/k: layer output isn't re-manipulated,
    // so ⌃← from the layer would never hit the Home/End rules below.
    map('j', ['left_control', 'right_control'], 'any').to('home'),
    map('l', ['left_control', 'right_control'], 'any').to('end'),
    map('i', ['left_control', 'right_control'], 'any').to('home', 'left_control'),
    map('k', ['left_control', 'right_control'], 'any').to('end', 'left_control'),
    navKeys('right_control', windowsTabs),
    // Physical ⌘ is already control here, so ⌘← / ⌘→ become Home / End
    // (and ⇧⌘← / ⇧⌘→ select to them). Caps+← / caps+→ land here as well.
    map('left_arrow', 'control', 'any').to('home'),
    map('right_arrow', 'control', 'any').to('end'),
    // ⌘↑ / ⌘↓ are ⌃↑ / ⌃↓ here, which macOS grabs for Mission Control and
    // App Exposé before the client sees them. Ctrl+Home / Ctrl+End is the
    // Windows "start / end of file"; ⇧ passes through, so ⇧⌘↑ selects to it.
    map('up_arrow', 'control', 'any').to('home', 'left_control'),
    map('down_arrow', 'control', 'any').to('end', 'left_control'),
    // ⇧ + caps: held is ⇧⌃ (with the variable, like below), tapped alone is
    // the real caps lock; ⇧ held again, caps_lock optional and the tap held
    // as above.
    map('caps_lock', 'shift', 'caps_lock')
      .toVar('caps-ctrl', 1, 0)
      .to('left_control', 'left_shift')
      .toIfAlone('caps_lock', undefined, capsLockTap),
    // caps = ⌃ like on the mac, but it also sets a variable so a/e can
    // become home/end without swallowing ⌘a/⌘e (⌘ is ⌃ here as well).
    map('caps_lock', null, 'any')
      .toVar('caps-ctrl', 1, 0)
      .to('left_control')
      .toIfAlone('escape'),
    map('a', '⌃', 'any').condition(ifCaps).to('home'),
    map('e', '⌃', 'any').condition(ifCaps).to('end'),
  ]),

])

// Profile parameters (to_if_alone timeout and friends) go in the third
// argument of writeToProfile; the defaults are documented in karabiner.ts.
