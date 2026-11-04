package com.lumebox.app

import android.app.Activity
import android.content.Context
import android.content.IntentFilter
import android.os.BatteryManager
import android.view.KeyEvent
import android.view.WindowManager
import android.webkit.CookieManager
import android.content.Intent
import android.content.ComponentName
import android.content.pm.PackageManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var readerKeysEnabled = false
    private var readerKeys: MethodChannel? = null
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (readerKeysEnabled && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            readerKeys?.invokeMethod("turn", if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) 1 else -1)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (readerKeysEnabled && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }
    private var exportResult: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        unlockHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        unlockHighRefreshRate()
    }

    /// 解锁高刷新率：三星等厂商默认把非白名单应用限制在 60Hz，
    /// 这里主动请求屏幕支持的最高刷新率 DisplayMode（minSdk 26，直接可用）。
    /// 与现有 configureFlutterEngine 里的各通道完全正交，不做任何重写。
    private fun unlockHighRefreshRate() {
        try {
            val display = window.windowManager.defaultDisplay ?: return
            val mode = display.supportedModes
                .filter { it.physicalWidth == display.mode.physicalWidth && it.physicalHeight == display.mode.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            if (mode.modeId != display.mode.modeId) {
                val params = window.attributes
                params.preferredDisplayModeId = mode.modeId
                window.attributes = params
            }
        } catch (_: Exception) {
            // 刷新率请求失败不影响任何功能：系统按默认策略走。
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        readerKeys = MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/reader_keys").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "configure") {
                    readerKeysEnabled = call.argument<Boolean>("enabled") == true
                    result.success(null)
                } else result.notImplemented()
            }
        }
        DanmakuCredentials.register(this, engine.dartExecutor.binaryMessenger)
        super.configureFlutterEngine(engine)
        // 本地凭证加密的根密钥（LocalCipher / SectionDatabase 依赖）：
        // iOS 走钥匙串、Windows 走 DPAPI；Android 用 AndroidKeyStore 包裹——
        // 首次生成 32 字节随机密钥，用 Keystore 内的 AES-GCM 密钥加密后落盘，
        // 根密钥本身不可从 Keystore 导出。返回给 Dart 的是明文密钥（base64）。
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/source_repository")
            .setMethodCallHandler { call, result ->
                if (call.method != "storageKey") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val alias = "lumebox_storage_wrap"
                    val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    if (!keyStore.containsAlias(alias)) {
                        val generator = javax.crypto.KeyGenerator.getInstance("AES", "AndroidKeyStore")
                        generator.init(android.security.keystore.KeyGenParameterSpec.Builder(
                            alias,
                            android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
                        )
                            .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                            .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                            .setKeySize(256)
                            .build())
                        generator.generateKey()
                    }
                    val secretKey = keyStore.getKey(alias, null) as javax.crypto.SecretKey
                    val file = java.io.File(filesDir, "storage_wrap.bin")
                    val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
                    val wrapped: ByteArray
                    if (file.exists()) {
                        val blob = file.readBytes()
                        cipher.init(javax.crypto.Cipher.DECRYPT_MODE, secretKey,
                            javax.crypto.spec.GCMParameterSpec(128, blob.copyOfRange(0, 12)))
                        wrapped = cipher.doFinal(blob.copyOfRange(12, blob.size))
                    } else {
                        wrapped = ByteArray(32).also { java.security.SecureRandom().nextBytes(it) }
                        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, secretKey)
                        file.writeBytes(cipher.iv + cipher.doFinal(wrapped))
                    }
                    result.success(android.util.Base64.encodeToString(wrapped, android.util.Base64.NO_WRAP))
                } catch (error: Exception) {
                    result.error("storageKey", error.message, null)
                }
            }
        // 阅读器状态栏 / 视频播放器的电量胶囊：iOS 侧已实现同名通道，
        // Android 这里补齐（读自身电量无需任何运行时权限）。
        // 覆盖上游的简化实现：属性返回 0 的机型回退粘性广播换算，
        // 异常与越界一律 success(null)，Dart 侧按「未知电量」渲染。
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/battery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "level" -> {
                        try {
                            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                            // BATTERY_PROPERTY_CAPACITY 个别机型返回 0，回退到粘性广播换算。
                            var value = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                            if (value !in 1..100) {
                                val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                                val raw = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                                if (raw >= 0 && scale > 0) value = raw * 100 / scale
                            }
                            result.success(if (value in 0..100) value else null)
                        } catch (error: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        IntroRecognition(this, engine.dartExecutor.binaryMessenger)
        // 阅读器亮度独立调节（iOS 侧已实现同名通道）：screenBrightness 只影响
        // 本 Activity 窗口，退出阅读器由 Dart 侧调 current/重置。
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/brightness")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "set" -> {
                        try {
                            val value = (call.argument<Double>("value") ?: -1.0).toFloat()
                            val lp = window.attributes
                            lp.screenBrightness = if (value <= 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            else value.coerceIn(0.01f, 1.0f)
                            window.attributes = lp
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("brightness", error.message, null)
                        }
                    }
                    "current" -> result.success(window.attributes.screenBrightness.takeIf { it >= 0f })
                    else -> result.notImplemented()
                }
            }
        // 多任务防窥（iOS 侧已实现同名通道）：FLAG_SECURE 让任务切换卡与
        // 截屏不显示应用内容；app 锁开启时由 Dart 侧调用。
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method != "setEnabled") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("privacy", error.message, null)
                }
            }
        // WAF 校验的 HttpOnly Cookie 补充源（iOS 侧为 WKWebView 仓库）。
        // android.webkit.CookieManager.getCookie 会返回包括 HttpOnly 在内的
        // 整串 Cookie；逐枚的 domain/path/expires 元数据 Android 拿不到，
        // 按当前 URL 合成（host 精确匹配 + 路径 /），Dart 侧过滤逻辑兼容。
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/webview")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "allCookies" -> {
                        try {
                            val url = call.arguments as? Map<*, *>
                            val target = url?.get("url") as? String ?: ""
                            val uri = android.net.Uri.parse(target)
                            val host = (uri.host ?: "").lowercase()
                            val raw = if (host.isEmpty()) null
                            else CookieManager.getInstance().getCookie(target)
                            val secure = target.startsWith("https")
                            val list = raw?.split("; ")?.mapNotNull { pair ->
                                val at = pair.indexOf('=')
                                if (at <= 0) null else mapOf(
                                    "name" to pair.substring(0, at).trim(),
                                    "value" to pair.substring(at + 1).trim(),
                                    "domain" to host,
                                    "path" to "/",
                                    "secure" to secure,
                                    "httpOnly" to true,
                                    "expires" to null,
                                )
                            } ?: emptyList()
                            result.success(list)
                        } catch (error: Exception) {
                            result.success(emptyList<Any>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/app_icon")
            .setMethodCallHandler { call, result ->
                val names = listOf("default", "Aurora", "Obsidian", "Solar", "Orbit", "Prism", "Spark")
                fun component(name: String) = ComponentName(packageName, "$packageName.icons.${if (name == "default") "Default" else name}")
                if (call.method == "current") {
                    val current = names.firstOrNull { name ->
                        val state = packageManager.getComponentEnabledSetting(component(name))
                        state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                            (name == "default" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
                    }
                    result.success(current ?: "default")
                } else if (call.method == "set") {
                    val selected = call.arguments as? String
                    if (selected !in names) { result.error("icon", "Unknown icon", null); return@setMethodCallHandler }
                    try {
                        // Enable the destination first, so a failed switch never removes every launcher.
                        packageManager.setComponentEnabledSetting(component(selected!!), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                        names.filter { it != selected }.forEach { name ->
                            packageManager.setComponentEnabledSetting(component(name), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                        }
                        result.success(true)
                    } catch (error: Exception) { result.error("icon", error.message, null) }
                } else { result.notImplemented() }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/configuration")
            .setMethodCallHandler { call, result ->
                if (call.method != "export") { result.notImplemented(); return@setMethodCallHandler }
                if (exportResult != null) { result.error("busy", "Export already open", null); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes") ?: call.argument<String>("text")?.toByteArray(Charsets.UTF_8)
                val name = call.argument<String>("name")
                if (bytes == null || bytes.size > 32 * 1024 * 1024 || name == null || name.contains("/") || name.contains("\\")) { result.error("arguments", "Missing backup", null); return@setMethodCallHandler }
                exportBytes = bytes
                exportResult = result
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (name.endsWith(".zip")) "application/zip" else "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, 4271)
                } catch (error: Exception) {
                    exportBytes = null; exportResult = null
                    result.error("export", error.message, null)
                }
            }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4271) return
        val result = exportResult ?: return
        val bytes = exportBytes
        exportResult = null; exportBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) { result.success(false); return }
        try {
            val stream = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Cannot open destination")
            stream.use { it.write(bytes) }
            result.success(true)
        } catch (error: Exception) { result.error("export", error.message, null) }
    }
}
