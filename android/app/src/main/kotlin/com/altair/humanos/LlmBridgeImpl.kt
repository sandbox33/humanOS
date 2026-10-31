package com.altair.humanos

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The on-device model (LiteRT-LM, CPU) behind the assistant. It is loaded
 * on demand off the UI thread, answers one request at a time, stops a
 * request after its timeout and leaves memory after [idleMs] without use.
 * It only ever receives the parser prompt built by the app.
 */
class LlmBridgeImpl(private val context: Context) : LlmBridge {
    private val lock = Mutex()
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var loadedPath: String? = null
    private var idleMs = 60_000L
    private val unloadTask = Runnable {
        // Never close the engine in the middle of a request.
        if (lock.tryLock()) {
            try {
                closeEngine()
            } finally {
                lock.unlock()
            }
        } else {
            scheduleUnload()
        }
    }

    private fun closeEngine() {
        val e = engine ?: return
        engine = null
        loadedPath = null
        try {
            e.close()
        } catch (t: Throwable) {
            // Already closed by the runtime.
        }
    }

    private fun scheduleUnload() {
        main.removeCallbacks(unloadTask)
        main.postDelayed(unloadTask, idleMs)
    }

    override suspend fun load(modelPath: String, maxTokens: Long, idleSeconds: Long): LlmLoadResult =
        withContext(Dispatchers.IO) {
            lock.withLock {
                idleMs = idleSeconds * 1000L
                val start = System.currentTimeMillis()
                try {
                    if (engine == null || loadedPath != modelPath) {
                        closeEngine()
                        val created = Engine(
                            EngineConfig(
                                modelPath,
                                backend = Backend.CPU(),
                                maxNumTokens = maxTokens.toInt(),
                                cacheDir = context.cacheDir.path,
                            ),
                        )
                        created.initialize()
                        engine = created
                        loadedPath = modelPath
                    }
                    scheduleUnload()
                    LlmLoadResult(loaded = true, loadMs = System.currentTimeMillis() - start)
                } catch (t: Throwable) {
                    closeEngine()
                    LlmLoadResult(
                        loaded = false,
                        loadMs = System.currentTimeMillis() - start,
                        errorEs = "No se pudo cargar el modelo: ${t.message ?: t.javaClass.simpleName}",
                    )
                }
            }
        }

    override suspend fun generate(prompt: String, timeoutMs: Long): LlmReply = withContext(Dispatchers.IO) {
        lock.withLock {
            val start = System.currentTimeMillis()
            val current = engine ?: return@withLock LlmReply(elapsedMs = 0, errorEs = "El modelo no está cargado.")
            main.removeCallbacks(unloadTask)
            val timedOut = AtomicBoolean(false)
            try {
                // Greedy decoding: the same phrase always gives the same JSON.
                current.createConversation(ConversationConfig(samplerConfig = SamplerConfig(1, 1.0, 1.0, 0))).use { conversation ->
                    val watchdog = Runnable {
                        timedOut.set(true)
                        conversation.cancelProcess()
                    }
                    main.postDelayed(watchdog, timeoutMs)
                    try {
                        val reply = conversation.sendMessage(prompt)
                        val text = reply.contents.contents.filterIsInstance<Content.Text>().joinToString("") { it.text }
                        if (timedOut.get()) {
                            LlmReply(elapsedMs = System.currentTimeMillis() - start, errorEs = "El modelo tardó demasiado.")
                        } else {
                            LlmReply(elapsedMs = System.currentTimeMillis() - start, text = text)
                        }
                    } finally {
                        main.removeCallbacks(watchdog)
                    }
                }
            } catch (t: Throwable) {
                LlmReply(
                    elapsedMs = System.currentTimeMillis() - start,
                    errorEs = if (timedOut.get()) "El modelo tardó demasiado." else "El modelo falló: ${t.message ?: t.javaClass.simpleName}",
                )
            } finally {
                scheduleUnload()
            }
        }
    }

    override fun unload() {
        main.removeCallbacks(unloadTask)
        main.post(unloadTask)
    }

    override fun isLoaded(): Boolean = engine != null

    override fun totalMemoryBytes(): Long {
        val info = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java).getMemoryInfo(info)
        return info.totalMem
    }
}
