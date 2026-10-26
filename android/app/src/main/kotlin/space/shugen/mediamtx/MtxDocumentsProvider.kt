package space.shugen.mediamtx

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * Exposes the app's private MediaMTX directory through the Storage Access
 * Framework, so Files / file managers can inspect logs and recordings, or
 * replace a MediaMTX binary manually.
 */
class MtxDocumentsProvider : DocumentsProvider() {
    companion object {
        private const val AUTHORITY_SUFFIX = ".documents"
        private const val ROOT_ID = "root"
        private const val ROOT_TITLE = "MTX 控制台"
        private const val ROOT_DOCUMENT_ID = "root"

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_AVAILABLE_BYTES,
        )

        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
        )
    }

    private lateinit var baseDir: File

    override fun onCreate(): Boolean {
        baseDir = File(requireNotNull(context).filesDir, "mediamtx")
        if (!baseDir.exists()) baseDir.mkdirs()
        return true
    }

    private fun resolve(documentId: String): File {
        if (documentId == ROOT_DOCUMENT_ID) return baseDir
        if (documentId.isBlank() || documentId.startsWith("/") ||
            documentId.split('/').any { it == ".." }
        ) {
            throw FileNotFoundException("Invalid document id")
        }
        val file = File(baseDir, documentId)
        val basePath = baseDir.canonicalPath
        val canonical = file.canonicalPath
        if (canonical != basePath && !canonical.startsWith(basePath + File.separator)) {
            throw FileNotFoundException("Outside root")
        }
        return file
    }

    private fun documentId(file: File): String {
        if (file.canonicalPath == baseDir.canonicalPath) return ROOT_DOCUMENT_ID
        return file.canonicalPath.removePrefix(baseDir.canonicalPath + File.separator)
            .replace(File.separatorChar, '/')
    }

    private fun childId(parentId: String, child: File): String {
        val name = child.name
        return if (parentId == ROOT_DOCUMENT_ID) name else "$parentId/$name"
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_ROOT_PROJECTION)
        val row = cursor.newRow()
        row.add(Root.COLUMN_ROOT_ID, ROOT_ID)
        row.add(Root.COLUMN_DOCUMENT_ID, ROOT_DOCUMENT_ID)
        row.add(Root.COLUMN_TITLE, ROOT_TITLE)
        row.add(Root.COLUMN_SUMMARY, "本机服务 · 日志 / 录制 / 版本")
        row.add(
            Root.COLUMN_FLAGS,
            Root.FLAG_LOCAL_ONLY or Root.FLAG_SUPPORTS_CREATE or
                Root.FLAG_SUPPORTS_IS_CHILD,
        )
        row.add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
        row.add(Root.COLUMN_AVAILABLE_BYTES, baseDir.usableSpace)
        return cursor
    }

    override fun queryDocument(
        documentId: String,
        projection: Array<out String>?,
    ): Cursor {
        val file = resolve(documentId)
        val cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        includeFile(cursor, file)
        return cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val parent = resolve(parentDocumentId)
        val cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        if (!parent.isDirectory) return cursor
        val files = parent.listFiles()?.toList().orEmpty()
            .sortedWith(compareByDescending<File> { it.isDirectory }.thenBy { it.name.lowercase() })
        for (file in files) {
            if (file.name.startsWith(".mtx-")) continue
            includeFile(cursor, file)
        }
        return cursor
    }

    override fun querySearchDocuments(
        rootId: String,
        query: String,
        projection: Array<out String>?,
    ): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        val needle = query.lowercase()
        baseDir.walkTopDown()
            .maxDepth(5)
            .filter { it.isFile && it.name.lowercase().contains(needle) }
            .take(200)
            .forEach { includeFile(cursor, it) }
        return cursor
    }

    private fun includeFile(cursor: MatrixCursor, file: File) {
        val isDir = file.isDirectory
        val row = cursor.newRow()
        row.add(Document.COLUMN_DOCUMENT_ID, documentId(file))
        row.add(Document.COLUMN_DISPLAY_NAME, if (file == baseDir) ROOT_TITLE else file.name)
        row.add(Document.COLUMN_MIME_TYPE, if (isDir) Document.MIME_TYPE_DIR else mimeType(file))
        row.add(Document.COLUMN_SIZE, if (isDir) null else file.length())
        row.add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
        var flags = Document.FLAG_SUPPORTS_RENAME or Document.FLAG_SUPPORTS_DELETE
        if (isDir) {
            flags = flags or Document.FLAG_DIR_SUPPORTS_CREATE
        } else {
            flags = flags or Document.FLAG_SUPPORTS_WRITE
        }
        row.add(Document.COLUMN_FLAGS, flags)
    }

    private fun mimeType(file: File): String {
        val name = file.name.lowercase()
        return when {
            name.endsWith(".log") || name.endsWith(".yml") || name.endsWith(".yaml") ->
                "text/plain"
            name.endsWith(".m3u8") || name.endsWith(".json") || name.endsWith(".txt") ->
                "text/plain"
            name.endsWith(".mp4") -> "video/mp4"
            name.endsWith(".mkv") -> "video/x-matroska"
            name.endsWith(".ts") -> "video/mp2t"
            name.endsWith(".tar.gz") || name.endsWith(".tgz") -> "application/gzip"
            name == "mediamtx" || name.startsWith("mediamtx_") -> "application/octet-stream"
            else -> MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase())
                ?: "application/octet-stream"
        }
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val file = resolve(documentId)
        if (file.isDirectory) throw FileNotFoundException("Not a file")
        val access = when (mode) {
            "r" -> ParcelFileDescriptor.MODE_READ_ONLY
            "w" -> ParcelFileDescriptor.MODE_WRITE_ONLY or
                ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
            "rw" -> ParcelFileDescriptor.MODE_READ_WRITE or
                ParcelFileDescriptor.MODE_CREATE
            else -> throw IllegalArgumentException("Unsupported mode $mode")
        }
        return ParcelFileDescriptor.open(file, access)
    }

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String,
    ): String {
        val parent = resolve(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException("Parent is not a directory")
        val safeName = displayName.substringAfterLast('/').ifBlank { "untitled" }
        val file = File(parent, safeName)
        if (!file.exists()) {
            if (mimeType == Document.MIME_TYPE_DIR) {
                file.mkdirs()
            } else {
                file.parentFile?.mkdirs()
                file.createNewFile()
            }
        }
        return documentId(file)
    }

    override fun deleteDocument(documentId: String) {
        val file = resolve(documentId)
        if (file == baseDir) throw FileNotFoundException("Cannot delete root")
        val deleted = if (file.isDirectory) file.deleteRecursively() else file.delete()
        if (!deleted) throw FileNotFoundException("Unable to delete")
    }

    override fun renameDocument(
        documentId: String,
        displayName: String,
    ): String {
        val file = resolve(documentId)
        if (file == baseDir) throw FileNotFoundException("Cannot rename root")
        val safeName = displayName.substringAfterLast('/').ifBlank { return documentId }
        val target = File(file.parentFile, safeName)
        if (!file.renameTo(target)) throw FileNotFoundException("Unable to rename")
        return documentId(target)
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        return try {
            val parent = resolve(parentDocumentId).canonicalPath
            val child = resolve(documentId).canonicalPath
            child == parent || child.startsWith(parent + File.separator)
        } catch (_: Exception) {
            false
        }
    }

    override fun getDocumentType(documentId: String): String {
        val file = resolve(documentId)
        return if (file.isDirectory) Document.MIME_TYPE_DIR else mimeType(file)
    }
}
