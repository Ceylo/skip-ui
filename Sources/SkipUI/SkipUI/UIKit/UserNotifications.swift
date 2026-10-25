// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.Worker
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.ListenableWorker
import androidx.work.OneTimeWorkRequestBuilder
import java.util.HashSet
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlinx.coroutines.flow.first
#endif

// SKIP @bridge
public final class UNUserNotificationCenter {
    private static let shared = UNUserNotificationCenter()

    private init() {
    }

    // SKIP @bridge
    public static func current() -> UNUserNotificationCenter {
        return shared
    }

    // SKIP @bridge
    public func notificationSettings() async -> UNNotificationSettings {
        #if SKIP
        // The application context, not the activity: a background worker asks too, and has none.
        let context = ProcessInfo.processInfo.androidContext
        let status: UNAuthorizationStatus
        if NotificationManagerCompat.from(context).areNotificationsEnabled() {
            status = .authorized
        } else if Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || UserDefaults.standard.bool(forKey: "UNNotificationPermissionDenied") {
            // Before API 33 there is no permission to ask for: notifications were turned off in Settings.
            status = .denied
        } else {
            status = .notDetermined
        }
        return UNNotificationSettings(authorizationStatus: status)
        #else
        fatalError()
        #endif
    }

    @available(*, unavailable)
    public func setBadgeCount(_ count: Int) async throws {
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        #if SKIP
        guard Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU else {
            return true
        }
        let granted = UIApplication.shared.requestPermission(Manifest.permission.POST_NOTIFICATIONS)
        let defaults = UserDefaults.standard
        if granted {
            defaults.removeObject(forKey: "UNNotificationPermissionDenied")
        } else {
            defaults.set(true, forKey: "UNNotificationPermissionDenied")
        }
        return granted
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func requestAuthorization(bridgedOptions: Int) async throws -> Bool {
        return try await requestAuthorization(options: UNAuthorizationOptions(rawValue: bridgedOptions))
    }

    // SKIP @bridge
    public var delegate: (any UNUserNotificationCenterDelegate)? {
        didSet {
            #if SKIP
            deliverPendingResponse()
            #endif
        }
    }

    @available(*, unavailable)
    public var supportsContentExtensions: Bool {
        fatalError()
    }

    // SKIP @bridge
    public func add(_ request: UNNotificationRequest) async throws {
        #if SKIP
        // Scheduling does not require a delegate. On iOS, willPresent runs only when a
        // notification fires while the app is in the foreground. Gating enqueue on it
        // drops every request from an app that never set a delegate, and drops
        // background notifications whose presentation options are empty.
        let context = ProcessInfo.processInfo.androidContext

        // Build the data which should be displayed in the notification.
        let dataBuilder = Data.Builder()
            .putString("title", request.content.title)
            .putString("body", request.content.body)
            .putInt("id", request.identifier.hashValue)
            .putString(NotificationWorker.identifierKey, request.identifier)
            .putString(NotificationWorker.categoryKey, request.content.categoryIdentifier)
            .putInt(NotificationWorker.interruptionLevelKey, request.content.interruptionLevel.rawValue)
        let messageIntent = request.content.messageIntent
        let sender = messageIntent?.sender
        if let messageIntent, let sender {
            dataBuilder.putString(NotificationWorker.senderNameKey, sender.displayName)
            dataBuilder.putString(NotificationWorker.senderIdentifierKey, sender.customIdentifier)
            dataBuilder.putString(NotificationWorker.senderImageKey, sender.image?.url.absoluteString)
            dataBuilder.putString(NotificationWorker.conversationIdentifierKey, messageIntent.conversationIdentifier)
        }

        // A visible image is the thumbnail beside the text, and a hidden one shows only when expanded:
        // a small image such as an avatar must not be blown up into the expanded picture.
        let images = request.content.attachments.filter { $0.type == "public.image" }
        let thumbnail = images.first(where: { !$0.hidesThumbnail })
        let picture = images.first(where: { $0.hidesThumbnail })

        // Get the next trigger date (if any).
        let nextDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ??
                       (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        let postsNow = nextDate == nil || nextDate!.currentTimeMillis - System.currentTimeMillis() <= UNUserNotificationCenter.immediateDelayMillis

        // A post now reads the files before returning; a later one reads copies, as iOS moves the files into its store.
        var storedAttachments: java.io.File? = nil
        if !images.isEmpty && (!postsNow || sender != nil) {
            await pruneAttachmentStores(context: context)
            storedAttachments = UNUserNotificationCenter.newAttachmentStore(id: request.identifier.hashValue, context: context)
        }
        let thumbnailURL = thumbnail.map { UNUserNotificationCenter.store($0.url, as: "large_icon", in: storedAttachments) }
        if let thumbnail, let thumbnailURL {
            dataBuilder.putString(NotificationWorker.largeIconKey, thumbnailURL.absoluteString)
            dataBuilder.putString(NotificationWorker.largeIconIdentifierKey, thumbnail.identifier)
        }
        if let picture {
            let pictureURL = picture.url == thumbnail?.url ? thumbnailURL! : UNUserNotificationCenter.store(picture.url, as: "big_picture", in: storedAttachments)
            dataBuilder.putString(NotificationWorker.bigPictureKey, pictureURL.absoluteString)
            dataBuilder.putString(NotificationWorker.bigPictureIdentifierKey, picture.identifier)
        }

        for (key, value) in request.content.userInfo {
            if let s = value as? String {
                dataBuilder.putString(key.toString(), s)
            } else if let b = value as? Bool {
                dataBuilder.putBoolean(key.toString(), b)
            } else if let i = value as? Int {
                dataBuilder.putInt(key.toString(), i)
            } else if let d = value as? Double {
                dataBuilder.putDouble(key.toString(), d)
            } else {
                dataBuilder.putString(key.toString(), value.toString())
            }
        }
        
        if postsNow {
            // Posted before returning, as WorkManager can run jobs out of order: serial adds stay in order in the shade,
            // and the attachments are read while their files still exist.
            UNUserNotificationCenter.postRequest(identifier: request.identifier, data: dataBuilder.build(), context: context)
        } else {
            UNUserNotificationCenter.enqueueRequest(identifier: request.identifier, data: dataBuilder.build(), date: nextDate, context: context)
        }

        // SKIP NOWARN
        await UNUserNotificationCenter.cancelWorkOfEarlierVersions(identifiers: [request.identifier], workManager: WorkManager.getInstance(context))
        #endif
    }

    // SKIP @bridge
    public func pendingNotificationRequests() async -> [Any /* UNNotificationRequest */] {
        #if SKIP
        // The queued work is what will fire. A saved date can say otherwise: WorkManager can run a request after its date.
        // SKIP NOWARN
        return await UNUserNotificationCenter.queuedNotificationIdentifiers(WorkManager.getInstance(ProcessInfo.processInfo.androidContext)).map {
            UNNotificationRequest(identifier: $0, content: UNMutableNotificationContent(), trigger: nil)
        }
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        #if SKIP
        UNUserNotificationCenter.removePendingRequests(identifiers: identifiers, context: ProcessInfo.processInfo.androidContext)
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func removeAllPendingNotificationRequests() {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        // Every notification's work carries this tag, whichever SkipUI version enqueued it, and nothing else does.
        WorkManager.getInstance(context).cancelAllWorkByTag(UNUserNotificationCenter.notificationWorkTag)
        UNUserNotificationCenter.forgetRequests(identifiers: getAllNotificationRequests().map { $0.id }, context: context)
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func deliveredNotifications() async -> [Any /* UNNotification */] {
        #if SKIP
        return getDeliveredNotifications()
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext

        // Get all notification identifiers from the shared preferences.
        let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let editor = preferences.edit()
        let ids = HashSet<String>(preferences.getStringSet("ids", HashSet<String>()) ?? HashSet<String>())
        
        // Get the notification manager.
        let notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! NotificationManager
        
        // Cancel all delivered notifications using the notification manager.
        let now = System.currentTimeMillis()
        for identifier in identifiers {
            // A removed notification's tap is no longer a response.
            editor.remove(UNUserNotificationCenter.responseTokenKey(identifier))
            let triggerTime = preferences.getLong("date_" + identifier, 0)
            if triggerTime < now {
                notificationManager.cancel(identifier.hashValue)
                ids.remove(identifier)
                editor.remove("date_" + identifier)
            }
        }
        
        // Update the notification identifiers in the shared preferences.
        editor.putStringSet("ids", ids)
        editor.apply()
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func removeAllDeliveredNotifications() {
        #if SKIP
        let deliveredNotifications = getDeliveredNotifications()
        let identifiers = deliveredNotifications.compactMap { ($0 as? UNNotification)?.request.identifier }
        removeDeliveredNotifications(withIdentifiers: identifiers)
        #else
        fatalError()
        #endif
    }

    /// The categories are saved, as iOS keeps them, so a process that only posts or answers a button finds them.
    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        #if SKIP
        UNUserNotificationCenter.saveCategories(Array(categories), context: ProcessInfo.processInfo.androidContext)
        #endif
    }

    // SKIP @bridge
    public func setNotificationCategories(bridgedCategories: [UNNotificationCategory]) {
        setNotificationCategories(Set(bridgedCategories))
    }

    public func notificationCategories() async -> Set<UNNotificationCategory> {
        #if SKIP
        return Set(UNUserNotificationCenter.loadCategories(context: ProcessInfo.processInfo.androidContext))
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func bridgedNotificationCategories() async -> [UNNotificationCategory] {
        return Array(await notificationCategories())
    }

    #if SKIP
    /// The tag WorkManager gives every notification's work: its worker's class name.
    private static let notificationWorkTag: String = NotificationWorker.self.java.name
    private static let workNamePrefix = "__skip_usernotifications."

    /// The unique work name of the request with `identifier`, which is also its work's tag.
    static func workName(_ identifier: String) -> String {
        return workNamePrefix + identifier
    }

    /// Enqueues the notification work for `identifier`, replacing the identifier's earlier request as iOS
    /// does, and saves when it is due: `date`, or now for a request with no trigger. Returns as soon as the
    /// work is handed to WorkManager, which queues it on its own executor.
    static func enqueueRequest(identifier: String, data: Data, date: Date?, context: Context) {
        let delayMillis = date != nil ? max(0, date!.currentTimeMillis - System.currentTimeMillis()) : 0
        let workRequest = OneTimeWorkRequestBuilder<NotificationWorker>()
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(workName(identifier))
            .build()
        // Unique work replaces the work enqueued under its name.
        WorkManager.getInstance(context).enqueueUniqueWork(workName(identifier), ExistingWorkPolicy.REPLACE, workRequest)
        saveRequest(identifier: identifier, date: date, context: context)
    }

    /// A new directory for copies of the attachments of the notification with `id`. iOS moves an attachment's file
    /// into its own store when the request is added; the copy keeps the image for as long as the notification can
    /// show it, as its owner may delete the original. Each request gets its own, so a request replacing a notification
    /// still showing leaves that notification's files alone.
    static func newAttachmentStore(id: Int, context: Context) -> java.io.File {
        let directory = java.io.File(java.io.File(attachmentStoresDirectory(context), String(describing: id)), String(describing: System.currentTimeMillis()))
        directory.mkdirs()
        return directory
    }

    static func attachmentStoresDirectory(_ context: Context) -> java.io.File {
        return java.io.File(context.getNoBackupFilesDir(), "skip_usernotifications_attachments")
    }

    /// Copies the file at `url` into `directory` as `name`, returning the copy's URL, or `url` when there is no
    /// directory or the file can't be copied.
    static func store(_ url: URL, as name: String, in directory: java.io.File?) -> URL {
        guard let directory else {
            return url
        }
        do {
            let copy = java.io.File(directory, name)
            java.io.File(url.path).copyTo(copy, overwrite: true)
            return URL(fileURLWithPath: copy.absolutePath)
        } catch {
            logger.warning("keeping the original of a notification attachment, which could not be copied: \(error)")
            return url
        }
    }

    /// Copies are kept this long after their notification stops showing: a snoozed notification is not an active one,
    /// and a notification joins the active ones some time after it's posted.
    private static let attachmentStoreGraceMillis: Long = 24 * 60 * 60 * 1000
    private static let attachmentPruneIntervalMillis: Long = 10 * 60 * 1000
    private static var lastAttachmentPruneMillis: Long = 0

    /// Deletes the attachment copies of notifications that are neither showing nor queued, once their grace period is
    /// over. Runs at most every ten minutes.
    private func pruneAttachmentStores(context: Context) async {
        let now = System.currentTimeMillis()
        guard now - UNUserNotificationCenter.lastAttachmentPruneMillis >= UNUserNotificationCenter.attachmentPruneIntervalMillis else {
            return
        }
        UNUserNotificationCenter.lastAttachmentPruneMillis = now
        let expired = now - UNUserNotificationCenter.attachmentStoreGraceMillis
        let notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! NotificationManager
        var kept = Set<String>()
        for notification in notificationManager.getActiveNotifications() {
            kept.insert(String(describing: notification.getId()))
        }
        // Queued work can run after its date.
        for identifier in await UNUserNotificationCenter.queuedNotificationIdentifiers(WorkManager.getInstance(context)) {
            kept.insert(String(describing: identifier.hashValue))
        }
        let directories = UNUserNotificationCenter.attachmentStoresDirectory(context).listFiles()
        for index in 0..<(directories?.size ?? 0) {
            let directory = directories![index]
            if !kept.contains(directory.getName()) && directory.lastModified() < expired {
                directory.deleteRecursively()
            }
        }
    }

    static let preferencesName = "__skip_usernotifications"
    private static let categoriesKey = "categories"

    static func saveCategories(_ categories: [UNNotificationCategory], context: Context) {
        let json = org.json.JSONArray()
        // Sorted, as a set's order changes from one process to the next.
        for category in categories.sorted(by: { $0.identifier < $1.identifier }) {
            let actions = org.json.JSONArray()
            for action in category.actions {
                actions.put(org.json.JSONObject().put("identifier", action.identifier).put("title", action.title).put("options", action.options.rawValue))
            }
            let intentIdentifiers = org.json.JSONArray()
            for intentIdentifier in category.intentIdentifiers {
                intentIdentifiers.put(intentIdentifier)
            }
            json.put(org.json.JSONObject().put("identifier", category.identifier).put("actions", actions).put("intentIdentifiers", intentIdentifiers).put("options", category.options.rawValue))
        }
        // An app sets them at every launch, usually unchanged.
        let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let saved = json.toString()
        if preferences.getString(categoriesKey, nil) != saved {
            preferences.edit().putString(categoriesKey, saved).apply()
        }
    }

    static func loadCategories(context: Context) -> [UNNotificationCategory] {
        guard let saved = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE).getString(categoriesKey, nil) else {
            return []
        }
        var categories: [UNNotificationCategory] = []
        do {
            let json = org.json.JSONArray(saved)
            for i in 0..<json.length() {
                let category = json.getJSONObject(i)
                let actionsJSON = category.getJSONArray("actions")
                var actions: [UNNotificationAction] = []
                for j in 0..<actionsJSON.length() {
                    let action = actionsJSON.getJSONObject(j)
                    actions.append(UNNotificationAction(identifier: action.getString("identifier"), title: action.getString("title"), options: UNNotificationActionOptions(rawValue: action.getInt("options"))))
                }
                let intentsJSON = category.optJSONArray("intentIdentifiers")
                var intentIdentifiers: [String] = []
                for j in 0..<(intentsJSON?.length() ?? 0) {
                    intentIdentifiers.append(intentsJSON!.getString(j))
                }
                categories.append(UNNotificationCategory(identifier: category.getString("identifier"), actions: actions, intentIdentifiers: intentIdentifiers, options: UNNotificationCategoryOptions(rawValue: category.getInt("options"))))
            }
        } catch {
            logger.warning("ignoring unreadable notification categories: \(error)")
        }
        return categories
    }

    /// Delivers the response to a button that doesn't open the app, waiting for the delegate to handle it. Without a
    /// delegate yet, it waits for one, as a tap does.
    func receiveActionResponse(_ response: UNNotificationResponse) async {
        guard let delegate else {
            pendingResponse = response
            return
        }
        await delegate.userNotificationCenter(self, didReceive: response)
    }

    /// A trigger at most this far away posts at once, without a WorkManager job.
    static let immediateDelayMillis: Long = 1000

    /// Posts the notification for `identifier` now, replacing the identifier's pending request.
    static func postRequest(identifier: String, data: Data, context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(workName(identifier))
        saveRequest(identifier: identifier, date: nil, context: context)
        NotificationWorker.post(data, context: context)
    }

    /// Cancels the work of the requests with `identifiers`, whatever their saved dates: work can still be
    /// queued after its date. Returns as soon as the cancellations are handed to WorkManager; the work of
    /// earlier SkipUI versions is swept afterwards, off the caller's thread.
    static func removePendingRequests(identifiers: [String], context: Context) {
        let workManager = WorkManager.getInstance(context)
        for identifier in identifiers {
            workManager.cancelUniqueWork(workName(identifier))
        }
        forgetRequests(identifiers: identifiers, context: context)
        // Only an earlier version's work carries a bare identifier tag, so a request added after this call
        // is safe from the sweep.
        Task {
            await cancelWorkOfEarlierVersions(identifiers: identifiers, workManager: workManager)
        }
    }

    /// The identifiers of the notifications whose work has not run yet.
    static func queuedNotificationIdentifiers(_ workManager: WorkManager) async -> [String] {
        var identifiers: [String] = []
        for work in await notificationWork(taggedWith: notificationWorkTag, workManager) {
            if (work.info.state == WorkInfo.State.ENQUEUED || work.info.state == WorkInfo.State.BLOCKED) && !identifiers.contains(work.identifier) {
                identifiers.append(work.identifier)
            }
        }
        return identifiers
    }

    /// Cancels the work that earlier SkipUI versions enqueued for `identifiers`: one request per call, tagged
    /// with the bare identifier. Only NotificationWorker's work is cancelled, so the app's own work is never
    /// touched, even when it shares a tag with a notification identifier.
    static func cancelWorkOfEarlierVersions(identifiers: [String], workManager: WorkManager) async {
        for identifier in identifiers {
            for work in await notificationWork(taggedWith: identifier, workManager) {
                if !work.info.state.isFinished {
                    workManager.cancelWorkById(work.info.id)
                }
            }
        }
    }

    /// The notification work carrying `tag`, each with its request identifier: the work name tag, or the bare
    /// identifier that earlier SkipUI versions tagged it with. Only NotificationWorker's work counts. The read
    /// suspends until WorkManager answers; nothing waits on a thread.
    private static func notificationWork(taggedWith tag: String, _ workManager: WorkManager) async -> [(identifier: String, info: WorkInfo)] {
        var work: [(identifier: String, info: WorkInfo)] = []
        // SKIP NOWARN
        let workInfos = await workManager.getWorkInfosByTagFlow(tag).first()
        let iterator = workInfos.iterator()
        while iterator.hasNext() {
            let info = iterator.next() as! WorkInfo
            guard info.tags.contains(notificationWorkTag) else { continue }
            let tags = info.tags.iterator()
            while tags.hasNext() {
                let tag = tags.next() as! String
                if tag.hasPrefix(workNamePrefix) {
                    work.append((identifier: String(tag.dropFirst(workNamePrefix.count)), info: info))
                } else if tag != notificationWorkTag {
                    work.append((identifier: tag, info: info))
                }
            }
        }
        return work
    }

    /// Saves the identifier and its date, so the request can be found and removed later.
    private static func saveRequest(identifier: String, date: Date?, context: Context) {
        let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let ids = HashSet<String>(preferences.getStringSet("ids", HashSet<String>()) ?? HashSet<String>())
        ids.add(identifier)
        preferences.edit()
            .putStringSet("ids", ids)
            .putLong("date_" + identifier, date?.currentTimeMillis ?? System.currentTimeMillis())
            .apply()
    }

    /// Drops the requests with `identifiers` that have not reached their date from the saved list, which also
    /// lists delivered notifications.
    static func forgetRequests(identifiers: [String], context: Context) {
        let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let editor = preferences.edit()
        let ids = HashSet<String>(preferences.getStringSet("ids", HashSet<String>()) ?? HashSet<String>())
        let now = System.currentTimeMillis()
        for identifier in identifiers {
            if preferences.getLong("date_" + identifier, 0) > now {
                ids.remove(identifier)
                editor.remove("date_" + identifier)
            }
        }
        editor.putStringSet("ids", ids)
        editor.apply()
    }

    private func getAllNotificationRequests() -> [(id: String, timestamp: Long)] {
        let preferences = ProcessInfo.processInfo.androidContext.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let ids = preferences.getStringSet("ids", nil) ?? java.util.HashSet<String>()
        
        var all: [(id: String, timestamp: Long)] = []
        let iterator = ids.iterator()
        while iterator.hasNext() {
            let id = iterator.next() as! String
            let time = preferences.getLong("date_" + id, 0)
            all.append((id: id, timestamp: time))
        }
        
        return all
    }

    private func getPendingNotificationRequests() -> [Any /* UNNotificationRequest */] {
        let now = Date().currentTimeMillis
        return getAllNotificationRequests()
            .filter { $0.timestamp > now }
            .map {
                UNNotificationRequest(identifier: $0.id, content: UNMutableNotificationContent(), trigger: nil)
            }
    }

    private func getDeliveredNotifications() -> [Any /* UNNotification */] {
        let now = Date().currentTimeMillis
        return getAllNotificationRequests()
            .filter { $0.timestamp <= now }
            .map {
                let request = UNNotificationRequest(identifier: $0.id, content: UNMutableNotificationContent(), trigger: nil)
                return UNNotification(request: request, date: Date(timeIntervalSince1970: Double($0.timestamp) / 1000.0))
            }
    }

    /// A tap that arrived before there was a delegate to receive it.
    private var pendingResponse: UNNotificationResponse?

    /// Delivers the tap on a notification this center posted, which opened the app's activity
    /// with `intent`, to the delegate's `didReceive` as the default action, as iOS does. Without a
    /// delegate yet, the tap waits for one. Any other intent is ignored. Returns whether the
    /// intent was such a tap.
    @discardableResult func receiveResponse(from intent: Intent) -> Bool {
        let context = ProcessInfo.processInfo.androidContext
        guard let response = UNUserNotificationCenter.response(from: intent, context: context) else {
            return false
        }
        if response.actionIdentifier != UNNotificationDefaultActionIdentifier {
            // iOS removes a notification once one of its actions is chosen; a tap's is auto-cancelled.
            let notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! NotificationManager
            notificationManager.cancel(response.notification.request.identifier.hashValue)
        }
        pendingResponse = response
        deliverPendingResponse()
        return true
    }

    /// Reads the tap that launched `activity`, and the taps that reach it while it runs.
    func receiveResponses(in activity: androidx.activity.ComponentActivity) {
        if let intent = activity.intent {
            receiveResponse(from: intent)
        }
        activity.addOnNewIntentListener(NotificationResponseListener())
    }

    private func deliverPendingResponse() {
        guard let delegate, let response = pendingResponse else {
            return
        }
        pendingResponse = nil
        Task {
            await delegate.userNotificationCenter(self, didReceive: response)
        }
    }

    /// Issues the token that a tap on the notification with `identifier` must present, replacing
    /// the token of any notification posted earlier with that identifier.
    static func issueResponseToken(identifier: String, context: Context) -> String {
        let token = java.util.UUID.randomUUID().toString()
        context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE).edit()
            .putString(responseTokenKey(identifier), token)
            .commit()
        return token
    }

    static func responseTokenKey(_ identifier: String) -> String {
        return "response_token_" + identifier
    }

    /// The default-action response to the tap that opened an activity with `intent`, or nil when
    /// the intent does not present the token of a notification this center posted.
    ///
    /// The activity is exported, so any app can start it with any extras; the token, which only
    /// the notification's own pending intent carries, proves the tap. It is spent here, so the
    /// launch intent the system hands an activity again when it recreates it (after a process
    /// death, or from Recents) yields no second response.
    static func response(from intent: Intent, context: Context) -> UNNotificationResponse? {
        do {
            // Reading an extra unparcels the whole bundle, which throws on a malformed one.
            guard let extras = intent.extras, let identifier = extras.getString(NotificationWorker.identifierKey), let token = extras.getString(NotificationWorker.tokenKey) else {
                return nil
            }
            let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
            guard token == preferences.getString(responseTokenKey(identifier), nil) else {
                return nil
            }
            preferences.edit().remove(responseTokenKey(identifier)).commit()

            let actionIdentifier = extras.getString(NotificationWorker.actionIdentifierKey) ?? UNNotificationDefaultActionIdentifier
            let postedMillis = extras.getLong(NotificationWorker.dateKey, 0)
            if let bytes = extras.getByteArray(NotificationWorker.dataKey) {
                return NotificationWorker.response(to: Data.fromByteArray(bytes), actionIdentifier: actionIdentifier, postedMillis: postedMillis)
            }
            // An intent posted without the notification's data carries its userInfo only.
            var userInfo: [AnyHashable: Any] = [:]
            for key in extras.keySet() where key != NotificationWorker.identifierKey && key != NotificationWorker.tokenKey && key != NotificationWorker.dateKey && key != NotificationWorker.actionIdentifierKey && key != NotificationWorker.dataKey {
                // NotificationWorker writes these types only.
                if let value = extras.get(key), value is String || value is Bool || value is Int || value is Double {
                    userInfo[key] = value
                }
            }
            let content = UNMutableNotificationContent()
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let date = Date(timeIntervalSince1970: Double(postedMillis) / 1000.0)
            return UNNotificationResponse(actionIdentifier: actionIdentifier, notification: UNNotification(request: request, date: date))
        } catch {
            logger.warning("ignoring an unreadable intent: \(error)")
            return nil
        }
    }
    #endif
}

#if SKIP
struct NotificationResponseListener : androidx.core.util.Consumer<Intent> {
    override func accept(value: Intent) {
        UNUserNotificationCenter.current().receiveResponse(from: value)
    }
}
#endif

// SKIP @bridge
public protocol UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive notification: UNNotificationResponse) async

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?)
}

