import SwiftUI

class ResponseWindow: NSWindow {
    private let responseViewModel: ResponseViewModel
    private var hostingController: NSHostingController<ResponseView>?

    init(title: String, viewModel: ResponseViewModel) {
        self.responseViewModel = viewModel

        let controller = NSHostingController(
            rootView: ResponseView(viewModel: viewModel)
        )
        self.hostingController = controller

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = title
        self.minSize = NSSize(width: 400, height: 300)
        self.isReleasedWhenClosed = false

        self.contentViewController = controller
        controller.rootView = ResponseView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.close()
            }
        )
        self.center()
        self.setFrameAutosaveName("ResponseWindow")
    }

    convenience init(
        title: String,
        content: String,
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        conversationImages: [Data] = [],
        baseSystemPrompt: String? = nil,
        reviewContext: ResponseReviewContext? = nil,
        responsePresentation: CommandResponsePresentation = .standard
    ) {
        let viewModel = ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option,
            provider: provider,
            conversationImages: conversationImages,
            baseSystemPrompt: baseSystemPrompt,
            reviewContext: reviewContext,
            responsePresentation: responsePresentation
        )

        self.init(title: title, viewModel: viewModel)
    }

    override func close() {
        responseViewModel.markClosed()
        WindowManager.shared.removeResponseWindow(self)
        super.close()
    }
}
