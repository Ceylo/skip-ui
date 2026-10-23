// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
import Foundation
import SwiftUI
import XCTest

#if SKIP
import android.content.Context
import androidx.work.Configuration
import androidx.work.Data
import androidx.work.ListenableWorker
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
#endif

final class NotificationRequestTests: SkipUITestCase {
    #if SKIP
    private var context: Context {
        return ProcessInfo.processInfo.androidContext
    }

    private func workManager() -> WorkManager {
        if !WorkManager.isInitialized() {
            let configuration = Configuration.Builder()
                .setExecutor(DirectExecutor())
                .build()
            WorkManager.initialize(context, configuration)
        }
        let workManager = WorkManager.getInstance(context)
        workManager.cancelAllWork().result.get()
        workManager.pruneWork().result.get()
        context.getSharedPreferences("__skip_usernotifications", Context.MODE_PRIVATE).edit().clear().commit()
        return workManager
    }

    private func states(tag: String, _ workManager: WorkManager) -> [String] {
        var states: [String] = []
        let iterator = workManager.getWorkInfosByTag(tag).get().iterator()
        while iterator.hasNext() {
            states.append((iterator.next() as! WorkInfo).state.name)
        }
        return states.sorted()
    }

    private func enqueue(_ identifier: String, inDays days: Double?) {
        let date: Date? = days == nil ? nil : Date().addingTimeInterval(days! * 86400)
        UNUserNotificationCenter.enqueueRequest(identifier: identifier, data: Data.Builder().putString("title", identifier).build(), date: date, context: context)
    }

    private func savedDate(_ identifier: String) -> Int64 {
        return context.getSharedPreferences("__skip_usernotifications", Context.MODE_PRIVATE).getLong("date_" + identifier, 0)
    }
    #endif

    func testRequestReplacesOnlyItsOwnWork() async throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        let workManager = workManager()
        let unrelated = OneTimeWorkRequestBuilder<UnrelatedWorker>().setInitialDelay(1, TimeUnit.DAYS).addTag("daily").build()
        workManager.enqueue(unrelated).result.get()

        enqueue("daily", inDays: 1)
        enqueue("daily", inDays: 2)

        XCTAssertEqual(workManager.getWorkInfoById(unrelated.id).get()?.state, WorkInfo.State.ENQUEUED)
        // Unique work with REPLACE deletes the work it replaces.
        XCTAssertEqual(states(tag: UNUserNotificationCenter.workName("daily"), workManager), ["ENQUEUED"])
        let queued = await UNUserNotificationCenter.queuedNotificationIdentifiers(workManager)
        XCTAssertEqual(queued, ["daily"])