extension UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive notification: UNNotificationResponse) async {
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return []
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
    }
}

public struct UNAuthorizationOptions : OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0) // For bridging
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1) // For bridging
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2) // For bridging
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3) // For bridging
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4) // For bridging
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5) // For bridging
    public static var provisional = UNAuthorizationOptions(rawValue: 1 << 6) // For bridging
}

// SKIP @bridge
public final class UNNotification {
    // SKIP @bridge
    public let request: UNNotificationRequest
    // SKIP @bridge
    public let date: Date

    // SKIP @bridge
    public init(request: UNNotificationRequest, date: Date) {
        self.request = request
        self.date = date
    }
}

// SKIP @bridge
public final class UNNotificationRequest : @unchecked Sendable {
    // SKIP @bridge
    public let identifier: String
    // SKIP @bridge
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    
    // SKIP @bridge
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }

    // SKIP @bridge
    public convenience init(identifier: String, content: UNNotificationContent) {
        self.init(identifier: identifier, content: content, trigger: UNPushNotificationTrigger(repeats: false))
    }
}

public let UNNotificationDefaultActionIdentifier = "UNNotificationDefaultActionIdentifier" // For bridging
public let UNNotificationDismissActionIdentifier = "UNNotificationDismissActionIdentifier" // For bridging

