// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
package skip.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Assert.assertEquals
import org.junit.Test

@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class ToolbarItemsTests {
    @get:org.junit.Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Test fun primaryActionStaysTrailingMost() {
        val primary = ToolbarItem(placement = ToolbarItemPlacement.primaryAction, content = { EmptyView() })
        val automatic = ToolbarItem(content = { EmptyView() })
        var placements: kotlin.collections.List<ToolbarItemPlacement> = listOf()
        rule.setContent {
            val (_, _, trailing, _) = ToolbarItems(content = skip.lib.arrayOf<View>(primary, automatic)).Evaluate(context = ComposeContext())
            placements = trailing.map { (it as ToolbarItem).placement }
        }
        rule.runOnIdle {
            assertEquals(listOf(ToolbarItemPlacement.automatic, ToolbarItemPlacement.primaryAction), placements)
        }
    }

    @Test fun flexibleSpacerIsFixedInTopBar() {
        val spacer = ToolbarSpacer()
        var sizings: kotlin.collections.List<SpacerSizing> = listOf()
        rule.setContent {
            val (_, _, trailing, _) = ToolbarItems(content = skip.lib.arrayOf<View>(spacer)).Evaluate(context = ComposeContext())
            sizings = trailing.map { (it as ToolbarSpacer).sizing }
        }
        rule.runOnIdle {
            assertEquals(listOf(SpacerSizing.fixed), sizings)
        }
    }

    @Test fun principalReplacesTitle() {
        val principal = ToolbarItem(placement = ToolbarItemPlacement.principal, content = { EmptyView() })
        var leadingCount = -1
        var hasPrincipal = false
        rule.setContent {
            val (_, leading, _, _, principalItem) = ToolbarItems(content = skip.lib.arrayOf<View>(principal)).Evaluate(context = ComposeContext())
            leadingCount = leading.size
            hasPrincipal = principalItem != null
        }
        rule.runOnIdle {
            assertEquals(0, leadingCount)
            assertEquals(true, hasPrincipal)
        }
    }
}
