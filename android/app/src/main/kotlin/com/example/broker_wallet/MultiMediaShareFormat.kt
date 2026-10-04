package com.example.broker_wallet

/**
 * The deterministic part of the native media-batch share: which MIME type an
 * `ACTION_SEND_MULTIPLE` intent declares for a batch, and which distinct types
 * its `ClipDescription` lists.
 *
 * Kotlin standard library only (no Android classes), so each rule can be read
 * and checked on its own. Nothing here knows a path, a link or a record.
 */
internal object MultiMediaShareFormat {

    /**
     * The type the intent declares for a batch of files that proved these types.
     *
     * Every type identical gives that exact type. Different types of one family
     * (several image formats, or several video formats) give `family/slash-star`.
     * Nothing else is a batch: files of two families, or a type that is not
     * shaped like `type/subtype`, are refused with an [IllegalArgumentException].
     * A batch is never declared as a family it is not, nor as all types: Flutter
     * hands over photos and videos as separate homogeneous batches, so a mix
     * reaching this point is a mistake, not something to be labelled to suit a
     * receiver.
     */
    fun commonMimeType(mimeTypes: List<String>): String {
        val types = normalized(mimeTypes)
        require(types.isNotEmpty()) { "a batch has types" }
        val first = types.first()
        if (types.all { it == first }) return first
        val families = types.map { family(it) }.toSet()
        require(families.size == 1 && families.first() != "*") {
            "a batch is one family"
        }
        return "${families.first()}/*"
    }

    /** `image` for `image/jpeg`; `*` for anything that is not `type/subtype`. */
    fun family(mimeType: String): String {
        val slash = mimeType.indexOf('/')
        return if (slash <= 0) "*" else mimeType.substring(0, slash)
    }

    /** Every distinct type, in the order each was first seen. */
    fun distinctMimeTypes(mimeTypes: List<String>): List<String> =
        normalized(mimeTypes).distinct()

    private fun normalized(mimeTypes: List<String>): List<String> =
        mimeTypes.map { it.trim().lowercase() }.filter { it.isNotEmpty() }
}
