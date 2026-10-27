import SwiftUI
import UIKit

enum KeyboardMetrics {
    static let statusHeight: CGFloat = 34
    static let chipsHeight: CGFloat = 58
    static let barHeight: CGFloat = 6 + statusHeight + 6 + chipsHeight + 4
    /// Status row only — about the height of the system keyboard's prediction bar.
    static let compactBarHeight: CGFloat = 6 + statusHeight + 6
    static let keyHeight: CGFloat = 44
    static let rowGap: CGFloat = 11
    static let keyGap: CGFloat = 6
    static let sideInset: CGFloat = 3
    static let keysTopInset: CGFloat = 8
    static let keysHeight: CGFloat = keysTopInset + keyHeight * 4 + rowGap * 3 + 4
    static func totalHeight(barExpanded: Bool) -> CGFloat {
        (barExpanded ? barHeight : compactBarHeight) + keysHeight
    }
}

enum KeyboardColors {
    static let keyUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white }
    static let functionKeyUI = UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    }
    static let pressedUI = UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }
    static let key = Color(keyUI)
    static let shadow = Color.black.opacity(0.3)
}

struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            SuggestionBar(model: model)
                .frame(height: model.barExpanded ? KeyboardMetrics.barHeight : KeyboardMetrics.compactBarHeight)
            if model.showsDetails, let context = model.context {
                ContextDetails(context: context) { model.showsDetails = false }
                    .frame(height: KeyboardMetrics.keysHeight)
            } else if model.showsVariantList, !model.chips.isEmpty {
                VariantList(
                    title: model.variants.isEmpty ? "Tayyor javoblar" : "✨ Variantlar",
                    suggestions: model.chips, focus: model.variantListFocus,
                    original: model.variants.isEmpty ? nil : model.originalDraft, picked: model.pickedVariantID,
                    pick: { model.pick($0) }, restore: model.restoreOriginal, close: model.closeVariantList)
                    .frame(height: KeyboardMetrics.keysHeight)
            } else if model.showsEmoji {
                EmojiRepresentable(model: model)
                    .frame(height: KeyboardMetrics.keysHeight)
            } else {
                let emojiKey = model.state.emojiKey ?? false
                KeysRepresentable(model: model, config: KeysUIView.Config(
                    layer: model.layer, shift: model.shift,
                    // With the emoji key there is no way back from Cyrillic, so it implies Latin.
                    alphabet: emojiKey ? .latin : model.alphabet,
                    showsGlobe: model.showsGlobe, emojiKey: emojiKey))
                    .frame(height: KeyboardMetrics.keysHeight)
            }
        }
    }
}

// MARK: - Suggestion bar

