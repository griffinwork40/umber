# Recursive Splits (Quarters) + Window Chooser

## Status: In Progress

Two features for Umber:
1. **Recursive splits** -- split an already-split pane to get 4 panes (quarters)
2. **Window chooser** -- tmux ctrl-b w equivalent for navigating Spaces and documents

## Approach

### Feature 1: Quarters via Nested SplitContainerView

**Key insight:** `SplitContainerView` already accepts any `NSView` as its child --
including another `SplitContainerView`. Nesting is compositionally free. Each container
stays at exactly 2 children with its own divider. No new tree data structure needed.

**How it works:**
- When the user splits a pane that's already inside a split, the focused pane's slot
  in its parent `SplitContainerView` gets replaced by a NEW `SplitContainerView` that
  holds the original pane + the new peer.
- The outer container doesn't know or care that its child is itself a split container.
- Divider drag, layout, and cursor rects all compose naturally because each level is
  independent.
- Depth limit: 2 levels (max 4 panes per tab). Enforced by a depth check, not a guard.

**Model change:**
- `splitPeers` dict value type changes from `(document, direction)` to include an
  optional sub-split: `(document, direction, subSplit: (document, container, direction)?)`
- Still keyed by primary document identity. Still flat -- no recursion in the data model.
- Or: a small `SplitEntry` struct that tracks the peer document, direction, the nested
  container (if any), and any sub-peer document.

**Teardown:** Three sequential loops (sub-peers, then peers, then primaries). Same
pattern as today's two-phase teardown. No recursion.

**Focus movement:** Extended from 2-case binary toggle to 4-case explicit mapping.
Each direction (H/J/K/L) resolves which of the 4 panes to focus by checking which
split level the current focus is in and which direction was requested.

### Feature 2: Window Chooser via CommandPalette

All three adversarial critics converged: reuse the existing CommandPalette infrastructure.

- Add Space-switching commands dynamically from `SpaceWindowController.open` registry
- Fuzzy search comes free from the palette's existing filtering
- Wire ⌘⇧A to open the palette pre-filtered to space/tab navigation
- tmux ctrl-b w is itself a plain text list -- the palette matches that UX

### Files Changed

| File | Change |
|------|--------|
| `SpaceViewController+Splits.swift` (272) | Major: drop guard !hasSplit, add sub-split creation, extend focus to 4 panes, nested container swap |
| `SpaceViewController+Closing.swift` (71) | Update: closeSplitPane handles sub-splits, three-phase teardown |
| `SpaceViewController.swift` (354) | Minimal: splitPeers value type widened, selectDocument handles nested splits |
| `SplitContainerView.swift` (323) | Add replaceChild method for swapping a leaf with a nested container |
| `ShellHosting.swift` (239) | Update focusedShellHost for 4-pane first-responder walk |
| `DocumentAreaViewController.swift` (168) | Handle nested container presentation |
| `AppMenu.swift` (326) | Split items: enable when depth < 2. Add ⌘⇧A for window chooser |
| `CommandPalette+Commands.swift` (65) | Add dynamic Space/tab switching commands |
| `AppDelegate.swift` or `AppDelegate+EditorActions.swift` | Add selectSpace/selectTab actions |

### Risks

1. **SpaceViewController.swift at 354 LOC** -- no new stored properties, just tuple
   type widening. Must extract something to get back under ceiling.
2. **Nested divider drag** -- each SplitContainerView handles its own divider
   independently. Manual testing needed to confirm outer divider doesn't capture
   inner drag events (hit-test should resolve this since inner container is deeper).
3. **Dimming with 4 panes** -- must dim 3 unfocused panes. The nested container's
   `setFocusedChild` only knows about its 2 children; the outer container's dimming
   applies to the whole nested container (correct: dimming the outer slot dims all
   inner panes via alphaValue propagation through the layer tree).
4. **Click callback lifetime** -- `didReceiveClickInChild` must be set on both the
   outer and inner containers, and cleared correctly during teardown.

### Alternatives Considered (Devils Advocate)

1. **PaneNode indirect enum tree** (original proposal) -- rejected due to impedance
   mismatch with SplitContainerView's 2-slot API, SpaceViewController.swift ceiling
   violation, and unspecified spatial tree walk.
2. **Flat TilingLayout enum** (architect) -- rejected because SplitContainerView would
   need 4-child layout, multiplying divider/drag/cursor logic. Nesting existing
   2-child containers is simpler.
3. **Second splitPeers dict** (paranoid) -- rejected because it only covers 1+1+2
   layout, not true 2x2 quarters.
4. **Dedicated WindowChooserPanel** (original F2) -- rejected unanimously by all
   critics. CommandPalette reuse is cheaper, proven, and matches tmux's actual UX.
