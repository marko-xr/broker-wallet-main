package com.example.broker_wallet

import androidx.core.content.FileProvider

/**
 * Serves the files of a media share to the app the person picks in the share
 * sheet, as `content://` URIs with a temporary read grant.
 *
 * It is a subclass of its own so its manifest entry cannot collide with the
 * app's other `androidx.core.content.FileProvider`. Its paths file
 * (`res/xml/brokerwallet_share_paths.xml`) exposes one folder only: the share
 * staging folder inside the app's cache, where each share prepares its files in
 * a folder of its own. Nothing else the app stores is reachable through it.
 */
class BrokerWalletShareFileProvider : FileProvider()
