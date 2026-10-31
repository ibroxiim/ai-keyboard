import ImageIO
import SwiftUI
import UIKit

/// A looping GIF. Frames are decoded one at a time by ImageIO (`CGAnimateImageDataWithBlock`), so ten previews on
/// the strip cost the memory of ten frames, not ten whole GIFs — the keyboard extension has little to spare.
struct AnimatedGifView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> GifImageView { GifImageView(frame: .zero) }

    func updateUIView(_ view: GifImageView, context: Context) { view.load(url) }

    static func dismantleUIView(_ view: GifImageView, coordinator: ()) { view.stop() }
}

final class GifImageView: UIImageView {
    private var current: URL?
    private var task: Task<Void, Never>?
    private var stopFlag = false
    private static let cache = NSCache<NSURL, NSData>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = UIColor.secondarySystemFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(_ url: URL) {
        guard url != current else { return }
        current = url
        stop()
        image = nil
        if let cached = Self.cache.object(forKey: url as NSURL) {
            animate(cached as Data)
            return
        }
        task = Task { [weak self] in
            guard let data = try? await Klipy.download(url), !Task.isCancelled else { return }
            Self.cache.setObject(data as NSData, forKey: url as NSURL)
            await MainActor.run { self?.animate(data) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        stopFlag = true
    }

    private func animate(_ data: Data) {
        stopFlag = false
        // The block runs on the main thread for every frame until `stop` is set.
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, cgImage, stop in
            guard let self, !self.stopFlag else {
                stop.pointee = true
                return
            }
            self.image = UIImage(cgImage: cgImage)
        }
    }
}
