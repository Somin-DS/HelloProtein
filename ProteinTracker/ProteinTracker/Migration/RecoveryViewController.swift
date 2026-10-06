import UIKit
import MigrationCore

/// Shown when the start gate cannot hand over a verified store. It names the
/// problem and offers a retry when one can help. Every sentence is tied to a
/// flag of the recovery state: the original is called untouched only when
/// `originalPreserved` says so, a backup is mentioned only when
/// `backupAvailable`, and the retry button and its hint appear together only
/// when `canRetry` and a retry action exist. There is deliberately no reset or
/// delete action.
final class RecoveryViewController: UIViewController {
    enum Presentation {
        case recovery(RecoveryState)
        case unsupportedOS
    }

    /// Pure text decisions so they can be unit tested without a window.
    struct Content: Equatable {
        let title: String
        let body: String
        let retryHint: String?
        let detail: String

        init(presentation: Presentation, hasRetryAction: Bool, debugDetail: Bool) {
            switch presentation {
            case .unsupportedOS:
                title = RenewalStrings.text("recovery_title")
                body = RenewalStrings.text("recovery_unsupported_os")
                retryHint = nil
                detail = ""
            case .recovery(let state):
                title = RenewalStrings.text("recovery_title")
                var lines = [RenewalStrings.text("recovery_kind_\(state.kind.rawValue)")]
                if state.originalPreserved { lines.append(RenewalStrings.text("recovery_preserved")) }
                if state.backupAvailable { lines.append(RenewalStrings.text("recovery_backup_available")) }
                body = lines.joined(separator: "\n\n")
                retryHint = state.canRetry && hasRetryAction ? RenewalStrings.text("recovery_retry_hint") : nil
                // The raw detail can contain legacy IDs and stored values; keep it
                // out of release screenshots and show only the non-identifying code.
                detail = debugDetail ? "\(state.kind.rawValue): \(state.detail)" : state.kind.rawValue
            }
        }

        var showsRetry: Bool { retryHint != nil }
    }

    private let presentation: Presentation
    private let retry: (() -> Void)?
    private var retryAction: (() -> Void)?
    private var retryButton: UIButton?

    var content: Content {
        #if DEBUG
        let debugDetail = true
        #else
        let debugDetail = false
        #endif
        return Content(presentation: presentation, hasRetryAction: retry != nil, debugDetail: debugDetail)
    }

    init(presentation: Presentation, retry: (() -> Void)?) {
        self.presentation = presentation
        self.retry = retry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let content = self.content

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.text = content.title
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = "recovery.title"

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .body)
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 0
        body.text = content.body
        body.accessibilityIdentifier = "recovery.body"

        let stack = UIStackView(arrangedSubviews: [title, body])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let hint = content.retryHint, let retry {
            let hintLabel = UILabel()
            hintLabel.font = .preferredFont(forTextStyle: .body)
            hintLabel.adjustsFontForContentSizeCategory = true
            hintLabel.numberOfLines = 0
            hintLabel.text = hint
            hintLabel.accessibilityIdentifier = "recovery.retryHint"
            stack.addArrangedSubview(hintLabel)

            let button = UIButton(type: .system)
            button.setTitle(RenewalStrings.text("recovery_retry"), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.accessibilityIdentifier = "recovery.retry"
            retryAction = retry
            button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
            retryButton = button
            stack.addArrangedSubview(button)
        }

        let detail = UILabel()
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.text = content.detail
        detail.accessibilityIdentifier = "recovery.detail"
        stack.addArrangedSubview(detail)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    /// The retry replaces this screen through the start gate; a second tap
    /// before that happens must not run the gate twice.
    @objc func retryTapped() {
        guard let action = retryAction else { return }
        retryAction = nil
        retryButton?.isEnabled = false
        action()
    }

    /// Exposed for tests: whether a tap would still run the retry.
    var isRetryAvailable: Bool { retryAction != nil && (retryButton?.isEnabled ?? false) }
}
