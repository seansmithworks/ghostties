import Foundation

/// How a project's sidebar tile is drawn. Nil on `Project` means `.auto`.
/// No ghost case: the ghost shapes are not offered as an icon option.
public enum ProjectIconStyle: String, Codable, Hashable, CaseIterable {
    /// Use a detected project icon, else fall back to the monogram.
    case auto
    /// Always draw the project's initial.
    case monogram
    /// Use the user-chosen image copied into Application Support.
    case file
}

/// What the new-session shortcut creates for a project.
public enum NewSessionDefault: Codable, Hashable {
    case shell
    case lastUsed
    case template(UUID)
}

/// A workspace project representing a directory the user has pinned.
public struct Project: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var rootPath: String
    public var isPinned: Bool

    /// The pixel-art ghost character displayed in the icon rail.
    /// Nil means the project predates the ghost system (shows initial fallback).
    public var ghostCharacter: GhostCharacter?

    /// The default template to use when creating sessions with a single click.
    /// Nil means always show the template picker.
    public var defaultTemplateId: UUID?

    /// The last moment any session in this project produced output, was focused,
    /// or was created. Drives the "Recent" smart-section membership rule.
    /// Nil means this project predates the timestamp system or has never been touched.
    public var lastActiveAt: Date?

    /// Tile style. Nil means `.auto`.
    public var iconStyle: ProjectIconStyle?

    /// What the new-session shortcut creates. Nil means the app default.
    public var newSessionDefault: NewSessionDefault?

    /// The template most recently used to create a session in this project.
    public var lastTemplateId: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        isPinned: Bool = false,
        ghostCharacter: GhostCharacter? = nil,
        defaultTemplateId: UUID? = nil,
        lastActiveAt: Date? = nil,
        iconStyle: ProjectIconStyle? = nil,
        newSessionDefault: NewSessionDefault? = nil,
        lastTemplateId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.isPinned = isPinned
        self.ghostCharacter = ghostCharacter
        self.defaultTemplateId = defaultTemplateId
        self.lastActiveAt = lastActiveAt
        self.iconStyle = iconStyle
        self.newSessionDefault = newSessionDefault
        self.lastTemplateId = lastTemplateId
    }

    // Custom decoder so existing workspace.json files (without ghost/template/timestamp
    // fields) load without error. New fields default to nil when missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.rootPath = try container.decode(String.self, forKey: .rootPath)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.ghostCharacter = try container.decodeIfPresent(GhostCharacter.self, forKey: .ghostCharacter)
        self.defaultTemplateId = try container.decodeIfPresent(UUID.self, forKey: .defaultTemplateId)
        self.lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        self.iconStyle = try container.decodeIfPresent(ProjectIconStyle.self, forKey: .iconStyle)
        self.newSessionDefault = try container.decodeIfPresent(NewSessionDefault.self, forKey: .newSessionDefault)
        self.lastTemplateId = try container.decodeIfPresent(UUID.self, forKey: .lastTemplateId)
    }
}
