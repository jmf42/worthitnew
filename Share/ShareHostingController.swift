//ShareHostingController.swift`**
import UIKit
import Social
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareHostingController)
final class ShareHostingController: SLComposeServiceViewController {
    private var mainViewModel: MainViewModel!
    private var subscriptionManager: SubscriptionManager!
    // Removed appServices

    private var hostingController: UIHostingController<AnyView>?
    private var initialURLProcessed = false

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.info("ShareHostingController viewDidLoad.", category: .shareExtension)
        view.backgroundColor = UIColor.black
        // Clear composer placeholder to avoid auto-focus incentives (contentText is read-only)
        self.placeholder = ""

        // Initialize services directly for this Share Extension instance
        let cacheManager = CacheManager.shared // CacheManager is a singleton
        let apiManager = APIManager()         // APIManager can be a new instance
        let subscriptionManager = SubscriptionManager()
        self.subscriptionManager = subscriptionManager
        self.mainViewModel = MainViewModel(
            apiManager: apiManager,
            cacheManager: cacheManager,
            subscriptionManager: subscriptionManager,
            usageTracker: UsageTracker.shared
        )
        // Do not force processing state here; processSharedURL will set .processing only if no cache is found.

        setupSwiftUIView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissNotification),
            name: .shareExtensionShouldDismissGlobal,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainAppNotification(_:)),
            name: .shareExtensionOpenMainApp,
            object: nil
        )

        if !initialURLProcessed {
             processSharedItem()
        }

        // Log share extension usage
        AnalyticsService.shared.logEvent(.shareExtensionUsed, parameters: ["source": "share_extension"])

        Task { @MainActor in
            await subscriptionManager.refreshProducts()
            await subscriptionManager.refreshEntitlement()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Logger.shared.info("ShareHostingController viewDidAppear.", category: .shareExtension)
        // SLComposeServiceViewController auto-focuses its internal text view.
        // Dismiss it so the keyboard doesn't appear or get stuck over our SwiftUI UI.
        dismissComposerKeyboard()
        if !initialURLProcessed && mainViewModel.currentVideoID == nil {
             Logger.shared.warning("ShareHostingController: Reprocessing shared item in viewDidAppear.", category: .shareExtension)
             processSharedItem()
        }
    }

    private func dismissComposerKeyboard() {
        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
        // Extra safety: slight delay to catch any re-focus from host
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.view.endEditing(true)
        }
    }

    private func setupSwiftUIView() {
        let rootView = RootView()
            .environmentObject(mainViewModel) // Pass the share extension's MainViewModel instance
            .environmentObject(subscriptionManager)

        hostingController = UIHostingController(rootView: AnyView(rootView))
        guard let hc = hostingController else { return }

        addChild(hc)
        view.addSubview(hc.view)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hc.didMove(toParent: self)
        Logger.shared.info("SwiftUI RootView hosted in Share Extension.", category: .shareExtension)
    }

    private func processSharedItem() {
        guard !initialURLProcessed else {
            Logger.shared.warning("processSharedItem called again; ignoring duplicate call.", category: .shareExtension)
            return
        }
        initialURLProcessed = true // Set the flag immediately to prevent re-entry
        Logger.shared.debug("ShareHostingController: Attempting to process shared item.", category: .shareExtension)

        guard let extensionContext = self.extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            Logger.shared.error("Failed to get extension context or input items.", category: .shareExtension)
            // setError is internal by default in MainViewModel, ensure MainViewModel.swift is in Share target
            mainViewModel.setPublicError(message: "Could not read shared content.", canRetry: false)
            return
        }

        guard !inputItems.isEmpty else {
            Logger.shared.warning("No input items found in extension context.", category: .shareExtension)
            mainViewModel.setPublicError(message: "No content was shared.", canRetry: false)
            return
        }
        
        let urlTypeIdentifier = UTType.url.identifier
        let textTypeIdentifier = UTType.plainText.identifier

        Task { // Perform async work in a Task
            for item in inputItems {
                if let attachments = item.attachments {
                    for attachment in attachments {
                        if attachment.hasItemConformingToTypeIdentifier(urlTypeIdentifier) {
                            do {
                                if let url = try await attachment.loadItem(forTypeIdentifier: urlTypeIdentifier, options: nil) as? URL {
                                    Logger.shared.info("Successfully loaded URL: \(url.absoluteString)", category: .shareExtension)
                                    await MainActor.run { mainViewModel.processSharedURL(url) }
                                    return // Process first valid URL
                                }
                            } catch {
                                Logger.shared.error("Error loading URL item: \(error.localizedDescription)", category: .shareExtension, error: error)
                            }
                        }
                    }
                    // If no URL type found, try text type
                    for attachment in attachments {
                         if attachment.hasItemConformingToTypeIdentifier(textTypeIdentifier) {
                            do {
                                if let text = try await attachment.loadItem(forTypeIdentifier: textTypeIdentifier, options: nil) as? String,
                                   let url = URLParser.firstSupportedVideoURL(in: text) {
                                    Logger.shared.info("Successfully parsed URL from text: \(url.absoluteString)", category: .shareExtension)
                                    await MainActor.run { mainViewModel.processSharedURL(url) }
                                    return // Process first valid URL found in text
                                } else {
                                     Logger.shared.warning("Shared text did not contain a parsable video URL or was not String.", category: .shareExtension)
                                }
                            } catch {
                                Logger.shared.error("Error loading text item: \(error.localizedDescription)", category: .shareExtension, error: error)
                            }
                        }
                    }
                }
            }
            // If loop completes and no URL processed
            await MainActor.run {
                 if mainViewModel.currentVideoID == nil && mainViewModel.viewState != .error {
                    Logger.shared.warning("No suitable URL or text item found after checking all attachments.", category: .shareExtension)
                    mainViewModel.setPublicError(message: "Could not find a valid video link in the shared content.", canRetry: false)
                }
            }
        }
    }
    
    @objc private func handleDismissNotification() {
        Logger.shared.info("Dismiss notification received. Closing extension.", category: .shareExtension)
        self.dismissExtension(withError: false)
    }

    @objc private func handleOpenMainAppNotification(_ notification: Notification) {
        let deepLink = (notification.object as? URL) ?? URL(string: AppConstants.subscriptionDeepLink)
        if let deepLink {
            Logger.shared.info("Open main app notification received. Attempting deep link: \(deepLink.absoluteString)", category: .shareExtension)
            self.dismissExtension(withError: false, redirectURL: deepLink)
        } else {
            Logger.shared.warning("Open main app notification received without a valid URL. Dismissing extension only.", category: .shareExtension)
            self.dismissExtension(withError: false)
        }
    }

    private func dismissExtension(withError: Bool, redirectURL: URL? = nil) {
        // Release the general share-extension lock acquired at launch
        FileLock.release("com.worthitai.share.active.lock")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let finish: () -> Void = {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }

            if withError {
                self.extensionContext?.cancelRequest(withError: NSError(domain: AppConstants.bundleID, code: 1, userInfo: [NSLocalizedDescriptionKey: "Share extension cancelled with error."]))
                return
            }

            guard let url = redirectURL else {
                finish()
                return
            }

            self.extensionContext?.open(url) { success in
                if success {
                    Logger.shared.info("Successfully handed off to WorthIt app for subscription.", category: .shareExtension)
                    finish()
                } else {
                    Logger.shared.error("Failed to open WorthIt app via deep link from share extension.", category: .shareExtension)
                    NotificationCenter.default.post(name: .shareExtensionOpenMainAppFailed, object: nil)
                }
            }
        }
    }

    // MARK: - SLComposeServiceViewController required overrides
    override func isContentValid() -> Bool {
        // We validate inputs internally when processing the shared item.
        return true
    }

    override func didSelectPost() {
        // Finish and dismiss the extension when the user taps Post/Done.
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // We don't present additional configuration items.
        return []
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        Logger.shared.info("ShareHostingController deinitialized.", category: .shareExtension)
    }
}
