// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.content.Context
import android.content.Intent
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
#endif

// SKIP @bridge
public final class INImage {
    let url: URL

    // SKIP @bridge
    public init(url: URL) {
        self.url = url
    }

    // SKIP @bridge
    public var bridgedURL: URL {
        return url
    }
}

public enum INPersonHandleType : Int {
    case unknown = 0
    case emailAddress = 1
    case phoneNumber = 2
}

public final class INPersonHandle {
    public let value: String?
    public let type: INPersonHandleType

    public init(value: String?, type: INPersonHandleType) {
        self.value = value
        self.type = type
    }
}

public enum INPersonSuggestionType : Int {
    case none = 0
    case socialProfile = 1
    case instantMessageAddress = 2
}

// SKIP @bridge
public final class INPerson {
    public let personHandle: INPersonHandle?
    public let nameComponents: Any? /* PersonNameComponents? */
    // SKIP @bridge
    public let displayName: String
    // SKIP @bridge
    public let image: INImage?
    public let contactIdentifier: String?
    // SKIP @bridge
    public let customIdentifier: String?
    // SKIP @bridge
    public let isMe: Bool

    public init(personHandle: INPersonHandle, nameComponents: Any? /* PersonNameComponents? */, displayName: String?, image: INImage?, contactIdentifier: String?, customIdentifier: String?, isMe: Bool, suggestionType: INPersonSuggestionType) {
        self.personHandle = personHandle
        self.nameComponents = nameComponents
        self.displayName = displayName ?? personHandle.value ?? ""
        self.image = image
        self.contactIdentifier = contactIdentifier
        self.customIdentifier = customIdentifier
        self.isMe = isMe
    }

    // SKIP @bridge
    public convenience init(handleValue: String?, displayName: String?, image: INImage?, customIdentifier: String?, isMe: Bool) {
        self.init(personHandle: INPersonHandle(value: handleValue, type: INPersonHandleType.unknown), nameComponents: nil, displayName: displayName, image: image, contactIdentifier: nil, customIdentifier: customIdentifier, isMe: isMe, suggestionType: INPersonSuggestionType.none)
    }

    // SKIP @bridge
    public var bridgedHandleValue: String? {
        return personHandle?.value
    }

    #if SKIP
    func androidPerson(context: Context) -> Person {
        let builder = Person.Builder().setName(displayName).setKey(customIdentifier)
        if let bitmap = NotificationWorker.bitmap(at: image?.url.absoluteString, context: context) {
            builder.setIcon(IconCompat.createWithBitmap(bitmap))
        }
        return builder.build()
    }
    #endif
}

// SKIP @bridge
public class INIntent {
}

public enum INOutgoingMessageType : Int {
    case unknown = 0
    case outgoingMessageText = 1
    case outgoingMessageAudio = 2
}

// SKIP @bridge
public final class INSendMessageIntent : INIntent, UNNotificationContentProviding {
    // SKIP @bridge
    public let recipients: [INPerson]?
    public let outgoingMessageType: INOutgoingMessageType
    // SKIP @bridge
    public let content: String?
    public let speakableGroupName: Any? /* INSpeakableString? */
    // SKIP @bridge
    public let conversationIdentifier: String?
    public let serviceName: String?
    // SKIP @bridge
    public let sender: INPerson?
    public let attachments: [Any]? /* [INSendMessageAttachment]? */

    public init(recipients: [INPerson]?, outgoingMessageType: INOutgoingMessageType, content: String?, speakableGroupName: Any? /* INSpeakableString? */, conversationIdentifier: String?, serviceName: String?, sender: INPerson?, attachments: [Any]? /* [INSendMessageAttachment]? */) {
        self.recipients = recipients
        self.outgoingMessageType = outgoingMessageType
        self.content = content
        self.speakableGroupName = speakableGroupName
        self.conversationIdentifier = conversationIdentifier
        self.serviceName = serviceName
        self.sender = sender
        self.attachments = attachments
    }

    // SKIP @bridge
    public convenience init(recipients: [INPerson]?, content: String?, conversationIdentifier: String?, sender: INPerson?) {
        self.init(recipients: recipients, outgoingMessageType: INOutgoingMessageType.outgoingMessageText, content: content, speakableGroupName: nil, conversationIdentifier: conversationIdentifier, serviceName: nil, sender: sender, attachments: nil)
    }

    var shortcutIdentifier: String? {
        return conversationIdentifier ?? sender?.customIdentifier
    }

    #if SKIP
    func pushShortcut(context: Context) {
        guard let sender, let shortcutIdentifier else {
            return
        }
        let launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName())
        let intent = Intent(Intent.ACTION_VIEW)
        intent.setComponent(launchIntent?.getComponent())
        if let conversationIdentifier, let url = URL(string: conversationIdentifier), url.scheme != nil {
            intent.setData(android.net.Uri.parse(conversationIdentifier))
        }
        let builder = ShortcutInfoCompat.Builder(context, shortcutIdentifier)
            .setShortLabel(sender.displayName)
            .setLongLived(true)
            .setPerson(sender.androidPerson(context: context))
            .setIntent(intent)
        if let bitmap = NotificationWorker.bitmap(at: sender.image?.url.absoluteString, context: context) {
            builder.setIcon(IconCompat.createWithAdaptiveBitmap(INSendMessageIntent.adaptiveBitmap(bitmap)))
        }
        ShortcutManagerCompat.pushDynamicShortcut(context, builder.build())
    }

    private static func adaptiveBitmap(_ bitmap: android.graphics.Bitmap) -> android.graphics.Bitmap {
        let side = max(bitmap.getWidth(), bitmap.getHeight())
        let canvasSide = side * 3 / 2
        let padded = android.graphics.Bitmap.createBitmap(canvasSide, canvasSide, android.graphics.Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(padded).drawBitmap(bitmap, Float((canvasSide - bitmap.getWidth()) / 2), Float((canvasSide - bitmap.getHeight()) / 2), nil)
        return padded
    }
    #endif
}

public enum INInteractionDirection : Int {
    case unspecified = 0
    case outgoing = 1
    case incoming = 2
}

// SKIP @bridge
public final class INInteraction {
    public let intent: INIntent
    public let intentResponse: Any? /* INIntentResponse? */
    public var direction: INInteractionDirection = INInteractionDirection.unspecified

    public init(intent: INIntent, response: Any? /* INIntentResponse? */) {
        self.intent = intent
        self.intentResponse = response
    }

    // SKIP @bridge
    public convenience init(intent: INIntent) {
        self.init(intent: intent, response: nil)
    }

    // SKIP @bridge
    public func donate() async throws {
        #if SKIP
        (intent as? INSendMessageIntent)?.pushShortcut(context: ProcessInfo.processInfo.androidContext)
        #endif
    }
}
#endif
