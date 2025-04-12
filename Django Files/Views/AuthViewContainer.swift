import SwiftUI
import SwiftData
//import UIKit

public struct AuthViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    @Query private var items: [DjangoFilesSession]
    
    @State private var isAuthViewLoading: Bool = true
    
    var viewingSettings: Binding<Bool>
    let selectedServer: DjangoFilesSession
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    var showingEditor: Binding<Bool>
    var needsRefresh: Binding<Bool>
    
    @State private var authController: AuthController = AuthController()
    
    public var body: some View {
        if viewingSettings.wrappedValue {
            SessionSelector(session: selectedServer, viewingSelect: viewingSettings)
                .onAppear(){
                    columnVisibility.wrappedValue = .automatic
                }
        }
        else if selectedServer.url != "" {
            ZStack {
                AuthViewControllerWrapper(
                    authController: authController,
                    server: selectedServer,
                    isLoading: $isAuthViewLoading,
                    viewingSettings: viewingSettings,
                    columnVisibility: columnVisibility,
                    needsRefresh: needsRefresh,
                    modelContext: modelContext,
                    presentationMode: presentationMode,
                    onDismiss: { dismiss() }
                )
            }
            .ignoresSafeArea(.all)
            .background(Color.djangoFilesBackground)
        }
        else {
            Text("Loading...")
                .onAppear(){
                    columnVisibility.wrappedValue = .all
                }
        }
    }
}

struct AuthViewControllerWrapper: UIViewControllerRepresentable {
    var authController: AuthController
    var server: DjangoFilesSession
    @Binding var isLoading: Bool
    var viewingSettings: Binding<Bool>
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    var needsRefresh: Binding<Bool>
    var modelContext: ModelContext
    var presentationMode: Binding<PresentationMode>
    var onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> AuthUIViewController {
        let controller = AuthUIViewController(
            authController: authController,
            server: server,
            isLoading: $isLoading,
            viewingSettings: viewingSettings,
            columnVisibility: columnVisibility,
            needsRefresh: needsRefresh,
            modelContext: modelContext,
            presentationMode: presentationMode,
            onDismiss: onDismiss
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AuthUIViewController, context: Context) {
        // Update if needed
    }
}

class AuthUIViewController: UIViewController {
    private var authController: AuthController
    private var server: DjangoFilesSession
    private var isLoading: Binding<Bool>
    private var viewingSettings: Binding<Bool>
    private var columnVisibility: Binding<NavigationSplitViewVisibility>
    private var needsRefresh: Binding<Bool>
    private var modelContext: ModelContext
    private var presentationMode: Binding<PresentationMode>
    private var onDismiss: () -> Void
    private var loadingView: UIActivityIndicatorView?
    
    init(authController: AuthController, 
         server: DjangoFilesSession,
         isLoading: Binding<Bool>,
         viewingSettings: Binding<Bool>,
         columnVisibility: Binding<NavigationSplitViewVisibility>,
         needsRefresh: Binding<Bool>,
         modelContext: ModelContext,
         presentationMode: Binding<PresentationMode>,
         onDismiss: @escaping () -> Void) {
        self.authController = authController
        self.server = server
        self.isLoading = isLoading
        self.viewingSettings = viewingSettings
        self.columnVisibility = columnVisibility
        self.needsRefresh = needsRefresh
        self.modelContext = modelContext
        self.presentationMode = presentationMode
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupCallbacks()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Ensure navigation bar is hidden only for this view controller
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Restore the visibility of the navigation bar when this view disappears
        if let navigationController = self.navigationController {
            // Only unhide if we're being dismissed, not if a child controller is being presented
            if isBeingDismissed || navigationController.viewControllers.count <= 1 || navigationController.viewControllers.last != self {
                print("dismiss event")
                print(self.server.auth)
                if !self.server.auth {
                    navigationController.setNavigationBarHidden(false, animated: animated)
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Configure WebView with server URL
        if let url = URL(string: server.url), 
           authController.url?.absoluteString != server.url {
            authController.url = url
            authController.applyCookies(from: server)
            authController.reset()
        }
        
        // Update column visibility
        DispatchQueue.main.async {
            self.columnVisibility.wrappedValue = .detailOnly
        }
    }
    
    private func setupViews() {
        // Configure WebView
        authController.webView.frame = view.bounds
        authController.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = UIColor.systemGray6
        view.addSubview(authController.webView)
        
        // Setup loading indicator
        let loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = view.center
        loadingIndicator.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        self.loadingView = loadingIndicator
        
        if isLoading.wrappedValue {
            loadingIndicator.startAnimating()
        }
        
        // Initial setup for the web view
        if needsRefresh.wrappedValue {
            authController.reset()
            needsRefresh.wrappedValue = false
        }
    }
    
    private func setupCallbacks() {
        // Set callbacks for auth controller
        authController.onStartedLoadingAction = { [weak self] in
            DispatchQueue.main.async {
                self?.isLoading.wrappedValue = true
                self?.loadingView?.startAnimating()
            }
        }
        
        authController.onLoadedAction = { [weak self] in
            DispatchQueue.main.async {
                self?.isLoading.wrappedValue = false
                self?.loadingView?.stopAnimating()
            }
        }
        
        authController.onCancelledAction = { [weak self] in
            DispatchQueue.main.async {
                self?.isLoading.wrappedValue = false
                self?.loadingView?.stopAnimating()
                self?.onDismiss()
            }
        }
        
        authController.onSchemeRedirectAction = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading.wrappedValue = false
                self.loadingView?.stopAnimating()
                
                guard let resolve = self.authController.schemeURL else { return }
                
                switch resolve {
                case "serverlist":
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                    self.columnVisibility.wrappedValue = .all
                    
                case "serversettings":
                    self.viewingSettings.wrappedValue = true
                    
                case "logout":
                    self.server.auth = false
                    self.columnVisibility.wrappedValue = .automatic
                    self.modelContext.insert(self.server)
                    do {
                        try self.modelContext.save()
                    } catch {
                        print("Error saving session: \(error)")
                    }
                    self.presentationMode.wrappedValue.dismiss()
                    
                default:
                    break
                }
            }
        }
    }
}

struct LoadingView: View {
    @State private var isLoading = false
    @State private var firstAppear = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.8)
            .stroke(Color.launchScreenBackground, lineWidth: 5)
            .rotationEffect(Angle(degrees: isLoading ? 360 : 0))
            .opacity(firstAppear ? 1 : 0)
            .onAppear(){
                DispatchQueue.main.async {
                    if isLoading == false{
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)){
                            isLoading.toggle()
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.25)){
                        firstAppear = true
                    }
                }
            }
            .onDisappear(){
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)){
                        firstAppear = true
                    }
                }
            }
    }
} 