// SKIP @bridge
public final class UNNotificationResponse {
    // SKIP @bridge
    public let actionIdentifier: String
    // SKIP @bridge
    public let notification: UNNotification

    @available(*, unavailable)
    public var targetScene: Any? /* UIScene? */ {
        fatalError()
    }

    // SKIP @bridge
    public init(actionIdentifier: String = "UNNotificationDefaultActionIdentifier" /* UNNotificationDefaultActionIdentifier */, notification: UNNotification) {
        self.actionIdentifier = actionIdentifier
        self.notification = notification
    }
}

// SKIP @bridge
public struct UNNotificationActionOptions : OptionSet {
    // SKIP @bridge
    public let rawValue: Int

    // SKIP @bridge
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1 << 0) // For bridging
    public static let destructive = UNNotificationActionOptions(rawValue: 1 << 1) // For bridging
    public static let foreground = UNNotificationActionOptions(rawValue: 1 << 2) // For bridging
}

// SKIP @bridge
public final class UNNotificationAction {
    // SKIP @bridge
    public let identifier: String
    // SKIP @bridge
    public let title: String
    public let options: UNNotificationActionOptions

    public init(identifier: String, title: String, options: UNNotificationActionOptions = []) {
        self.identifier = identifier
        self.title = title
        self.options = options
    }

