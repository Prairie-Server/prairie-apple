# tvOS Focus Guidance

This note documents the focus rules we want future tvOS navigation work to
follow in the Prairie Apple client. The short version: every interactive zone
needs exactly one focus owner. Let the tvOS focus engine own movement through a
stable graph of focusable controls, or build one custom focusable composite
control. Do not mix the two models.

## Focus Models

Use one of these patterns for a given control.

### Native Focus Graph

Use this for ordinary rows, grids, button groups, sheets, and menus where each
actionable item can be a real focus target.

- Render stable `Button`, `NavigationLink`, or `.focusable(true)` items.
- Group related movement with `.focusSection()` and `.focusScope(...)`.
- Use `@FocusState`, `prefersDefaultFocus`, `defaultFocus`, or `resetFocus` to
  seed or restore focus, not to fight the focus engine on every move.
- Keep the focused subtree mounted and structurally stable while moving focus.
- Attach `onMoveCommand` only at intentional boundaries, such as "Up from the
  first card returns to the top menu." Do not intercept normal in-zone movement.
- Move focus geometry with layout (`padding`, `frame`, alignment), not
  `.offset`, because tvOS resolves focus from layout frames.

Good local examples:

- `TVCatalogGrid`
- `TVLibraryCollectionsView`
- `TVForYouDropdown`
- `TVProfileDropdown`

### Composite Focus Control

Use this when the visual control is one logical selector even though it renders
multiple highlighted rows or columns. A cascading selector is the main example.

- Make one container the real focus target with `.focusable(true)` and a single
  `@FocusState`.
- Render rows as passive labels; do not make them `Button`s and do not attach
  per-row `.focused(...)` bindings.
- Store the highlighted row/column in ordinary `@State`.
- Handle all D-pad movement for the composite with one `onMoveCommand`.
- Commit the highlighted selection on Select, usually with `onTapGesture` on
  the focused container.
- Add useful accessibility labels and button/selected traits to the composite
  or its rendered labels so VoiceOver still describes the action.

Good local example:

- `TVCascadeSelector`

## Do Not Mix Models

The broken pattern is a hybrid control:

- row `Button`s participate in native focus,
- the same rows also use `@FocusState`,
- a parent or window-level handler manually changes that focus in response to
  directional presses.

That gives the same physical remote press to multiple owners. The symptom is a
single D-pad press producing multiple focus writes, such as:

```text
cascade.move/right library(1)
cascade.focus -> section(1, recommended)
cascade.focus -> section(1, browse)
cascade.focus -> nil
bar.focusedItem -> Calendar
```

When this happens, stop adding press interceptors. Decide which focus model the
control should use, then remove the other one.

## Top Menu Ownership

The top menu has three conceptual states:

- `closed`: no panel is visible; focus belongs to content or the bar.
- `preview`: a dwell-open panel is visible, but the bar still owns focus and
  the panel is passive.
- `entered`: the user pressed Down or otherwise entered the panel; the panel
  owns focus and the bar is inert until the panel closes.

Implementation details may use booleans, but the state machine above is the
contract. In entered mode, it should be impossible for the bar to accept focus
on another tab behind the panel. Treat `panelHasFocus` as telemetry from the
child panel, not as the source of truth for ownership. The durable ownership
signal is the host's "entered panel" state.

When closing a panel, choose the next owner explicitly:

- Menu/Back closes and returns focus to the panel's bar anchor.
- Down past the last row closes and hands focus to page content.
- Selecting a panel row closes, updates route/scope state, and then hands focus
  to the destination content.

## Debugging Checklist

When tvOS focus feels random, capture logs for the ownership boundary first:

- current focused top-bar item
- open panel
- whether the panel is in preview or entered mode
- whether the panel reports focus
- the panel's internal highlighted item
- every `onMoveCommand` direction handled by the active owner

Expected cascade movement after entering a Movies panel looks like this:

```text
host.enterOpenPanel openPanel=Movies
cascade.panelFocused -> true selection=library(1)
cascade.move direction=right focus=library(1)
cascade.focus -> section(1, recommended)
cascade.move direction=down focus=section(1, recommended)
cascade.focus -> section(1, collections)
```

Unexpected signs:

- the bar logs a different focused tab while a panel is entered,
- a single D-pad press produces multiple panel focus writes,
- panel focus becomes `nil` without an explicit close or content handoff,
- `onMoveCommand` is attached broadly and also expected to pass native movement
  through the same zone.

## References

- Apple tvOS focus engine and remote guidance:
  https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/WorkingwiththeAppleTVRemote.html
- SwiftUI `focusSection()`:
  https://developer.apple.com/documentation/swiftui/view/focussection%28%29
