import UIKit
import MigrationCore

/// Shown when the start gate cannot hand over a verified store. It names the
/// problem, states that the original is untouched, and offers a retry. There
/// is deliberately no reset or delete action.
final class RecoveryViewController: UIViewController {
    enum Presentation {
        case recovery(RecoveryState)
        case unsupportedOS
    }

    private let presentation: Presentation
    private let retry: (() -> Void)?
    private var retryAction: (() -> Void)?

    @objc private func retryTapped() { retryAction?() }

    init(presentation: Presentation, retry: (() -> Void)?) {
        self.presentation = presentation
        self.retry = retry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.text = RenewalStrings.text("recovery_title")
        title.accessibilityTraits = .header

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .body)
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 0
        body.text = bodyText()

        let detail = UILabel()
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.text = detailText()

        let stack = UIStackView(arrangedSubviews: [title, body, detail])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if case .recovery(let state) = presentation, state.canRetry, let retry {
            let button = UIButton(type: .system)
            button.setTitle(RenewalStrings.text("recovery_retry"), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            retryAction = retry
            button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

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

    private func bodyText() -> String {
        switch presentation {
        case .unsupportedOS:
            return RenewalStrings.text("recovery_unsupported_os")
        case .recovery(let state):
            var lines = [RenewalStrings.text("recovery_kind_\(state.kind.rawValue)")]
            if state.originalPreserved { lines.append(RenewalStrings.text("recovery_preserved")) }
            if state.backupAvailable { lines.append(RenewalStrings.text("recovery_backup_available")) }
            return lines.joined(separator: "\n\n")
        }
    }

    private func detailText() -> String {
        switch presentation {
        case .unsupportedOS: return ""
        case .recovery(let state):
            // The raw detail can contain legacy IDs and stored values; keep it
            // out of release screenshots and show only the non-identifying code.
            #if DEBUG
            return "\(state.kind.rawValue): \(state.detail)"
            #else
            return state.kind.rawValue
            #endif
        }
    }
}
