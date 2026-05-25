import Foundation

/// Shared state for coordinating drag-to-convert between panels.
@MainActor
final class DragCoordinator: ObservableObject {
    @Published var draggedItems: [FileItem] = []
    @Published var isDragging = false

    func beginDrag(items: [FileItem]) {
        draggedItems = items
        isDragging = true
    }

    func endDrag() {
        draggedItems = []
        isDragging = false
    }
}
