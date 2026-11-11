import Testing

import InnoDI

@Suite("FeatureRoot macro token")
struct FeatureRootTokenTests {
    @Test("Hosting is an explicit opt-in and the alias defaults to none")
    func initializersRecordEachChoice() {
        let plain = FeatureRoot(Int.self)
        #expect(ObjectIdentifier(plain.rootView) == ObjectIdentifier(Int.self))
        #expect(plain.alias == nil)
        #expect(!plain.hosted)

        let aliased = FeatureRoot(String.self, as: "detail")
        #expect(ObjectIdentifier(aliased.rootView) == ObjectIdentifier(String.self))
        #expect(aliased.alias == "detail")
        #expect(!aliased.hosted)

        let hosted = FeatureRoot(String.self, as: "detail", hosted: true)
        #expect(hosted.alias == "detail")
        #expect(hosted.hosted)
        #expect(!FeatureRoot(Int.self, hosted: false).hosted)
    }
}
