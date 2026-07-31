# Ohbee Preview 1.0.1

Ohbee Preview 1.0.1 is a visual-quality patch for the stable MVP. It changes no
viewer features or behavior.

## Improved small-size application icon

- Added a purpose-designed simplified bee for 16×16, 32×32, and 64×64 icon
  representations.
- Made the bee the primary silhouette with stronger contrast and fewer colors.
- Removed the landscape frame and decorative details at small sizes.
- Preserved the established full Ohbee Preview artwork from 128×128 upward.

This fixes the application icon appearing as an indistinct multicolor shape in
Finder list views, Open With menus, and other compact macOS surfaces.

## Installation and icon-cache validation

1. Quit Ohbee Preview.
2. Remove the existing `/Applications/Ohbee Preview.app`.
3. Extract `Ohbee-Preview-1.0.1-macOS.zip` and copy **Ohbee Preview.app** into
   `/Applications`.
4. Confirm Finder reports version 1.0.1.
5. Check the icon in Applications, Finder list view, and Finder Open With.
6. Restart Finder if the old icon remains cached.
7. Log out and back in only if Finder still displays the old icon.

The application does not reset Launch Services or delete system icon caches.

## Distribution note

This artifact uses the existing ad-hoc signing mode for local evaluation. It is
not Developer ID signed, notarized, or distributed through the Mac App Store.
