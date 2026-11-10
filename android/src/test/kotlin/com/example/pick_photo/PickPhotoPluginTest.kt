package com.example.pick_photo

import kotlin.test.Test
import kotlin.test.assertNotNull

internal class PickPhotoPluginTest {
    @Test
    fun onPluginInstantiated_isNotNull() {
        val plugin = PickPhotoPlugin()
        assertNotNull(plugin)
    }
}
