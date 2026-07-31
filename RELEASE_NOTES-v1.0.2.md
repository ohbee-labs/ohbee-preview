# Ohbee Preview 1.0.2

Ohbee Preview 1.0.2 is a focused viewport-correctness patch. It introduces no
new browsing or management features.

## Fixed

- Replacement images remain centered after Previous and Next navigation.
- Fit-to-Window centering is revalidated after later SwiftUI and AppKit layout
  callbacks, including window-size changes.
- Scroll and magnification geometry from the previous image cannot affect a
  newly committed image generation.

The purpose-designed small application icon introduced in v1.0.1 remains
included without modification.

## Manual release validation

Use a folder containing small and large landscape images, a portrait image, and
substantially different aspect ratios. Navigate repeatedly in both directions,
then repeat after resizing, zooming, panning, rotating, entering fullscreen, and
leaving fullscreen. Every Fit-mode replacement should remain centered on both
axes.

## Distribution note

This artifact uses the existing ad-hoc signing mode for local evaluation. It is
not Developer ID signed, notarized, or distributed through the Mac App Store.
