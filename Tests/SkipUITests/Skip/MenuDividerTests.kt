// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
package skip.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Dividers have no semantics node, so the menus are compared by height. */
@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class MenuDividerTests {
    @get:org.junit.Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Test fun onlyDividersBetweenItemsAreDrawn() {
        fun item(): Renderable = Button(title = "Item", action = {})
        val menus = listOf(
            listOf(Divider(), item(), Divider(), Divider(), item(), Divider()),
            listOf(item(), Divider(), item()),
            listOf(item(), item()),
        )
        val heights = IntArray(menus.size)
        rule.setContent {
            menus.forEachIndexed { index, menu ->
                Column(Modifier.onGloballyPositioned { heights[index] = it.size.height }) {
                    Menu.RenderDropdownMenuItems(for_ = menu, context = ComposeContext(), replaceMenu = {})
                }
            }
        }
        rule.runOnIdle {
            assertTrue("A divider between items must draw", heights[1] > heights[2])
            assertEquals("Leading, trailing and repeated dividers must not draw", heights[1], heights[0])
        }
    }
}
