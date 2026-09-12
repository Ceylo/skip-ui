// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
package skip.ui

import androidx.compose.animation.core.AnimationVector
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.TwoWayConverter
import androidx.compose.animation.core.VectorizedFiniteAnimationSpec

/**
 * [animation] held at its initial value for [delayMillis] first. Compose's own delays live on
 * `TweenSpec` and `StartOffset`, neither of which a `SpringSpec` has, so `Animation.delay(_:)`
 * wraps a spring in this instead.
 */
class DelayedAnimationSpec<T>(val delayMillis: Int, val animation: FiniteAnimationSpec<T>) : FiniteAnimationSpec<T> {
    override fun <V : AnimationVector> vectorize(converter: TwoWayConverter<T, V>): VectorizedFiniteAnimationSpec<V> =
        VectorizedDelayedAnimationSpec(delayMillis * 1_000_000L, animation.vectorize(converter))

    override fun equals(other: Any?): Boolean =
        other is DelayedAnimationSpec<*> && other.delayMillis == delayMillis && other.animation == animation

    override fun hashCode(): Int = 31 * delayMillis + animation.hashCode()
}

private class VectorizedDelayedAnimationSpec<V : AnimationVector>(
    private val delayNanos: Long,
    private val animation: VectorizedFiniteAnimationSpec<V>
) : VectorizedFiniteAnimationSpec<V> {
    override fun getValueFromNanos(playTimeNanos: Long, initialValue: V, targetValue: V, initialVelocity: V): V =
        if (playTimeNanos < delayNanos) initialValue
        else animation.getValueFromNanos(playTimeNanos - delayNanos, initialValue, targetValue, initialVelocity)

    override fun getVelocityFromNanos(playTimeNanos: Long, initialValue: V, targetValue: V, initialVelocity: V): V =
        if (playTimeNanos < delayNanos) initialVelocity
        else animation.getVelocityFromNanos(playTimeNanos - delayNanos, initialValue, targetValue, initialVelocity)

    override fun getDurationNanos(initialValue: V, targetValue: V, initialVelocity: V): Long =
        delayNanos + animation.getDurationNanos(initialValue, targetValue, initialVelocity)
}
