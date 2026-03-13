package com.kuackmedia.androidauto.utils

import androidx.core.content.FileProvider

/**
 * Empty FileProvider subclass to avoid conflict with Cordova's core FileProvider.
 * Each plugin that declares a <provider> must use a unique android:name class.
 */
class AutoFileProvider : FileProvider()
