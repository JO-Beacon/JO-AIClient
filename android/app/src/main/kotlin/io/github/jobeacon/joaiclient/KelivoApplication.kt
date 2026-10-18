package io.github.jobeacon.joaiclient

import android.app.Application
import android.os.Build
import io.github.jobeacon.joaiclient.background.BackgroundRuntime
import io.github.jobeacon.joaiclient.input.NativeMessageInputPlugin
import io.github.jobeacon.joaiclient.workspace.WorkspacePlugin
import io.github.jobeacon.joaiclient.scheduled.ScheduledTasks
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** One Dart isolate and database owner per process, independent of its UI. */
class KelivoApplication : Application() {
    val backgroundRuntime by lazy { BackgroundRuntime(this) }
    val scheduledTasks by lazy { ScheduledTasks(this) }
    val workspace by lazy { WorkspacePlugin(this) }
    val deviceTools by lazy { DeviceLocalToolsHandler(this) }
    lateinit var messageInput: NativeMessageInputPlugin
        private set

    private val engineHolder = lazy {
        // Android 11 的 Impeller（OpenGL）路径在带实时毛玻璃时超出 120Hz 的
        // 单帧预算；Skia 能把同样的模糊压低到预算内。这里配置共享引擎，
        // 因为 Activity 的启动参数传不到 provideFlutterEngine 提供的引擎。
        val engineArgs = if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
            arrayOf("--enable-impeller=false")
        } else {
            null
        }
        FlutterEngine(this, engineArgs).also { engine ->
            val messenger = engine.dartExecutor.binaryMessenger
            backgroundRuntime.configure(messenger)
            scheduledTasks.configure(messenger)
            workspace.configure(messenger)
            deviceTools.configure(messenger)
            messageInput = NativeMessageInputPlugin(this, messenger)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }

    val hasEngine get() = engineHolder.isInitialized()
    val engine: FlutterEngine get() = engineHolder.value
}
