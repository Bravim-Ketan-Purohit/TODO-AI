import PhotosUI
import SwiftUI

/// Evening reflection (design 7o/7p): three geometric moods, one line, an
/// optional photo. Skippable, zero guilt. Photo never leaves the phone.
struct NotePromptCard: View {
    let onSave: (String, String, UIImage?) -> Void
    let onSkip: () -> Void

    @State private var mood: String?
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 14) {
                HStack(spacing: 26) {
                    moodButton("good") {
                        Rectangle().fill(DS.acidLime).frame(width: 13, height: 13)
                            .cornerRadius(2).rotationEffect(.degrees(45))
                    }
                    moodButton("ok") {
                        Circle().fill(DS.fog).frame(width: 13, height: 13)
                    }
                    moodButton("rough") {
                        Triangle().fill(DS.coral).frame(width: 14, height: 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    self.photo = nil
                                    photoItem = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(DS.fog)
                                        .frame(width: 16, height: 16)
                                        .background(Color(hex: 0x26282B))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                    }
                    TextField("One line about today…", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .font(DS.inter(13.5)).foregroundStyle(DS.paper)
                        .focused($focused)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 14)).foregroundStyle(DS.ash)
                    }
                }
                .padding(.top, 13)
                .overlay(alignment: .top) { DS.hairline.frame(height: 0.5) }

                if mood != nil {
                    Button {
                        onSave(mood ?? "ok", text.trimmingCharacters(in: .whitespacesAndNewlines),
                               photo)
                    } label: {
                        Text("Save note")
                            .font(DS.inter(13.5, .medium)).foregroundStyle(Color(hex: 0x08090A))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(DS.limeGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(16)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            Button(action: onSkip) {
                Text("Skip — tomorrow doesn't care.")
                    .font(DS.inter(12)).foregroundStyle(Color(hex: 0x4B4F55))
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(duration: 0.3), value: mood)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photo = UIImage(data: data)
                }
            }
        }
    }

    private func moodButton(_ value: String, @ViewBuilder glyph: () -> some View) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { mood = value }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            glyph()
                .frame(width: 44, height: 44)
                .background(mood == value ? DS.acidLime.opacity(0.12) : .clear)
                .overlay(Circle().stroke(mood == value ? DS.acidLime : Color(hex: 0x23252A),
                                         lineWidth: mood == value ? 1 : 0.5))
                .clipShape(Circle())
                .scaleEffect(mood == value ? 1.08 : 1)
                .opacity(mood == nil || mood == value ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
