package com.example.broker_wallet

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a homogeneous batch of two or more photos, or of two or more videos, to
 * the Android share sheet as ONE `ACTION_SEND_MULTIPLE` request.
 *
 * This is only the last step of a share. Flutter has already chosen the files,
 * fetched the private ones through the authenticated path, written them as local
 * files with their real names and proven types, split a mixed choice into its
 * photos and its videos, and put the message on the clipboard. What arrives here
 * is those local paths and one type per path, in the order the person chose
 * them. It never gets a link, an identifier or a key, a message, or a mix of
 * photos and videos, and it decides nothing about what is shared.
 *
 * The request carries:
 *  - every file as a `content://` URI from [BrokerWalletShareFileProvider], in
 *    `EXTRA_STREAM`, in the order given;
 *  - the same URIs in the intent's `ClipData`, one item per file and in the same
 *    order, with a `ClipDescription` that lists the distinct real types, plus
 *    `FLAG_GRANT_READ_URI_PERMISSION`, so the receiving app is granted every
 *    attachment (a chooser copies both onto the intent it launches);
 *  - the declared type from [MultiMediaShareFormat.commonMimeType]: the exact type
 *    when all are the same, the wildcard of their one family otherwise. Never a
 *    mix, never a family the files are not;
 *  - no message. A receiving app may repeat a message that travels with several
 *    files, drop it, or refuse the share; the details are on the clipboard.
 *
 * Starting the chooser is the whole outcome; what a receiving app does with the
 * files is the receiver's choice.
 */
class MultiMediaSharePlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        /** The channel Dart calls. The same name is in `share_android_sink.dart`. */
        const val CHANNEL = "com.example.broker_wallet/multi_media_share"

        const val METHOD_SHARE = "shareMultipleMedia"

        /**
         * The folder of the app's cache that shares are prepared in, one folder
         * per share. The same name is in `share_live.dart` and in
         * `res/xml/brokerwallet_share_paths.xml`; only files under it are shared.
         */
        const val STAGING_FOLDER = "broker_wallet_share"

        /** Appended to the application id: the same authority as the manifest. */
        const val PROVIDER_SUFFIX = ".brokerwallet.shareprovider"

        fun registerWith(flutterEngine: FlutterEngine, activity: Activity) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(MultiMediaSharePlugin(activity))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_SHARE) {
            result.notImplemented()
            return
        }
        val paths = call.argument<List<String>>("paths")
        val mimeTypes = call.argument<List<String>>("mimeTypes")
        try {
            share(paths, mimeTypes)
            result.success(null)
        } catch (e: IllegalArgumentException) {
            // Fixed words only: never a path, a name or a message.
            result.error("invalid-request", "The media batch could not be shared.", null)
        } catch (e: Exception) {
            result.error("share-failed", "The share sheet could not be opened.", null)
        }
    }

    private fun share(paths: List<String>?, mimeTypes: List<String>?) {
        require(paths != null && mimeTypes != null) { "files and types are required" }
        require(paths.size >= 2) { "a batch has two files or more" }
        require(paths.size == mimeTypes.size) { "every file has one type" }
        require(mimeTypes.none { it.isBlank() }) { "every type is known" }

        val root = File(activity.cacheDir, STAGING_FOLDER).canonicalFile
        val authority = activity.packageName + PROVIDER_SUFFIX
        val uris = ArrayList<Uri>(paths.size)
        for (path in paths) {
            val file = File(path).canonicalFile
            require(file.path.startsWith(root.path + File.separator)) {
                "only prepared share files are shared"
            }
            require(file.isFile && file.canRead()) { "every file can be read" }
            uris.add(FileProvider.getUriForFile(activity, authority, file))
        }

        val intent = buildSendIntent(uris, mimeTypes)
        activity.startActivity(Intent.createChooser(intent, null))
    }

    /** The one `ACTION_SEND_MULTIPLE` request for [uris], in the order given. */
    internal fun buildSendIntent(uris: List<Uri>, mimeTypes: List<String>): Intent {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
        intent.type = MultiMediaShareFormat.commonMimeType(mimeTypes)
        intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        intent.clipData = clipDataFor(uris, mimeTypes)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return intent
    }

    /**
     * Every URI as an item of one `ClipData`, in order. The description lists the
     * distinct real types itself, because items added without a resolver do not
     * update it.
     */
    @Suppress("DEPRECATION")
    private fun clipDataFor(uris: List<Uri>, mimeTypes: List<String>): ClipData {
        val description = ClipDescription(
            "Broker Wallet media",
            MultiMediaShareFormat.distinctMimeTypes(mimeTypes).toTypedArray(),
        )
        val clip = ClipData(description, ClipData.Item(uris.first()))
        for (uri in uris.drop(1)) {
            clip.addItem(ClipData.Item(uri))
        }
        return clip
    }
}