    // SKIP @bridge
    public convenience init(identifier: String, title: String, bridgedOptions: Int) {
        self.init(identifier: identifier, title: title, options: UNNotificationActionOptions(rawValue: bridgedOptions))
    }

    // SKIP @bridge
    public var bridgedOptions: Int {
        return options.rawValue
    }
}

// SKIP @bridge
public struct UNNotificationCategoryOptions : OptionSet {
    // SKIP @bridge
    public let rawValue: Int

    // SKIP @bridge
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1 << 0) // For bridging
    public static let allowInCarPlay = UNNotificationCategoryOptions(rawValue: 1 << 1) // For bridging
    public static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 1 << 2) // For bridging
    public static let hiddenPreviewsShowSubtitle = UNNotificationCategoryOptions(rawValue: 1 << 3) // For bridging
}

/// Its actions become the buttons of the notifications whose `categoryIdentifier` names it.
// SKIP @bridge
public final class UNNotificationCategory : Hashable {
    // SKIP @bridge
    public let identifier: String
    // SKIP @bridge
    public let actions: [UNNotificationAction]
    // SKIP @bridge
    public let intentIdentifiers: [String]
    public let options: UNNotificationCategoryOptions

    public init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.options = options
    }

    // SKIP @bridge
    public convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], bridgedOptions: Int) {
        self.init(identifier: identifier, actions: actions, intentIdentifiers: intentIdentifiers, options: UNNotificationCategoryOptions(rawValue: bridgedOptions))
    }

    // SKIP @bridge
    public var bridgedOptions: Int {
        return options.rawValue
    }

    public static func ==(lhs: UNNotificationCategory, rhs: UNNotificationCategory) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

public enum UNNotificationInterruptionLevel : Int {
    case passive = 0
    case active = 1
    case timeSensitive = 2
    case critical = 3
}

// SKIP @bridge
public struct UNNotificationPresentationOptions : OptionSet {
    // SKIP @bridge
    public let rawValue: Int

    // SKIP @bridge
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0) // For bridging
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 1) // For bridging
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 2) // For bridging
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 3) // For bridging
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 4) // For bridging
}

// SKIP @bridge
public class UNNotificationContent {
    // SKIP @bridge
    public var title: String
    // SKIP @bridge
    public var subtitle: String
    // SKIP @bridge
    public var body: String
    public var badge: NSNumber?
    // SKIP @bridge
    public var bridgedBadge: Int? {
        return badge?.intValue
    }
    // SKIP @bridge
    public var sound: UNNotificationSound?
    // SKIP @bridge
    public var launchImageName: String
    public var userInfo: [AnyHashable: Any]
    // SKIP @bridge
    public var bridgedUserInfo: [AnyHashable: Any] {
        return userInfo.filter { entry in
            let value = entry.value
            return value is Bool || value is Double || value is Float || value is Int || value is Int64 || value is String || value is Array<Any> || value is Dictionary<AnyHashable, Any> || value is Set<AnyHashable>
        }
    }
    // SKIP @bridge
    public var attachments: [UNNotificationAttachment]
    // SKIP @bridge
    public var categoryIdentifier: String
    // SKIP @bridge
    public var threadIdentifier: String
    // SKIP @bridge
    public var targetContentIdentifier: String?
    // SKIP @bridge
    public var summaryArgument: String
    // SKIP @bridge
    public var summaryArgumentCount: Int
    // SKIP @bridge
    public var filterCriteria: String?
    public var interruptionLevel: UNNotificationInterruptionLevel = .active
    // SKIP @bridge
    public var bridgedInterruptionLevel: Int {
        get { interruptionLevel.rawValue }
        set { interruptionLevel = UNNotificationInterruptionLevel(rawValue: newValue) ?? .active }
    }

