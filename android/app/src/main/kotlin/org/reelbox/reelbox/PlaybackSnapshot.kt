package org.reelbox.reelbox

/** Decoder truth supplied by Dart, never inferred by a native timer/player. */
data class PlaybackSnapshot(
    val title: String = "Reelbox", val playing: Boolean = false,
    val positionMs: Long = 0, val durationMs: Long = 0
) {
    companion object {
        fun from(args: Map<*, *>, previous: PlaybackSnapshot = PlaybackSnapshot()): PlaybackSnapshot {
            val duration = ((args["durationMs"] as? Number)?.toLong() ?: previous.durationMs).coerceAtLeast(0)
            val position = ((args["positionMs"] as? Number)?.toLong() ?: previous.positionMs).coerceAtLeast(0)
            return PlaybackSnapshot(
                (args["title"] as? String ?: previous.title).take(512),
                args["playing"] as? Boolean ?: previous.playing,
                if (duration > 0) position.coerceAtMost(duration) else position,
                duration
            )
        }
    }
}
