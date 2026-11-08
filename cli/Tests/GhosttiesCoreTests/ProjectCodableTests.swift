import Foundation
import Testing
@testable import GhosttiesCore

@Suite struct ProjectCodableTests {
    private let legacyJSON = """
    {"id":"11111111-1111-1111-1111-111111111111","name":"atlas","rootPath":"/tmp/atlas","isPinned":true,\
    "defaultTemplateId":"22222222-2222-2222-2222-222222222222"}
    """

    private let fullJSON = """
    {"id":"11111111-1111-1111-1111-111111111111","name":"atlas","rootPath":"/tmp/atlas","isPinned":false,\
    "iconStyle":"monogram","newSessionDefault":{"template":{"_0":"33333333-3333-3333-3333-333333333333"}},\
    "lastTemplateId":"44444444-4444-4444-4444-444444444444"}
    """

    @Test func legacyFileDecodesWithNilNewFieldsAndReencodesWithoutThem() throws {
        let project = try JSONDecoder().decode(Project.self, from: Data(legacyJSON.utf8))
        #expect(project.iconStyle == nil)
        #expect(project.newSessionDefault == nil)
        #expect(project.lastTemplateId == nil)
        #expect(project.defaultTemplateId != nil)

        let out = try JSONEncoder().encode(project)
        let object = try #require(JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(object["iconStyle"] == nil)
        #expect(object["newSessionDefault"] == nil)
        #expect(object["lastTemplateId"] == nil)
        #expect(try JSONDecoder().decode(Project.self, from: out) == project)
    }

    @Test func fullFileRoundTrips() throws {
        let project = try JSONDecoder().decode(Project.self, from: Data(fullJSON.utf8))
        #expect(project.iconStyle == .monogram)
        #expect(project.newSessionDefault == .template(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!))
        #expect(project.lastTemplateId == UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let again = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(again == project)
    }

    @Test func simpleDefaultsRoundTrip() throws {
        for value in [NewSessionDefault.shell, .lastUsed] {
            let project = Project(name: "p", rootPath: "/tmp/p", newSessionDefault: value)
            let again = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
            #expect(again.newSessionDefault == value)
        }
    }

    @Test func unknownFutureNewSessionDefaultDecodesAsNil() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"atlas","rootPath":"/tmp/atlas","isPinned":false,\
        "iconStyle":"holographic","newSessionDefault":{"somethingNew":{"_0":1}}}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.name == "atlas")
        #expect(project.newSessionDefault == nil)
        #expect(project.iconStyle == nil)
    }
}
