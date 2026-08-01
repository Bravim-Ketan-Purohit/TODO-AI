import UIKit

/// Day-note photos never leave the phone (privacy: server stores mood+text
/// only). One JPEG per day in Documents.
enum NotePhotoStore {
    private static func url(_ date: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("note-\(date).jpg")
    }

    static func save(_ image: UIImage, for date: String) {
        try? image.jpegData(compressionQuality: 0.8)?.write(to: url(date))
    }

    static func load(_ date: String) -> UIImage? {
        UIImage(contentsOfFile: url(date).path)
    }
}
