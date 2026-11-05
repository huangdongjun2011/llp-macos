public struct ListeningDraft: Equatable {
    public private(set) var isEditorVisible: Bool
    public var text: String

    public init(isEditorVisible: Bool = false, text: String = "") {
        self.isEditorVisible = isEditorVisible
        self.text = text
    }

    @discardableResult
    public mutating func toggleEditorVisibility() -> Bool {
        isEditorVisible.toggle()
        return isEditorVisible
    }
}