        UNUserNotificationCenter.removePendingRequests(identifiers: ["daily"], context: context)
        XCTAssertEqual(workManager.getWorkInfoById(unrelated.id).get()?.state, WorkInfo.State.ENQUEUED)
        let queuedAfterRemoval = await UNUserNotificationCenter.queuedNotificationIdentifiers(workManager)
        XCTAssertTrue(queuedAfterRemoval.isEmpty)
        XCTAssertEqual(savedDate("daily"), Int64(0))
        #endif
    }

    func testRequestReplacesDuplicatesOfEarlierVersions() async throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        let workManager = workManager()
        // Earlier versions enqueued one request per call, tagged with the bare identifier.
        for _ in 0..<2 {
            workManager.enqueue(OneTimeWorkRequestBuilder<NotificationWorker>().setInitialDelay(1, TimeUnit.DAYS).addTag("reminder").build()).result.get()
        }
        let queued = await UNUserNotificationCenter.queuedNotificationIdentifiers(workManager)
        XCTAssertEqual(queued, ["reminder"])

        // What `add` does: enqueue the request, then sweep the earlier versions' work for its identifier.
        enqueue("reminder", inDays: 1)
        await UNUserNotificationCenter.cancelWorkOfEarlierVersions(identifiers: ["reminder"], workManager: workManager)

        XCTAssertEqual(states(tag: "reminder", workManager), ["CANCELLED", "CANCELLED"])
        XCTAssertEqual(states(tag: UNUserNotificationCenter.workName("reminder"), workManager), ["ENQUEUED"])
        #endif
    }

    func testImmediateRequestReplacesTheScheduledDate() throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        let workManager = workManager()
        enqueue("reminder", inDays: 1)
        XCTAssertGreaterThan(savedDate("reminder"), Int64(System.currentTimeMillis()))

        enqueue("reminder", inDays: nil)

        XCTAssertLessThanOrEqual(savedDate("reminder"), Int64(System.currentTimeMillis()))
        // The request a day out is gone; only the immediate one remains.
        let workInfos = workManager.getWorkInfosByTag(UNUserNotificationCenter.workName("reminder")).get()
        XCTAssertEqual(workInfos.size, 1)
        XCTAssertEqual((workInfos.get(0) as! WorkInfo).initialDelayMillis, Int64(0))
        #endif
    }

    func testAttachmentOptionsAsOnIOS() throws {
        #if !SKIP
        throw XCTSkip("UserNotifications' own attachments on Apple platforms")
        #else
        let image = try UNNotificationAttachment(identifier: "clear", url: URL(fileURLWithPath: "/tmp/a.JPG"), options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: true])
        XCTAssertEqual(image.type, "public.image")
        XCTAssertTrue(image.hidesThumbnail)
        let document = try UNNotificationAttachment(identifier: "doc", url: URL(fileURLWithPath: "/tmp/a.pdf"), options: nil)
        XCTAssertEqual(document.type, "public.data")
        XCTAssertFalse(document.hidesThumbnail)
        #endif
    }

    func testDueRequestPostsAtOnceAndReplacesItsWork() throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        let workManager = workManager()
        enqueue("reminder", inDays: 1)

        UNUserNotificationCenter.postRequest(identifier: "reminder", data: Data.Builder().putString("title", "Now").putInt("id", 42).build(), context: context)

        XCTAssertEqual(states(tag: UNUserNotificationCenter.workName("reminder"), workManager), ["CANCELLED"])
        XCTAssertLessThanOrEqual(savedDate("reminder"), Int64(System.currentTimeMillis()))
        let posted = try XCTUnwrap(activeNotification(id: 42))
        XCTAssertEqual(posted.extras.getString(android.app.Notification.EXTRA_TITLE), "Now")
        XCTAssertTrue(posted.extras.getBoolean(android.app.Notification.EXTRA_SHOW_WHEN))
        #endif
    }

    func testImageAttachmentsAreTheLargeIconAndExpandedPicture() throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        _ = workManager()
        let thumbnail = imageFile("thumbnail.png")
        let picture = imageFile("picture.png")

        NotificationWorker.post(Data.Builder().putInt("id", 43).putString(NotificationWorker.largeIconKey, thumbnail.absoluteString).putString(NotificationWorker.bigPictureKey, picture.absoluteString).build(), context: context)
        let posted = try XCTUnwrap(activeNotification(id: 43))
        XCTAssertNotNil(posted.getLargeIcon())
        XCTAssertTrue(posted.extras.containsKey(android.app.Notification.EXTRA_PICTURE))

        NotificationWorker.post(Data.Builder().putInt("id", 44).build(), context: context)
        let plain = try XCTUnwrap(activeNotification(id: 44))
        XCTAssertNil(plain.getLargeIcon())
        XCTAssertFalse(plain.extras.containsKey(android.app.Notification.EXTRA_PICTURE))
        #endif
    }

    func testRevealButtonPostsTheHiddenPictureAgain() throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        _ = workManager()
        let executor = NotificationActionReceiver.executor
        NotificationActionReceiver.executor = DirectExecutor()
        defer { NotificationActionReceiver.executor = executor }
        let blurred = imageFile("blurred.png")
        let clear = imageFile("clear.png")
        let data = Data.Builder()
            .putInt("id", 45)
            .putString(NotificationWorker.largeIconKey, blurred.absoluteString)
            .putString(NotificationWorker.bigPictureKey, clear.absoluteString)
            .putString(NotificationWorker.revealActionTitleKey, "Show")
            .putString(NotificationWorker.concealActionTitleKey, "Hide")
            .build()

        NotificationWorker.post(data, context: context)
        let hidden = try XCTUnwrap(activeNotification(id: 45))
        XCTAssertFalse(hidden.extras.containsKey(android.app.Notification.EXTRA_PICTURE))
        XCTAssertEqual(actionTitles(hidden), "Show")

        press(hidden)
        let revealed = try XCTUnwrap(activeNotification(id: 45))
        XCTAssertTrue(revealed.extras.containsKey(android.app.Notification.EXTRA_PICTURE))
        XCTAssertEqual(actionTitles(revealed), "Hide")
        XCTAssertEqual(postedTime(revealed), postedTime(hidden))

        press(revealed)
        let hiddenAgain = try XCTUnwrap(activeNotification(id: 45))
        XCTAssertFalse(hiddenAgain.extras.containsKey(android.app.Notification.EXTRA_PICTURE))
        XCTAssertEqual(actionTitles(hiddenAgain), "Show")
        #endif
    }

    func testAttachmentCopyOutlivesTheOriginal() throws {
        #if !SKIP
        throw XCTSkip("Notification requests are WorkManager work on Android")
        #else
        let original = imageFile("original.png")
        let store = UNUserNotificationCenter.newAttachmentStore(id: 46, context: context)
        let copy = UNUserNotificationCenter.store(original, as: "big_picture", in: store)
        java.io.File(original.path).delete()

        XCTAssertNotEqual(copy, original)
        XCTAssertTrue(java.io.File(copy.path).exists())
        XCTAssertEqual(UNUserNotificationCenter.store(original, as: "big_picture", in: nil), original)
        #endif
    }

    #if SKIP
    private func actionTitles(_ notification: android.app.Notification) -> String {
        // SKIP REPLACE: return notification.actions.orEmpty().joinToString { it.title.toString() }
        return ""
    }

    private func postedTime(_ notification: android.app.Notification) -> Int64 {
        // SKIP REPLACE: return notification.`when`
        return 0
    }

    private func press(_ notification: android.app.Notification) {
        notification.actions[0].actionIntent.send()
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
    }

    private func activeNotification(id: Int) -> android.app.Notification? {
        let manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! android.app.NotificationManager
        return manager.activeNotifications.firstOrNull { $0.id == id }?.notification
    }

    private func imageFile(_ name: String) -> URL {
        let file = java.io.File(context.cacheDir, name)
        let bitmap = android.graphics.Bitmap.createBitmap(8, 8, android.graphics.Bitmap.Config.ARGB_8888)
        let stream = java.io.FileOutputStream(file)
        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
        stream.close()
        return URL(fileURLWithPath: file.absolutePath)
    }
    #endif
}

#if SKIP
final class DirectExecutor: java.util.concurrent.Executor {
    override func execute(command: java.lang.Runnable) {
        command.run()
    }
}

public final class UnrelatedWorker: Worker {
    public init(context: Context, params: WorkerParameters) {
        super.init(context, params)
    }

    public override func doWork() -> ListenableWorker.Result {
        return ListenableWorker.Result.success()
    }
}
#endif
