import SwiftUI
import WidgetKit

@main
struct TODOWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TODOWidgets()
        TODOWidgetsLiveActivity()
    }
}
