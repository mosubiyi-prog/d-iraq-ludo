from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()
permission = (
    '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
    'android:maxSdkVersion="28" />'
)
if permission not in text:
    pos = text.find(">")
    if pos < 0:
        raise SystemExit("AndroidManifest.xml root tag not found")
    text = text[: pos + 1] + "\n    " + permission + text[pos + 1 :]
    manifest.write_text(text)

kotlin_root = Path("android/app/src/main/kotlin")
activities = list(kotlin_root.rglob("MainActivity.kt"))
if len(activities) != 1:
    raise SystemExit(
        f"Expected one Kotlin MainActivity after flutter create, found {len(activities)}"
    )

activity = activities[0]
existing = activity.read_text()
package_line = next(
    (line.strip() for line in existing.splitlines() if line.strip().startswith("package ")),
    "",
)
if not package_line:
    raise SystemExit("MainActivity package declaration not found")

activity.write_text(
    f"""{package_line}

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {{
    private val mediaChannelName = "com.diraq.ludo/media"
    private val legacyWriteRequestCode = 4207

    private data class PendingSave(
        val bytes: ByteArray,
        val fileName: String,
        val mimeType: String,
        val result: MethodChannel.Result,
    )

    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaChannelName,
        ).setMethodCallHandler {{ call, result ->
            if (call.method != "saveImage") {{
                result.notImplemented()
                return@setMethodCallHandler
            }}

            val bytes = call.argument<ByteArray>("bytes")
            val fileName = call.argument<String>("fileName")?.trim().orEmpty()
            val mimeType = call.argument<String>("mimeType")?.trim().orEmpty()

            if (bytes == null || bytes.isEmpty() || fileName.isEmpty()) {{
                result.error("invalid_image", "Missing image bytes or file name.", null)
                return@setMethodCallHandler
            }}

            val safeMime = if (mimeType.startsWith("image/")) mimeType else "image/jpeg"

            if (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    PackageManager.PERMISSION_GRANTED
            ) {{
                if (pendingSave != null) {{
                    result.error("save_busy", "Another image save is waiting for permission.", null)
                    return@setMethodCallHandler
                }}
                pendingSave = PendingSave(bytes, fileName, safeMime, result)
                requestPermissions(
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    legacyWriteRequestCode,
                )
                return@setMethodCallHandler
            }}

            saveNow(bytes, fileName, safeMime, result)
        }}
    }}

    private fun saveNow(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {{
        try {{
            val savedAt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {{
                saveWithMediaStore(bytes, fileName, mimeType)
            }} else {{
                saveLegacy(bytes, fileName, mimeType)
            }}
            result.success(savedAt)
        }} catch (error: Exception) {{
            result.error(
                "save_failed",
                error.message ?: "Could not save image.",
                null,
            )
        }}
    }}

    private fun saveWithMediaStore(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String {{
        val values = ContentValues().apply {{
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/DEDA",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }}

        val resolver = contentResolver
        val uri = resolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IllegalStateException("Could not create gallery item.")

        try {{
            resolver.openOutputStream(uri)?.use {{ output ->
                output.write(bytes)
                output.flush()
            }} ?: throw IllegalStateException("Could not open gallery output stream.")

            val complete = ContentValues().apply {{
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }}
            resolver.update(uri, complete, null, null)
            return uri.toString()
        }} catch (error: Exception) {{
            resolver.delete(uri, null, null)
            throw error
        }}
    }}

    @Suppress("DEPRECATION")
    private fun saveLegacy(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String {{
        val pictures = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_PICTURES,
        )
        val dedaDirectory = File(pictures, "DEDA")
        if (!dedaDirectory.exists() && !dedaDirectory.mkdirs()) {{
            throw IllegalStateException("Could not create DEDA Pictures folder.")
        }}

        val file = File(dedaDirectory, fileName)
        FileOutputStream(file).use {{ output ->
            output.write(bytes)
            output.flush()
        }}
        MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf(mimeType),
            null,
        )
        return file.absolutePath
    }}

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {{
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != legacyWriteRequestCode) return

        val pending = pendingSave ?: return
        pendingSave = null

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {{
            saveNow(
                pending.bytes,
                pending.fileName,
                pending.mimeType,
                pending.result,
            )
        }} else {{
            pending.result.error(
                "permission_required",
                "Storage permission is required to save this image.",
                null,
            )
        }}
    }}
}}
"""
)

print(f"DEDA image saving channel configured in {activity}")