    public init(title: String = "", subtitle: String = "", body: String = "", badge: NSNumber? = nil, sound: UNNotificationSound? = UNNotificationSound.default, launchImageName: String = "", userInfo: [AnyHashable: Any] = [:], attachments: [UNNotificationAttachment] = [], categoryIdentifier: String = "", threadIdentifier: String = "", targetContentIdentifier: String? = nil, summaryArgument: String = "", summaryArgumentCount: Int = 0, filterCriteria: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.sound = sound
        self.launchImageName = launchImageName
        self.userInfo = userInfo
        self.attachments = attachments
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.targetContentIdentifier = targetContentIdentifier
        self.summaryArgument = summaryArgument
        self.summaryArgumentCount = summaryArgumentCount
        self.filterCriteria = filterCriteria
    }

    var messageIntent: INSendMessageIntent?
    // SKIP @bridge
    public var bridgedMessageIntent: INSendMessageIntent? {
        get { messageIntent }
        set { messageIntent = newValue }
    }

    // SKIP @bridge
    public static func bridgedContent(title: String, subtitle: String, body: String, badge: Int?, sound: UNNotificationSound?, launchImageName: String, userInfo: [AnyHashable: Any], attachments: [UNNotificationAttachment], categoryIdentifier: String, threadIdentifier: String, targetContentIdentifier: String?, summaryArgument: String, summaryArgumentCount: Int, filterCriteria: String?) -> UNNotificationContent {
        return UNNotificationContent(title: title, subtitle: subtitle, body: body, badge: badge == nil ? nil : NSNumber(value: Int32(badge!)), sound: sound, launchImageName: launchImageName, userInfo: userInfo, attachments: attachments, categoryIdentifier: categoryIdentifier, threadIdentifier: threadIdentifier, targetContentIdentifier: targetContentIdentifier, summaryArgument: summaryArgument, summaryArgumentCount: summaryArgumentCount, filterCriteria: filterCriteria)
    }

    public func mutableCopy() -> Any {
        let copy = UNMutableNotificationContent()
        copy.title = title
        copy.subtitle = subtitle
        copy.body = body
        copy.badge = badge
        copy.sound = sound
        copy.launchImageName = launchImageName
        copy.userInfo = userInfo
        copy.attachments = attachments
        copy.categoryIdentifier = categoryIdentifier
        copy.threadIdentifier = threadIdentifier
        copy.targetContentIdentifier = targetContentIdentifier
        copy.summaryArgument = summaryArgument
        copy.summaryArgumentCount = summaryArgumentCount
        copy.filterCriteria = filterCriteria
        copy.interruptionLevel = interruptionLevel
        copy.messageIntent = messageIntent
        return copy
    }

    public func updating(from provider: UNNotificationContentProviding) throws -> UNNotificationContent {
        let copy = mutableCopy() as! UNMutableNotificationContent
        if let intent = provider as? INSendMessageIntent {
            copy.messageIntent = intent
            if let sender = intent.sender {
                copy.title = sender.displayName
            }
        }
        return copy
    }
}

public protocol UNNotificationContentProviding {
}

public final class UNMutableNotificationContent : UNNotificationContent {
    public override var title: String {
        get { super.title }
        set { super.title = newValue }
    }
    public override var subtitle: String {
        get { super.subtitle }
        set { super.subtitle = newValue }
    }
    public override var body: String {
        get { super.body }
        set { super.body = newValue }
    }
    public override var badge: NSNumber? {
        get { super.badge }
        set { super.badge = newValue }
    }
    public override var sound: UNNotificationSound? {
        get { super.sound }
        set { super.sound = newValue }
    }
    public override var launchImageName: String {
        get { super.launchImageName }
        set { super.launchImageName = newValue }
    }
    public override var userInfo: [AnyHashable: Any] {
        get { super.userInfo }
        set { super.userInfo = newValue }
    }
    public override var attachments: [UNNotificationAttachment] {
        get { super.attachments }
        set { super.attachments = newValue }
    }
    public override var categoryIdentifier: String {
        get { super.categoryIdentifier }
        set { super.categoryIdentifier = newValue }
    }
    public override var threadIdentifier: String {
        get { super.threadIdentifier }
        set { super.threadIdentifier = newValue }
    }
    public override var targetContentIdentifier: String? {
        get { super.targetContentIdentifier }
        set { super.targetContentIdentifier = newValue }
    }
    public override var summaryArgument: String {
        get { super.summaryArgument }
        set { super.summaryArgument = newValue }
    }
    public override var summaryArgumentCount: Int {
        get { super.summaryArgumentCount }
        set { super.summaryArgumentCount = newValue }
    }
    public override var filterCriteria: String? {
        get { super.filterCriteria }
        set { super.filterCriteria = newValue }
    }
}

// SKIP @bridge
public final class UNNotificationSound {
    public let name: UNNotificationSoundName
    // SKIP @bridge
    public var bridgedName: String {
        return name.rawValue
    }
    // SKIP @bridge
    public let volume: Float

    // SKIP @bridge
    public static var `default`: UNNotificationSound {
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: "default"))
    }

    // SKIP @bridge
    public static var defaultCriticalSound: UNNotificationSound {
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: "default_critical"))
    }

    // SKIP @bridge
    public static func defaultCriticalSound(withAudioVolume volume: Float) -> UNNotificationSound {
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: "default_critical"), volume: volume)
    }

    public init(named name: UNNotificationSoundName, volume: Float = Float(0.0)) {
        self.name = name
        self.volume = volume
    }

    // SKIP @bridge
    public convenience init(named name: String, volume: Float) {
        self.init(named: UNNotificationSoundName(rawValue: name), volume: volume)
    }

    public static func soundNamed(_ name: UNNotificationSoundName) -> UNNotificationSound {
        return UNNotificationSound(named: name)
    }
}

public struct UNNotificationSoundName: RawRepresentable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public let UNNotificationAttachmentOptionsTypeHintKey = "UNNotificationAttachmentOptionsTypeHintKey"
public let UNNotificationAttachmentOptionsThumbnailHiddenKey = "UNNotificationAttachmentOptionsThumbnailHiddenKey"
public let UNNotificationAttachmentOptionsThumbnailClippingRectKey = "UNNotificationAttachmentOptionsThumbnailClippingRectKey"
public let UNNotificationAttachmentOptionsThumbnailTimeKey = "UNNotificationAttachmentOptionsThumbnailTimeKey"

// SKIP @bridge
public class UNNotificationAttachment {
    // SKIP @bridge
    public let identifier: String
    // SKIP @bridge
    public let url: URL
    // SKIP @bridge
    public let type: String
    // SKIP @bridge
    public let timeShift: TimeInterval
    /// `UNNotificationAttachmentOptionsThumbnailHiddenKey`: the image shows only in the expanded notification.
    // SKIP @bridge
    public let hidesThumbnail: Bool

    // SKIP @bridge
    public init(identifier: String, url: URL, type: String = "public.data", timeShift: TimeInterval = 0, hidesThumbnail: Bool = false) {
        self.identifier = identifier
        self.url = url
        self.type = type
        self.timeShift = timeShift
        self.hidesThumbnail = hidesThumbnail
    }

    public convenience init(identifier: String, url: URL, options: [AnyHashable: Any]? = nil) throws {
        self.init(identifier: identifier, url: url, type: UNNotificationAttachment.type(of: url, hint: UNNotificationAttachment.typeHint(options)), hidesThumbnail: UNNotificationAttachment.hidesThumbnail(options))
    }