struct SuggestionBar: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                if !model.chips.isEmpty { expandButton }
                micButton
                magicButton
            }
            .frame(height: KeyboardMetrics.statusHeight)

            if model.barExpanded { chipRow }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, model.barExpanded ? 4 : 6)
    }

    private var chipRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if model.chips.isEmpty && model.isAnalyzing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Javoblar tayyorlanmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .frame(maxHeight: .infinity)
                    } else if model.chips.isEmpty {
                        if model.hasFullAccess && model.showsTargetPicker {
                            ForEach(model.targets) { target in
                                TargetChip(target: target, isSelected: model.isSelected(target)) {
                                    model.select(target)
                                }
                            }
                        }
                    } else {
                        if !model.variants.isEmpty, let draft = model.originalDraft {
                            OriginalChip(draft: draft, isSelected: model.pickedVariantID == nil, restore: model.restoreOriginal)
                        }
                        ForEach(model.chips) { suggestion in
                            Chip(
                                suggestion: suggestion, isSelected: model.pickedVariantID == suggestion.id,
                                pick: { model.pick(suggestion) }, expand: { model.openVariantList(focus: suggestion) })
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollClipDisabled()
            .modifier(NoScrollEdgeEffect())
            .frame(height: KeyboardMetrics.chipsHeight)
    }

    @ViewBuilder
    private var status: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if model.voiceStatus != .idle {
            voiceStatusView
        } else if !model.variants.isEmpty {
            // "Biroz qisqaroq" — asked of the variants with one tap, the way it would be asked of a chat model.
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Text("✨").font(.system(size: 13))
                        ForEach(RewriteTweak.allCases, id: \.self) { tweak in
                            TweakPill(tweak: tweak, isOn: model.tweaks.contains(tweak)) { model.refine(tweak) }
                        }
                    }
                }
                .scrollClipDisabled()
                .modifier(NoScrollEdgeEffect())
                closeButton { model.dismissVariants() }
            }
        } else if let context = model.context {
            // The translation arrives before the suggestions; show it as soon as it is there.
            HStack(spacing: 6) {
                Button { model.toggleDetails() } label: {
                    Text(contextLine(context))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                closeButton { model.dismissContext() }
            }
        } else if model.isAnalyzing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Suhbat o'qilmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        } else if let error = model.recentError {
            Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        } else if !model.hasFullAccess {
            Text("Full Access o'chiq — AI ishlamaydi, faqat yozish mumkin")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
        } else {
            // Collapsed target: one pill instead of a whole chip row; tap to pick another friend/language.
            let language = model.state.language
            let friend = model.state.activeFriendProfile.map { " · \($0.name)" } ?? ""
            HStack(spacing: 8) {
                Button(action: model.toggleTargetPicker) {
                    HStack(spacing: 5) {
                        Text("✨ → \(Languages.flag(language)) \(language)\(friend)")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: model.showsTargetPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(KeyboardColors.key))
                }
                .buttonStyle(.plain)
                if model.clipboardOffered {
                    // Something was copied since the keyboard last looked: a message in the chat, most likely.
                    Button(action: model.translateClipboard) {
                        Text("📋 Tarjima")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Capsule().fill(KeyboardColors.key))
                    }
                    .buttonStyle(.plain)
                } else if model.showsTargetPicker {
                    Text("kimga yozyapsiz?").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                } else if let note = model.expiryNote {
                    Text(note).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
    }

    private func contextLine(_ context: ChatAnalysis) -> String {
        // Several unanswered messages come back one per line; the bar has a single line.
        let meaning = (context.lastIncomingUz.isEmpty ? context.summaryUz : context.lastIncomingUz)
            .split(whereSeparator: \.isNewline).joined(separator: " · ")
        return "💬 " + (context.partner.isEmpty ? meaning : "\(context.partner): \(meaning)")
    }

    private var magicButton: some View {
        Button(action: model.magic) {
            ZStack {
                if model.isRewriting {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 30)
            .background(Capsule().fill(Color.accentColor))
        }
        .disabled(model.isRewriting)
    }

    /// 🎤: starts dictation, stops it while it records, or puts a finished result in.
    private var micButton: some View {
        let status = model.voiceStatus
        let busy = status == .opening || status == .transcribing
        return Button(action: model.tapMic) {
            ZStack {
                switch status {
                case .recording:
                    Image(systemName: "stop.fill").foregroundStyle(.white)
                case .opening, .transcribing:
                    ProgressView().controlSize(.small)
                case .ready:
                    Image(systemName: "text.insert").foregroundStyle(.white)
                default:
                    Image(systemName: "mic.fill").foregroundStyle(.primary)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 36, height: 30)
            .background(Capsule().fill(micFill(status)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Ovozdan matn")
    }

    private func micFill(_ status: VoiceStatus) -> Color {
        switch status {
        case .recording: .red
        case .ready: .accentColor
        default: KeyboardColors.key
        }
    }

    @ViewBuilder
    private var voiceStatusView: some View {
        switch model.voiceStatus {
        case .opening:
            Text("Ilova ochilmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .openFailed:
            Text("Ilova ochilmadi — AI Keyboard ilovasini oching → Gapirish")
                .font(.system(size: 12)).foregroundStyle(.orange).lineLimit(2)
        case .recording:
            Text("🔴 Yozilmoqda — tugagach ⏹ ni bosing").font(.system(size: 13, weight: .medium)).lineLimit(2)
        case .transcribing:
            Text("Matn yozilmoqda…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .ready:
            Text("🎤 Ovozli matn tayyor — qo'yish").font(.system(size: 13, weight: .medium)).lineLimit(2)
        case .failed(let message):
            Text(message).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
        case .idle:
            EmptyView()
        }
    }

    /// Opens every reply in full — a chip shows two lines of it.
    private var expandButton: some View {
        Button {
            if model.showsVariantList { model.closeVariantList() } else { model.openVariantList() }
        } label: {
            Image(systemName: model.showsVariantList
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 30)
                .background(Capsule().fill(KeyboardColors.key))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Javoblarni to'liq ko'rish")
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}

struct Chip: View {
    let suggestion: Suggestion
    /// The reply that is in the field right now.
    let isSelected: Bool
    let pick: () -> Void
    /// Long press: the whole reply in the full-size list, scrolled to this one. A plain tap and a long press are
    /// separate gestures here — a `Button` would also fire its tap when the long press is released.
    let expand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(suggestion.text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(suggestion.uz)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 10)
        .frame(maxWidth: 240, maxHeight: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardColors.key))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .shadow(color: KeyboardColors.shadow, radius: 0, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: pick)
        .onLongPressGesture(minimumDuration: 0.35, perform: expand)
        .accessibilityAddTraits(.isButton)
    }
}

/// One of "qisqaroq · iliqroq · rasmiyroq · hazil"; lit while it is applied.
struct TweakPill: View {
    let tweak: RewriteTweak
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tweak.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? .white : .primary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(isOn ? Color.accentColor : KeyboardColors.key))
        }
        .buttonStyle(.plain)
    }
}

/// Puts back what the user had typed before ✨, so a picked variant is not a one-way door.
struct OriginalChip: View {
    let draft: String
    let isSelected: Bool
    let restore: () -> Void

    var body: some View {
        Button(action: restore) {
            VStack(alignment: .leading, spacing: 2) {
                Text("↩︎ Asli").font(.system(size: 13.5, weight: .medium))
                Text(draft).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .frame(maxWidth: 160, maxHeight: .infinity, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardColors.key))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .shadow(color: KeyboardColors.shadow, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// Every reply in full, over the keys — a chip cuts them at two lines. Tap a card to use that reply.
struct VariantList: View {
    let title: String
    let suggestions: [Suggestion]
    /// The card to scroll to when the list opens; nil — the top.
    let focus: Suggestion.ID?
    /// The draft ✨ started from, when these are ✨ variants; nil for screenshot replies.
    let original: String?
    let picked: Suggestion.ID?
    let pick: (Suggestion) -> Void
    let restore: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Klaviatura", action: close).font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        if let original {
                            card(text: "↩︎ Asli", detail: original, isSelected: picked == nil, action: restore)
                        }
                        ForEach(suggestions) { suggestion in
                            card(text: suggestion.text, detail: suggestion.uz, isSelected: picked == suggestion.id) {
                                pick(suggestion)
                            }
                            .id(suggestion.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    if let focus { proxy.scrollTo(focus, anchor: .top) }
                }
            }
        }
    }

    private func card(text: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardColors.key))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .shadow(color: KeyboardColors.shadow, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// iOS 26+ fades scroll view edges; in the short chip row that fade covered the top of the chips.
struct NoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

/// Who ✨ writes to when there is no screenshot: a remembered friend (their language + tone) or just a language.
struct TargetChip: View {
    let target: KeyboardModel.Target
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                switch target {
                case .friend(let friend):
                    Text("\(Languages.flag(friend.language)) \(friend.name)")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(friend.language).font(.system(size: 11)).foregroundStyle(.secondary)
                case .language(let language):
                    Text("\(Languages.flag(language)) \(language)").font(.system(size: 13.5, weight: .medium))
                }
            }
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: 200, maxHeight: .infinity)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardColors.key))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .shadow(color: KeyboardColors.shadow, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ContextDetails: View {
    let context: ChatAnalysis
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(context.partner.isEmpty ? "Suhbat" : context.partner).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Klaviatura", action: close).font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(context.summaryUz).font(.system(size: 13))
                    if !context.lastIncoming.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.lastIncoming).font(.system(size: 13, weight: .medium))
                            Text(context.lastIncomingUz).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ForEach(Array(context.transcript.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(
                                line.from == "me" ? Color.accentColor.opacity(0.25) : KeyboardColors.key))
                            .frame(maxWidth: .infinity, alignment: line.from == "me" ? .trailing : .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}
