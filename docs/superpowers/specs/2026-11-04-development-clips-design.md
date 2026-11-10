# Licensed Development Clips

The user requested a few online gaming videos in FL-Tiya and confirmed multiple games are acceptable. Import three explicitly reusable clips with visible creator/source/license attribution. Existing development accounts see real hosted media; production users remain isolated by the existing cohort rules. Do not assume a public trailer permits redistribution.

Use existing video_posts, private.video_reviews and the private clips bucket. Create pending records, upload immutable objects, verify downloaded bytes/content/provenance, then record trusted review and approve in one server transaction. Keep detailed hashes and source information in a content manifest, with concise attribution in the existing caption. A public bucket or signed URL would weaken the current access contract and is unnecessary.

Replace the For You / Clips empty state with an explicitly approved feed, loading/error/refresh, and tap-to-open native AVKit playback. Authenticated SDK download writes only a bounded per-account/per-presentation temporary file, paused and removed on close/logout. Following/Highlights and user uploads retain their existing unavailable states. No invented likes, comments or engagement counts.

Native SwiftUI, Swift 5 and iOS 17+ remain unchanged. No native build/typecheck/XCTest/app/simulator launch, new dependency, paid resource, commit/push or app publication. Live HTTP/media verification is within the requested import scope. Native rendering/playback remains for the user to verify in Xcode.