    // Kotlin's delegating constructor call can't read the option key globals itself.
    private static func typeHint(_ options: [AnyHashable: Any]?) -> String? {
        return options?[UNNotificationAttachmentOptionsTypeHintKey] as? String
    }

    private static func hidesThumbnail(_ options: [AnyHashable: Any]?) -> Bool {
        return options?[UNNotificationAttachmentOptionsThumbnailHiddenKey] as? Bool ?? false
    }

    public static func attachment(withIdentifier identifier: String, url: URL, options: [AnyHashable: Any]? = nil) throws -> UNNotificationAttachment {
        return try UNNotificationAttachment(identifier: identifier, url: url, options: options)
    }

    /// The type iOS infers from the file extension, unless the options give one.
    // SKIP @bridge
    public static func type(of url: URL, hint: String?) -> String {
        if let hint {
            return hint
        }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp":
            return "public.image"
        default:
            return "public.data"
        }
    }
}

// SKIP @bridge
public class UNNotificationTrigger {
    
    // SKIP @bridge
    public let repeats: Bool

    // SKIP @bridge
    public init(repeats: Bool) {
        self.repeats = repeats
    }
}

// SKIP @bridge
public final class UNTimeIntervalNotificationTrigger: UNNotificationTrigger {
    
    // SKIP @bridge
    public let timeInterval: TimeInterval

    // SKIP @bridge
    public init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        super.init(repeats: repeats)
    }

    // SKIP @bridge
    public func nextTriggerDate() -> Date? {
        let now = Date()
        return now.addingTimeInterval(self.timeInterval)
    }
}

// SKIP @bridge
public final class UNCalendarNotificationTrigger: UNNotificationTrigger {
    
    // SKIP @bridge
    public let dateComponents: Any /* DateComponents */
    
    // SKIP @bridge
    public init(dateMatching dateComponents: Any /* DateComponents */, repeats: Bool) {
        self.dateComponents = dateComponents
        super.init(repeats: repeats)
    }

    // SKIP @bridge
    public func nextTriggerDate() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        guard let nextDate = calendar.nextDate(
            after: now,
            matching: self.dateComponents as! DateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return nil
        }
        
        if !self.repeats && nextDate <= now {
            return nil
        }
        
        return nextDate
    }
}

public final class UNLocationNotificationTrigger: UNNotificationTrigger {
    public let region: Any /* CLRegion */

    public init(region: Any /* CLRegion */, repeats: Bool) {
        self.region = region
        super.init(repeats: repeats)
    }
}

public final class UNPushNotificationTrigger: UNNotificationTrigger {
    public override init(repeats: Bool) {
        super.init(repeats: repeats)
    }
}

// SKIP @bridge
public enum UNAuthorizationStatus : Int, @unchecked Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    @available(iOS 12.0, *)
    case provisional = 3
    @available(iOS 14.0, *)
    case ephemeral = 4
}

@available(iOS 11.0, *)
public enum UNShowPreviewsSetting : Int, @unchecked Sendable {
    case always = 0
    case whenAuthenticated = 1
    case never = 2
}

public enum UNNotificationSetting : Int, @unchecked Sendable {
    case notSupported = 0
    case disabled = 1
    case enabled = 2
}

public enum UNAlertStyle : Int, @unchecked Sendable {
    case none = 0
    case banner = 1
    case alert = 2
}

// SKIP @bridge
public class UNNotificationSettings : NSObject {
    private let _authorizationStatus: UNAuthorizationStatus
    
    // SKIP @bridge
    public var authorizationStatus: UNAuthorizationStatus {
        return _authorizationStatus
    }
    
    public init(authorizationStatus: UNAuthorizationStatus) {
        self._authorizationStatus = authorizationStatus
        super.init()
    }

    /// Android has no app-wide sound setting: each channel's importance decides whether it makes a sound.
    public var soundSetting: UNNotificationSetting {
        return .enabled
    }

    @available(*, unavailable)
    public var badgeSetting: UNNotificationSetting {
        fatalError()
    }

    @available(*, unavailable)
    public var alertSetting: UNNotificationSetting {
        fatalError()
    }

    @available(*, unavailable)
    public var notificationCenterSetting: UNNotificationSetting {
        fatalError()
    }

    @available(*, unavailable)
    public var lockScreenSetting: UNNotificationSetting {
        fatalError()
    }

    @available(*, unavailable)
    public var carPlaySetting: UNNotificationSetting {
        fatalError()
    }

    @available(*, unavailable)
    public var alertStyle: UNAlertStyle {
        fatalError()
    }

    @available(iOS 11.0, *)
    @available(*, unavailable)
    public var showPreviewsSetting: UNShowPreviewsSetting {
        fatalError()
    }

    @available(iOS 12.0, *)
    @available(*, unavailable)
    public var criticalAlertSetting: UNNotificationSetting {
        fatalError()
    }

    @available(iOS 12.0, *)
    @available(*, unavailable)
    public var providesAppNotificationSettings: Bool {
        fatalError()
    }

    @available(iOS 13.0, *)
    @available(*, unavailable)
    public var announcementSetting: UNNotificationSetting {
        fatalError()
    }

    @available(iOS 15.0, *)
    @available(*, unavailable)
    public var timeSensitiveSetting: UNNotificationSetting {
        fatalError()
    }

    @available(iOS 15.0, *)
    @available(*, unavailable)
    public var scheduledDeliverySetting: UNNotificationSetting {
        fatalError()
    }

    @available(iOS 15.0, *)
    @available(*, unavailable)
    public var directMessagesSetting: UNNotificationSetting {
        fatalError()
    }
}

#if SKIP
public class NotificationWorker : Worker {
    /// The extra that carries a notification's request identifier on the intent its tap opens,
    /// which also marks the intent as a tap.
    static let identifierKey = "skip.ui.UNNotificationRequest.identifier"
    /// The extra that carries the time the notification was posted, in milliseconds.
    static let dateKey = "skip.ui.UNNotification.date"
    /// The extra that carries the token proving the intent came from the notification.
    static let tokenKey = "skip.ui.UNNotificationResponse.token"
    /// The URL of the image drawn beside the text: a visible image attachment.
    static let largeIconKey = "image_url"
    /// The URL of the image drawn in the expanded notification.
    static let bigPictureKey = "big_picture_url"
    /// The request's `categoryIdentifier`, whose actions become the notification's buttons.
    static let categoryKey = "skip.ui.UNNotificationContent.categoryIdentifier"
    /// The request's `interruptionLevel` raw value.
    static let interruptionLevelKey = "skip.ui.UNNotificationContent.interruptionLevel"
    /// The identifiers of the attachments behind the large icon and the expanded picture.
    static let largeIconIdentifierKey = "skip.ui.UNNotificationAttachment.largeIcon"
    static let bigPictureIdentifierKey = "skip.ui.UNNotificationAttachment.bigPicture"
    /// The extra that carries the identifier of the action a button stands for.
    static let actionIdentifierKey = "skip.ui.UNNotificationResponse.actionIdentifier"
    /// The extra that carries whether that action requires an unlock.
    static let authenticationRequiredKey = "skip.ui.UNNotificationAction.authenticationRequired"
    /// The extra that carries the notification's serialized `Data`, from which its response is built.
    static let dataKey = "skip.ui.UNNotification.data"
    static let senderNameKey = "skip.ui.INPerson.displayName"
    static let senderIdentifierKey = "skip.ui.INPerson.customIdentifier"
    static let senderImageKey = "skip.ui.INPerson.image"
    static let conversationIdentifierKey = "skip.ui.INSendMessageIntent.conversationIdentifier"
    /// The keys that describe the notification itself rather than its userInfo.
    static let notificationKeys: Set<String> = ["title", "body", "id", identifierKey, largeIconKey, bigPictureKey, largeIconIdentifierKey, bigPictureIdentifierKey, categoryKey, interruptionLevelKey, senderNameKey, senderIdentifierKey, senderImageKey, conversationIdentifierKey]

