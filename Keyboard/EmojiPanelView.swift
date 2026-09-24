import SwiftUI
import UIKit

struct EmojiRepresentable: UIViewRepresentable {
    let model: KeyboardModel

    func makeUIView(context: Context) -> EmojiPanelView { EmojiPanelView(model: model) }

    func updateUIView(_ view: EmojiPanelView, context: Context) {}
}

/// Tarjimon's own emoji panel (tried switching to the system emoji keyboard instead; iOS only
/// allows "next keyboard", which depends on the user's keyboard order — the in-keyboard panel won).
/// Laid out like the system panel: a horizontally scrolling 5-row grid, the category name on top,
/// and ABC · categories · ⌫ at the bottom. UIKit, for the same no-lag reason as `KeysUIView`.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private let model: KeyboardModel
    private let sections: [EmojiCategory]
    private let collection: UICollectionView
    private let titleLabel = UILabel()
    private let bar = UIStackView()
    private var categoryButtons: [UIButton] = []
    private var repeatTimer: Timer?

    private static let rows: CGFloat = 5
    private static let cellSize = CGSize(width: 40, height: 32)
    private static let titleHeight: CGFloat = 18
    private static let barHeight: CGFloat = 38

    init(model: KeyboardModel) {
        self.model = model
        let recents = EmojiRecents.all
        sections = (recents.isEmpty ? [] : [EmojiCategory(title: "Ko'p ishlatilgan", symbol: "clock", emojis: recents)])
            + EmojiData.categories

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = Self.cellSize
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 14)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        addSubview(collection)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        addSubview(titleLabel)

        bar.axis = .horizontal
        bar.distribution = .fillEqually
        bar.alignment = .fill
        addSubview(bar)
        buildBar()
        updateCurrentSection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridHeight = Self.cellSize.height * Self.rows
        titleLabel.frame = CGRect(x: 12, y: 2, width: bounds.width - 24, height: Self.titleHeight)
        collection.frame = CGRect(x: 0, y: Self.titleHeight + 2, width: bounds.width, height: gridHeight)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight - 2, width: bounds.width - 8, height: Self.barHeight)
    }

    private func buildBar() {
        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        abc.tintColor = .label
        abc.addAction(UIAction { [weak self] _ in
            self?.model.keyDown()
            self?.model.showsEmoji = false
        }, for: .touchUpInside)
        bar.addArrangedSubview(abc)

        for (index, section) in sections.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: section.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.jump(to: index) }, for: .touchUpInside)
            categoryButtons.append(button)
            bar.addArrangedSubview(button)
        }

        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        delete.tintColor = .label
        delete.addAction(UIAction { [weak self] _ in self?.startDeleting() }, for: .touchDown)
        delete.addAction(UIAction { [weak self] _ in self?.stopDeleting() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        bar.addArrangedSubview(delete)
    }

    private func jump(to index: Int) {
        model.keyDown()
        collection.scrollToItem(at: IndexPath(item: 0, section: index), at: .left, animated: false)
        // scrollToItem centers the first column under the section inset; pin it to the left edge.
        collection.layoutIfNeeded()
        if let attributes = collection.layoutAttributesForItem(at: IndexPath(item: 0, section: index)) {
            let maxX = max(0, collection.contentSize.width - collection.bounds.width)
            collection.contentOffset.x = min(maxX, max(0, attributes.frame.minX - 4))
        }
        updateCurrentSection()
    }

    private func startDeleting() {
        model.keyDown()
        model.backspace()
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.backspace() }
                }
            }
        }
    }

    private func stopDeleting() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    /// The section whose items are under the left edge names the title and lights its category button.
    private func updateCurrentSection() {
        let probe = CGPoint(x: collection.contentOffset.x + 20, y: Self.cellSize.height / 2)
        let current = collection.indexPathForItem(at: probe)?.section
            ?? collection.indexPathsForVisibleItems.map(\.section).min()
            ?? 0
        titleLabel.text = sections[current].title.uppercased()
        for (index, button) in categoryButtons.enumerated() {
            button.tintColor = index == current ? .label : .secondaryLabel
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCurrentSection()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emojis[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        model.insertEmoji(sections[indexPath.section].emojis[indexPath.item])
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let id = "EmojiCell"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 29)
        label.textAlignment = .center
        contentView.addSubview(label)
        selectedBackgroundView = UIView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    override var isHighlighted: Bool {
        didSet { label.transform = isHighlighted ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity }
    }
}
