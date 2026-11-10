# Vertical Clips Feed

## Request and scope

The user corrected the card-based video page: make it look and behave like a short-video feed. This supersedes the cover-card presentation approved earlier. The implementation uses the existing native SwiftUI app, private approved Supabase feed, real covers and local MP4 playback. No server, login, payment or publication change is needed.

## Presentation and behavior

- Home opens directly into one full-height video, with vertical snapping between clips. Remove the introduction and card list.
- Use a black canvas, compact For You header, persistent five-tab navigation, a game/title overlay and working sound and Source & credits controls. No fabricated engagement counts or unavailable social buttons.
- Autoplay and loop only the current page. Tap to pause/resume. Swipe, leave Home, background, logout, or open credits stops playback. On return the selected clip can be prepared again.
- Real cover frames are visible while the current video downloads/prepares. Existing landscape clips retain their aspect ratio rather than cropping away gameplay to fill a portrait screen.
- Full creator/source/license/modification text is readable in a credits sheet; retain attribution without covering the video in a long card.
- Empty, network error, media error and retry states remain truthful. Refresh the real feed through a header action; preserve valid selection on refresh.

## Approach

The existing feed will use iOS17 SwiftUI vertical paging and selected-page activation. A dedicated native AVPlayerLayer surface avoids the detail player's embedded transport chrome. Reuse ClipPlaybackModel's private download and protected per-presentation file lifecycle. The previous card-to-sheet player remains available in source but no longer is Home's primary route. A horizontal PageTabView rotated into portrait was rejected because it complicates accessibility and page sizing; a separate UIKit feed controller is unnecessary for three existing short clips.

The concrete control placement, initially muted autoplay and aspect-fit landscape video are implementation choices communicated with this update, not previously confirmed product rules.

## Verification boundary

No build, type checking, XCTest execution, app/simulator launch, dependency resolution, commit or push. Regenerate project membership, parse Swift grammar in all existing configurations, review async/page/session cleanup and provide user-run Xcode steps. Native layout and playback remain unverified until that run.