    public init(context: Context, params: WorkerParameters) {
        super.init(context, params)
    }
    
    public override func doWork() -> ListenableWorker.Result {
        NotificationWorker.post(getInputData(), context: getApplicationContext())
        return ListenableWorker.Result.success()
    }

    /// Posts the notification `inputData` describes.
    static func post(_ inputData: Data, context: Context) {
        // Get the data which should be displayed in the notification.
        let id = inputData.getInt("id", 0)
        let title = inputData.getString("title") ?? ""
        let body = inputData.getString("body") ?? ""
        let passive = inputData.getInt(interruptionLevelKey, UNNotificationInterruptionLevel.active.rawValue) == UNNotificationInterruptionLevel.passive.rawValue
        // A passive request replacing a notification still showing keeps its place in the shade.
        let replacedPostTime = postTimeOfActiveNotification(id: id, context: context)
        let postedMillis = (passive ? replacedPostTime : nil) ?? System.currentTimeMillis()

        let intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName())
        // SINGLE_TOP hands a running activity the tap as a new intent, where CLEAR_TOP alone would recreate it.
        intent?.addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP | android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
        
        let bundle = android.os.Bundle()
        let allData = inputData.keyValueMap
        for (key, value) in allData where !notificationKeys.contains(key) {
            if let s = value as? String {
                bundle.putString(key, s)
            } else if let b = value as? Bool {
                bundle.putBoolean(key, b)
            } else if let i = value as? Int {
                bundle.putInt(key, i)
            } else if let d = value as? Double {
                bundle.putDouble(key, d)
            } else {
                bundle.putString(key, value.toString())
            }
        }
        bundle.putLong(NotificationWorker.dateKey, postedMillis)
        bundle.putByteArray(dataKey, inputData.toByteArray())
        if let identifier = inputData.getString(NotificationWorker.identifierKey) {
            bundle.putString(NotificationWorker.identifierKey, identifier)
            bundle.putString(NotificationWorker.tokenKey, UNUserNotificationCenter.issueResponseToken(identifier: identifier, context: context))
        }
        intent?.putExtras(bundle)
        
        // Create the notification channel.
        let channelID = "tools.skip.firebase.messaging" // Match AndroidManifest.xml
        let notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! NotificationManager
        if Build.VERSION.SDK_INT >= Build.VERSION_CODES.O {
            let appName = context.getApplicationInfo().loadLabel(context.getPackageManager()).toString()
            notificationManager.createNotificationChannel(NotificationChannel(channelID, appName, NotificationManager.IMPORTANCE_DEFAULT))
        }
        
        // Build the notification.
        let builder = NotificationCompat.Builder(context, channelID)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setWhen(postedMillis)
            .setShowWhen(true)
        // A package without a launcher activity has no intent, and updating its pending intent then throws.
        if let intent {
            builder.setContentIntent(PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
        }

        let messageIntent = NotificationWorker.messageIntent(in: inputData)
        var largeIcon: android.graphics.Bitmap? = nil
        var picture: android.graphics.Bitmap? = nil
        if let messageIntent, let sender = messageIntent.sender {
            let me = Person.Builder().setName("Me").build()
            let person = sender.androidPerson(context: context)
            let style = NotificationCompat.MessagingStyle(me)
            // An image message shows no text, so the body is its own message.
            style.addMessage(NotificationCompat.MessagingStyle.Message(body, postedMillis, person))
            if let imageURL = inputData.getString(largeIconKey), let uri = NotificationAttachmentProvider.uri(forFileURL: imageURL, context: context) {
                style.addMessage(NotificationCompat.MessagingStyle.Message(body, postedMillis, person).setData("image/*", uri))
            }
            builder.setStyle(style)
            if let shortcutIdentifier = messageIntent.shortcutIdentifier {
                builder.setShortcutId(shortcutIdentifier)
            }
        } else {
            // The small icon is a status bar glyph, drawn from its alpha alone, so an attachment is the large icon instead.
            largeIcon = bitmap(at: inputData.getString(largeIconKey), context: context)
            if let largeIcon {
                builder.setLargeIcon(largeIcon)
            }
            let pictureURL = inputData.getString(bigPictureKey)
            picture = pictureURL == inputData.getString(largeIconKey) ? largeIcon : bitmap(at: pictureURL, context: context)
        }
        // Only an active replacement alerts again. The flag on the replaced notification also keeps SystemUI from
        // counting a passive update as an unread message.
        if passive || replacedPostTime == nil {
            builder.setOnlyAlertOnce(true)
        }
        // setSilent would also move a replacement to a group of its own.
        if passive && replacedPostTime == nil {
            builder.setSilent(true)
        }
        if let categoryIdentifier = inputData.getString(categoryKey), !categoryIdentifier.isEmpty,
           let category = UNUserNotificationCenter.loadCategories(context: context).first(where: { $0.identifier == categoryIdentifier }) {
            for action in category.actions {
                addAction(action, to: builder, id: id, inputData: inputData, launchIntent: intent, postedMillis: postedMillis, context: context)
            }
            if category.options.contains(.customDismissAction) {
                let dismissal = receiverIntent(actionIdentifier: UNNotificationDismissActionIdentifier, authenticationRequired: false, inputData: inputData, postedMillis: postedMillis, context: context)
                builder.setDeleteIntent(PendingIntent.getBroadcast(context, id, dismissal, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
            }
        }
        if let picture {
            let style = NotificationCompat.BigPictureStyle().bigPicture(picture)
            if largeIcon != nil {
                // Expanded, the picture replaces the thumbnail, as on iOS.
                style.bigLargeIcon(nil as android.graphics.Bitmap?)
            }
            builder.setStyle(style)
        }

        // Notification icon: must be a resource with transparent background and white logo
        // eg: to be used as a default icon must be added in the AndroidManifest.xml with the following code:
        // <meta-data
        // android:name="com.google.firebase.messaging.default_notification_icon"
        // android:resource="@drawable/ic_notification" />
        var resId = context.getResources().getIdentifier("ic_notification", "drawable", context.getPackageName())
        if resId == 0 {
            resId = context.getResources().getIdentifier("ic_launcher", "mipmap", context.getPackageName())
        }
        // createWithResource throws when the id is 0, which fails the worker and
        // the notification is never posted. A platform status icon always exists.
        // createWithResource records the package of the Context it is given, so a
        // framework id is not found in the app package. Load it from the android package.
        if resId == 0 {
            let androidContext = context.createPackageContext("android", 0)
            builder.setSmallIcon(IconCompat.createWithResource(androidContext, android.R.drawable.stat_notify_chat))
        } else {
            builder.setSmallIcon(IconCompat.createWithResource(context, resId))
        }
        
        // Display the notification.
        notificationManager.notify(id, builder.build())
    }

    /// Adds the button for `action`. A `.foreground` one opens the app as a tap does; any other reaches
    /// `NotificationActionReceiver`, which hands the response to the delegate without opening the app, as iOS does.
    private static func addAction(_ action: UNNotificationAction, to builder: NotificationCompat.Builder, id: Int, inputData: Data, launchIntent: Intent?, postedMillis: Long, context: Context) {
        let pendingIntent: PendingIntent
        if action.options.contains(.foreground) {
            guard let launchIntent else {
                return
            }
            // The action makes each button's intent distinct from the tap's and the other buttons'.
            let intent = Intent(launchIntent)
                .setAction(actionIntentPrefix + action.identifier)
                .putExtra(actionIdentifierKey, action.identifier)
            pendingIntent = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
        } else {
            let intent = receiverIntent(actionIdentifier: action.identifier, authenticationRequired: action.options.contains(.authenticationRequired), inputData: inputData, postedMillis: postedMillis, context: context)
            pendingIntent = PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
        }
        let button = NotificationCompat.Action.Builder(nil as IconCompat?, action.title, pendingIntent)
            .setAuthenticationRequired(action.options.contains(.authenticationRequired))
            .build()
        builder.addAction(button)
    }

    private static let actionIntentPrefix = "skip.ui.UNNotificationAction."

    /// The intent reaching `NotificationActionReceiver` for `actionIdentifier`; the action makes it distinct from the
    /// notification's other intents.
    private static func receiverIntent(actionIdentifier: String, authenticationRequired: Bool, inputData: Data, postedMillis: Long, context: Context) -> Intent {
        return Intent(context, NotificationActionReceiver.self.java)
            .setAction(actionIntentPrefix + actionIdentifier)
            .putExtra(dataKey, inputData.toByteArray())
            .putExtra(actionIdentifierKey, actionIdentifier)
            .putExtra(authenticationRequiredKey, authenticationRequired)
            .putExtra(dateKey, postedMillis)
    }

    /// The response to `actionIdentifier` on the notification `inputData` describes, with the request's content.
    static func response(to inputData: Data, actionIdentifier: String, postedMillis: Long) -> UNNotificationResponse {
        let content = UNMutableNotificationContent()
        content.title = inputData.getString("title") ?? ""
        content.body = inputData.getString("body") ?? ""
        content.categoryIdentifier = inputData.getString(categoryKey) ?? ""
        content.bridgedInterruptionLevel = inputData.getInt(interruptionLevelKey, UNNotificationInterruptionLevel.active.rawValue)
        var attachments: [UNNotificationAttachment] = []
        if let urlString = inputData.getString(largeIconKey), let url = URL(string: urlString) {
            attachments.append(UNNotificationAttachment(identifier: inputData.getString(largeIconIdentifierKey) ?? "", url: url, type: "public.image"))
        }
        if let urlString = inputData.getString(bigPictureKey), let url = URL(string: urlString) {
            attachments.append(UNNotificationAttachment(identifier: inputData.getString(bigPictureIdentifierKey) ?? "", url: url, type: "public.image", hidesThumbnail: true))
        }
        content.attachments = attachments
        content.messageIntent = messageIntent(in: inputData)
        var userInfo: [AnyHashable: Any] = [:]
        for (key, value) in inputData.keyValueMap where !notificationKeys.contains(key) {
            if let value {
                userInfo[key] = value
            }
        }
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: inputData.getString(identifierKey) ?? "", content: content, trigger: nil)
        let date = Date(timeIntervalSince1970: Double(postedMillis) / 1000.0)
        return UNNotificationResponse(actionIdentifier: actionIdentifier, notification: UNNotification(request: request, date: date))
    }

    static func messageIntent(in inputData: Data) -> INSendMessageIntent? {
        guard let senderName = inputData.getString(senderNameKey) else {
            return nil
        }
        var image: INImage? = nil
        if let imageURLString = inputData.getString(senderImageKey), let imageURL = URL(string: imageURLString) {
            image = INImage(url: imageURL)
        }
        let sender = INPerson(handleValue: nil, displayName: senderName, image: image, customIdentifier: inputData.getString(senderIdentifierKey), isMe: false)
        return INSendMessageIntent(recipients: nil, content: inputData.getString("body"), conversationIdentifier: inputData.getString(conversationIdentifierKey), sender: sender)
    }

    /// When the notification with `id` was posted, if it is still showing.
    private static func postTimeOfActiveNotification(id: Int, context: Context) -> Long? {
        // SKIP REPLACE: return (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications.firstOrNull { it.id == id }?.notification?.`when`
        return nil
    }

    /// Decodes the image at `urlString`, a file or content URL; nil when there is none or it can't be read.
    static func bitmap(at urlString: String?, context: Context) -> android.graphics.Bitmap? {
        guard let urlString else {
            return nil
        }
        do {
            let uri = android.net.Uri.parse(urlString)
            guard let stream = context.getContentResolver().openInputStream(uri) else {
                return nil
            }
            defer { stream.close() }
            return android.graphics.BitmapFactory.decodeStream(stream)
        } catch {
            logger.warning("ignoring an unreadable notification attachment: \(error)")
            return nil
        }
    }
}

public class NotificationAttachmentProvider : android.content.ContentProvider {
    public override init() {
        super.init()
    }

