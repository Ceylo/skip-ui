// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
package skip.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.dp
import kotlin.collections.List

/**
 * The node a `GeometryReader` is laid out as, around the `BoxWithConstraints` that composes its
 * content. That box is a `SubcomposeLayout`, which throws when asked for its intrinsic size, and
 * SkipUI does ask: `ComposeFlexibleContainer` measures `height(IntrinsicSize.Max)` inside a
 * scroll, and so does `ViewThatFits`. This node answers instead, without measuring the content:
 * a SwiftUI `GeometryReader` has no ideal size of its own, and reports 10×10 pt when unconstrained.
 */
@Composable
fun GeometryReaderLayout(modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content = content, modifier = modifier, measurePolicy = GeometryReaderMeasurePolicy)
}

private object GeometryReaderMeasurePolicy : MeasurePolicy {
    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): MeasureResult {
        val placeables = measurables.map { it.measure(constraints) }
        val width = constraints.constrainWidth(placeables.maxOfOrNull { it.width } ?: 0)
        val height = constraints.constrainHeight(placeables.maxOfOrNull { it.height } ?: 0)
        return layout(width, height) {
            placeables.forEach { it.place(0, 0) }
        }
    }

    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int = idealSize()
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int = idealSize()
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int = idealSize()
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int = idealSize()

    private fun IntrinsicMeasureScope.idealSize(): Int = 10.dp.roundToPx()
}