    static func uri(forFileURL fileURL: String, context: Context) -> android.net.Uri? {
        guard let path = android.net.Uri.parse(fileURL).getPath(), let file = storedFile(java.io.File(path), context: context) else {
            return nil
        }
        return android.net.Uri.Builder()
            .scheme("content")
            .authority(context.getPackageName() + ".skipui.notifications")
            .path(String(file.getPath().dropFirst(storesRoot(context).getPath().count)))
            .build()
    }

    private static func storesRoot(_ context: Context) -> java.io.File {
        return UNUserNotificationCenter.attachmentStoresDirectory(context).getCanonicalFile()
    }

    private static func storedFile(_ file: java.io.File, context: Context) -> java.io.File? {
        let resolved = file.getCanonicalFile()
        guard resolved.getPath().hasPrefix(storesRoot(context).getPath() + "/"), resolved.isFile() else {
            return nil
        }
        return resolved
    }

    public override func onCreate() -> Bool {
        return true
    }

    public override func openFile(uri: android.net.Uri, mode: String) throws -> android.os.ParcelFileDescriptor? {
        guard mode == "r", let context = getContext(), let file = NotificationAttachmentProvider.storedFile(java.io.File(NotificationAttachmentProvider.storesRoot(context), uri.getPath() ?? ""), context: context) else {
            throw java.io.FileNotFoundException(uri.toString())
        }
        return android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
    }

    public override func getType(uri: android.net.Uri) -> String? {
        return "image/*"
    }

    public override func query(uri: android.net.Uri, projection: kotlin.Array<String>?, selection: String?, selectionArgs: kotlin.Array<String>?, sortOrder: String?) -> android.database.Cursor? {
        return nil
    }

    public override func insert(uri: android.net.Uri, values: android.content.ContentValues?) -> android.net.Uri? {
        return nil
    }

    public override func update(uri: android.net.Uri, values: android.content.ContentValues?, selection: String?, selectionArgs: kotlin.Array<String>?) -> Int {
        return 0
    }

    public override func delete(uri: android.net.Uri, selection: String?, selectionArgs: kotlin.Array<String>?) -> Int {
        return 0
    }
}

/// Receives the presses on a notification's buttons that don't open the app, and hands their responses to the delegate.
public class NotificationActionReceiver : BroadcastReceiver {
    public override init() {
        super.init()
    }

    public override func onReceive(context: Context, intent: Intent) {
        guard let bytes = intent.getByteArrayExtra(NotificationWorker.dataKey), let actionIdentifier = intent.getStringExtra(NotificationWorker.actionIdentifierKey) else {
            logger.warning("ignoring a notification button without an action")
            return
        }
        // Before Android 12 a button can't ask for an unlock, so one that requires it does nothing on a locked device.
        let keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as! android.app.KeyguardManager
        if intent.getBooleanExtra(NotificationWorker.authenticationRequiredKey, true) && Build.VERSION.SDK_INT < Build.VERSION_CODES.S && keyguard.isDeviceLocked() {
            return
        }
        let data = Data.fromByteArray(bytes)
        let response = NotificationWorker.response(to: data, actionIdentifier: actionIdentifier, postedMillis: intent.getLongExtra(NotificationWorker.dateKey, System.currentTimeMillis()))
        // Each post issues a new token, which tells whether the delegate posted the notification again.
        let identifier = response.notification.request.identifier
        let preferences = context.getSharedPreferences(UNUserNotificationCenter.preferencesName, Context.MODE_PRIVATE)
        let token = preferences.getString(UNUserNotificationCenter.responseTokenKey(identifier), nil)
        let result = goAsync()
        Task {
            await UNUserNotificationCenter.current().receiveActionResponse(response)
            // iOS removes a notification once one of its actions is chosen.
            if actionIdentifier != UNNotificationDismissActionIdentifier && preferences.getString(UNUserNotificationCenter.responseTokenKey(identifier), nil) == token {
                let notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as! NotificationManager
                notificationManager.cancel(data.getInt("id", 0))
            }
            result.finish()
        }
    }
}
#endif
#endif
