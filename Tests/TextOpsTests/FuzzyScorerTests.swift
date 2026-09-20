//
//  FuzzyScorerTests.swift
//  TextOpsTests
//
//  VS Code's fuzzyScorer.test.ts, carried over: the same targets, queries and expected orders.
//
//  Created by David Sherlock on 9/20/26.
//

import XCTest
@testable import TextOps

final class FuzzyScorerTests: XCTestCase {
    // The test file's ResourceAccessor: label = basename, description = dirname, path = whole.
    private func res(_ relativeOrAbsolute: String) -> FuzzyScorer.Item {
        let path = relativeOrAbsolute.hasPrefix("/") ? relativeOrAbsolute : "/" + relativeOrAbsolute   // URI.file() makes paths absolute
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let label = parts.last ?? path
        let dir = parts.dropLast()
        let description = dir.isEmpty ? "." : (dir.joined(separator: "/").isEmpty ? "/" : dir.joined(separator: "/"))
        return FuzzyScorer.Item(label: label, description: description, path: path)
    }
    private func score(_ target: String, _ query: String, _ allowNonContiguous: Bool? = nil) -> (score: Int, positions: [Int]) {
        let q = FuzzyQuery(query)
        return FuzzyScorer.score(target, query: q.normalized, queryLower: q.normalizedLowercase, allowNonContiguousMatches: allowNonContiguous ?? !q.expectContiguousMatch)
    }
    private func scoreItem(_ item: FuzzyScorer.Item, _ query: String, _ allow: Bool = true) -> FuzzyScorer.ItemScore {
        FuzzyScorer.scoreItem(item, query: FuzzyQuery(query), allowNonContiguousMatches: allow)
    }
    /// Sorts by the comparator, scoring each item once, like the callers must.
    private func sorted(_ items: [FuzzyScorer.Item], _ query: String) -> [String] {
        let q = FuzzyQuery(query)
        let scored = items.map { ($0, FuzzyScorer.scoreItem($0, query: q, allowNonContiguousMatches: true)) }
        return scored.sorted { FuzzyScorer.compare($0.0, $0.1, $1.0, $1.1, query: q) == .orderedAscending }.map { $0.0.path ?? $0.0.label }
    }
    private func assertOrder(_ paths: [String], _ query: String, _ expectedFirst: [String], file: StaticString = #filePath, line: UInt = #line) {
        let items = paths.map(res)
        let expected = expectedFirst.map { $0.hasPrefix("/") ? $0 : "/" + $0 }
        for permutation in [items, items.reversed()] {
            let got = sorted(permutation, query)
            XCTAssertEqual(Array(got.prefix(expected.count)), expected, "query \(query)", file: file, line: line)
        }
    }

    func testScoreFuzzyOrdering() {
        let target = "HelLo-World"
        let queries = ["HelLo-World", "hello-world", "HW", "hw", "H", "h", "W", "Ld", "ld", "w", "L", "l", "4"]
        let scores = queries.map { score(target, $0, true).score }
        XCTAssertEqual(scores, scores.sorted(by: >), "\(zip(queries, scores).map { "\($0)=\($1)" })")
        XCTAssertEqual(scores.last, 0)
    }

    func testScoreNonFuzzy() {
        let t = "HelLo-World"
        XCTAssertGreaterThan(score(t, "HelLo-World", false).score, 0)
        XCTAssertEqual(score(t, "HelLo-World", false).positions.count, t.count)
        XCTAssertGreaterThan(score(t, "hello-world", false).score, 0)
        XCTAssertEqual(score(t, "HW", false).score, 0)
        XCTAssertGreaterThan(score(t, "h", false).score, 0)
        XCTAssertGreaterThan(score(t, "ello", false).score, 0)
        XCTAssertGreaterThan(score(t, "ld", false).score, 0)
        XCTAssertEqual(score(t, "eo", false).score, 0)
    }

    func testScoreItemMatchesAreProper() {
        let r = res("/xyz/some/path/someFile123.txt")
        XCTAssertEqual(FuzzyScorer.scoreItem(FuzzyScorer.Item(label: ""), query: FuzzyQuery("something"), allowNonContiguousMatches: true).score, 0)
        let identity = scoreItem(r, r.path!)
        XCTAssertEqual(identity.score, FuzzyScorer.pathIdentityScore)
        XCTAssertEqual(identity.descriptionMatch, [FuzzyMatchRange(start: 0, end: r.description!.utf16.count)])
        XCTAssertEqual(identity.labelMatch, [FuzzyMatchRange(start: 0, end: r.label.utf16.count)])
        let prefix = scoreItem(r, "som")
        XCTAssertNil(prefix.descriptionMatch)
        XCTAssertEqual(prefix.labelMatch, [FuzzyMatchRange(start: 0, end: 3)])
        let camel = scoreItem(r, "sF")
        XCTAssertNil(camel.descriptionMatch)
        XCTAssertEqual(camel.labelMatch, [FuzzyMatchRange(start: 0, end: 1), FuzzyMatchRange(start: 4, end: 5)])
        let basename = scoreItem(r, "of")
        XCTAssertNil(basename.descriptionMatch)
        XCTAssertEqual(basename.labelMatch, [FuzzyMatchRange(start: 1, end: 2), FuzzyMatchRange(start: 4, end: 5)])
        let path = scoreItem(r, "xyz123")
        XCTAssertEqual(path.labelMatch, [FuzzyMatchRange(start: 8, end: 11)])
        XCTAssertEqual(path.descriptionMatch, [FuzzyMatchRange(start: 1, end: 4)])
        XCTAssertGreaterThan(scoreItem(r, "…me/path/someFile123.txt").score, 0)
        let none = scoreItem(r, "987")
        XCTAssertEqual(none.score, 0); XCTAssertNil(none.labelMatch); XCTAssertNil(none.descriptionMatch)
        let noExact = scoreItem(r, "\"sF\"")
        XCTAssertEqual(noExact.score, 0)
        XCTAssertGreaterThan(identity.score, prefix.score)
        XCTAssertGreaterThan(prefix.score, basename.score)
        XCTAssertGreaterThan(basename.score, path.score)
        XCTAssertGreaterThan(path.score, none.score)
    }

    func testScoreItemMultiple() {
        let r = res("/xyz/some/path/someFile123.txt")
        let s = scoreItem(r, "xyz some")
        XCTAssertGreaterThan(s.score, 0)
        XCTAssertEqual(s.labelMatch, [FuzzyMatchRange(start: 0, end: 4)])
        XCTAssertEqual(s.descriptionMatch, [FuzzyMatchRange(start: 1, end: 4)])
    }

    func testScoreItemOptimizeForFilePaths() {
        let s = scoreItem(res("/xyz/others/spath/some/xsp/file123.txt"), "xspfile123")
        XCTAssertEqual(s.labelMatch, [FuzzyMatchRange(start: 0, end: 7)])
        XCTAssertEqual(s.descriptionMatch, [FuzzyMatchRange(start: 23, end: 26)])
    }

    func testScoreItemAvoidScattering36119() {
        let s = scoreItem(res("projects/ui/cula/ats/target.mk"), "tcltarget.mk")
        XCTAssertEqual(s.labelMatch, [FuzzyMatchRange(start: 0, end: 9)])
    }

    func testScoreItemPrefersCompactMatches() {
        let s = scoreItem(res("/1a111d1/11a1d1/something.txt"), "ad")
        XCTAssertEqual(s.labelMatch ?? [], [])
        XCTAssertEqual(s.descriptionMatch, [FuzzyMatchRange(start: 11, end: 12), FuzzyMatchRange(start: 13, end: 14)])
    }

    func testScoreItemProperTargetOffsets() {
        XCTAssertEqual(scoreItem(res("etem"), "teem").score, 0)
        XCTAssertEqual(scoreItem(res("ede"), "de").labelMatch, [FuzzyMatchRange(start: 1, end: 3)])
        let s = scoreItem(res("/src/vs/editor/browser/viewParts/lineNumbers/flipped-cursor-2x.svg"), "debug")
        XCTAssertEqual(s.descriptionMatch, [FuzzyMatchRange(start: 9, end: 10), FuzzyMatchRange(start: 36, end: 37), FuzzyMatchRange(start: 40, end: 41)])
        XCTAssertEqual(s.labelMatch, [FuzzyMatchRange(start: 9, end: 10), FuzzyMatchRange(start: 20, end: 21)])
    }

    func testScoreItemNoMatchUnlessInSequence() {
        XCTAssertEqual(scoreItem(res("abcde"), "edcda").score, 0)
    }

    func testScoreItemSlashOrBackslash() {
        let r = res("abcde/super/duper")
        XCTAssertGreaterThan(scoreItem(r, "abcde\\super\\duper").score, 0)
        XCTAssertGreaterThan(scoreItem(r, "abcde/super/duper").score, 0)
    }

    func testUpperCaseBonusOnlyOnNonConsecutive134723() {
        XCTAssertGreaterThan(scoreItem(res("asdfasdfasdf"), "asdf").score, scoreItem(res("ASDFasdfasdf"), "asdf").score)
    }

    // MARK: - Ordering

    private let abc = ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"]

    func testCompareIdentity() {
        assertOrder(abc, "/some/path/fileA.txt", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(abc, "/some/path/other/fileB.txt", ["/some/path/other/fileB.txt", "/some/path/fileA.txt", "/unrelated/some/path/other/fileC.txt"])
    }
    func testCompareBasenamePrefix() {
        assertOrder(abc, "fileA.txt", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(abc, "fileB.txt", ["/some/path/other/fileB.txt", "/some/path/fileA.txt", "/unrelated/some/path/other/fileC.txt"])
    }
    func testCompareBasenameCamelCase() {
        assertOrder(abc, "fA", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(abc, "fB", ["/some/path/other/fileB.txt", "/some/path/fileA.txt", "/unrelated/some/path/other/fileC.txt"])
    }
    func testCompareBasenameScores() {
        assertOrder(abc, "fileA", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(abc, "fileB", ["/some/path/other/fileB.txt", "/some/path/fileA.txt", "/unrelated/some/path/other/fileC.txt"])
    }
    func testComparePathScores() {
        assertOrder(abc, "pathfileA", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(abc, "pathfileB", ["/some/path/other/fileB.txt", "/some/path/fileA.txt", "/unrelated/some/path/other/fileC.txt"])
    }
    func testComparePreferShorterBasenames() {
        let p = ["/some/path/fileA.txt", "/some/path/other/fileBLonger.txt", "/unrelated/the/path/other/fileC.txt"]
        assertOrder(p, "somepath", ["/some/path/fileA.txt", "/some/path/other/fileBLonger.txt", "/unrelated/the/path/other/fileC.txt"])
        assertOrder(p, "file", ["/some/path/fileA.txt", "/unrelated/the/path/other/fileC.txt", "/some/path/other/fileBLonger.txt"])
    }
    func testComparePreferShorterPaths() {
        assertOrder(abc, "somepath", ["/some/path/fileA.txt", "/some/path/other/fileB.txt", "/unrelated/some/path/other/fileC.txt"])
        assertOrder(["config/test/t1.js", "config/test.js", "config/test/t2.js"], "co/te", ["config/test.js", "config/test/t1.js", "config/test/t2.js"])
    }
    func testComparePreferLabelOverDescription() {
        assertOrder(["parts/quick/arrow-left-dark.svg", "parts/quickopen/quickopen.ts"], "partsquick", ["parts/quickopen/quickopen.ts", "parts/quick/arrow-left-dark.svg"])
    }
    func testComparePreferCamelCase() {
        for q in ["npe", "NPE"] {
            assertOrder(["config/test/NullPointerException.java", "config/test/nopointerexception.java"], q, ["config/test/NullPointerException.java", "config/test/nopointerexception.java"])
        }
    }
    func testComparePreferCompactMatches() {
        assertOrder(["config/test/openthisAnythingHandler.js", "config/test/openthisisnotsorelevantforthequeryAnyHand.js"], "AH", ["config/test/openthisisnotsorelevantforthequeryAnyHand.js"])
        assertOrder(["config/test/examasdaple.js", "config/test/exampleasdaasd.ts"], "xp", ["config/test/exampleasdaasd.ts"])
        assertOrder(["config/test/examasdaple/file.js", "config/test/exampleasdaasd/file.ts"], "xp", ["config/test/exampleasdaasd/file.ts"])
        assertOrder(["config/example/thisfile.ts", "config/24234243244/example/file.js"], "exfile", ["config/24234243244/example/file.js"])
    }
    func testCompareAvoidMatchScattering() {
        let mods = ["node_modules1/bundle/lib/model/modules/ot1/index.js", "node_modules1/bundle/lib/model/modules/un1/index.js",
                    "node_modules1/bundle/lib/model/modules/modu1/index.js", "node_modules1/bundle/lib/model/modules/oddl1/index.js"]
        assertOrder(mods, "modu1/index.js", ["node_modules1/bundle/lib/model/modules/modu1/index.js"])
        assertOrder(mods, "un1/index.js", ["node_modules1/bundle/lib/model/modules/un1/index.js"])
        assertOrder(["app/containers/Services/NetworkData/ServiceDetails/ServiceLoad/index.js",
                     "app/containers/Services/NetworkData/ServiceDetails/ServiceDistribution/index.js",
                     "app/containers/Services/NetworkData/ServiceDetailTabs/ServiceTabs/StatVideo/index.js"], "StatVideoindex",
                    ["app/containers/Services/NetworkData/ServiceDetailTabs/ServiceTabs/StatVideo/index.js"])
        assertOrder(["src/build-helper/store/redux.ts", "src/repository/store/redux.ts"], "reproreduxts", ["src/repository/store/redux.ts"])
        assertOrder(["photobook/src/components/AddPagesButton/index.js", "photobook/src/components/ApprovalPageHeader/index.js",
                     "photobook/src/canvasComponents/BookPage/index.js"], "bookpageIndex", ["photobook/src/canvasComponents/BookPage/index.js"])
        assertOrder(["ui/src/utils/constants.js", "ui/src/ui/Icons/index.js"], "ui/icons", ["ui/src/ui/Icons/index.js"])
        assertOrder(["ui/src/components/IDInput/index.js", "ui/src/ui/Input/index.js"], "ui/input/index", ["ui/src/ui/Input/index.js"])
        assertOrder(["django/contrib/sites/locale/ga/LC_MESSAGES/django.mo", "django/core/signals.py"], "djancosig", ["django/core/signals.py"])
        assertOrder(["adsys/protected/config.php", "adsys/protected/framework/smarty/sysplugins/smarty_internal_config.php", "duowanVideo/wap/protected/config.php"],
                    "protectedconfig.php", ["adsys/protected/config.php", "duowanVideo/wap/protected/config.php", "adsys/protected/framework/smarty/sysplugins/smarty_internal_config.php"])
        assertOrder(["pkg/search/gradient/testdata/constraint_attrMatchString.yml", "cmd/gradient/main.go"], "gradientmain", ["cmd/gradient/main.go"])
        assertOrder(["alpha-beta-cappa.txt", "abc.txt"], "abc", ["abc.txt"])
        assertOrder(["xerxes-yak-zubba/index.js", "xyz/index.js"], "xyz", ["xyz/index.js"])
        assertOrder(["AssymblyInfo.cs", "IAsynchronousTask.java"], "async", ["IAsynchronousTask.java"])
        assertOrder(["static/app/source/angluar/-admin/-organization/-settings/layout/layout.js",
                     "static/app/source/angular/-admin/-project/-settings/_settings/settings.js"], "partisettings",
                    ["static/app/source/angular/-admin/-project/-settings/_settings/settings.js"])
        assertOrder(["Trilby.TrilbyTV.Web.Portal/Views/Systems/Index.cshtml", "Trilby.TrilbyTV.Web.Portal/Areas/Admins/Views/Tips/Index.cshtml"],
                    "tipsindex.cshtml", ["Trilby.TrilbyTV.Web.Portal/Areas/Admins/Views/Tips/Index.cshtml"])
        assertOrder(["editor/core/components/tests/list-view-spec.js", "editor/core/components/list-view.js"], "listview", ["editor/core/components/list-view.js"])
        assertOrder(["src/vs/workbench/contrib/files/common/explorerViewModel.ts", "src/vs/workbench/contrib/files/browser/views/explorerView.ts",
                     "src/vs/workbench/contrib/files/browser/views/explorerViewer.ts"], "filesexplorerview.ts",
                    ["src/vs/workbench/contrib/files/browser/views/explorerView.ts"])
    }
    func testComparePreferCaseMatch96122() {
        assertOrder(["lists.php", "lib/Lists.php"], "Lists.php", ["lib/Lists.php"])
    }
    func testComparePreferShorterMatch103052() {
        for q in ["foo bar", "foobar"] { assertOrder(["app/emails/foo.bar.js", "app/emails/other-footer.other-bar.js"], q, ["app/emails/foo.bar.js", "app/emails/other-footer.other-bar.js"]) }
        for q in ["payment model", "paymentmodel"] {
            assertOrder(["app/components/payment/payment.model.js", "app/components/online-payments-history/online-payments-history.model.js"], q,
                        ["app/components/payment/payment.model.js", "app/components/online-payments-history/online-payments-history.model.js"])
        }
        for q in ["color js", "colorjs"] {
            assertOrder(["app/constants/color.js", "app/components/model/input/pick-avatar-color.js"], q, ["app/constants/color.js", "app/components/model/input/pick-avatar-color.js"])
        }
    }
    func testComparePreferStrictCasePrefix() {
        let p = ["app/constants/color.js", "app/components/model/input/Color.js"]
        assertOrder(p, "Color", ["app/components/model/input/Color.js", "app/constants/color.js"])
        assertOrder(p, "color", ["app/constants/color.js", "app/components/model/input/Color.js"])
    }
    func testComparePreferPrefix103052() {
        assertOrder(["test/smoke/src/main.ts", "src/vs/editor/common/services/semantikTokensProviderStyling.ts"], "smoke main.ts",
                    ["test/smoke/src/main.ts", "src/vs/editor/common/services/semantikTokensProviderStyling.ts"])
    }
    func testCompareMultipleQueryBoosts() {
        for q in ["workbench.ts browser", "browser workbench.ts", "browser workbench", "workbench browser"] {
            assertOrder(["src/vs/workbench/services/host/browser/browserHostService.ts", "src/vs/workbench/browser/workbench.ts"], q,
                        ["src/vs/workbench/browser/workbench.ts", "src/vs/workbench/services/host/browser/browserHostService.ts"])
        }
        for q in ["window node", "window.ts node"] {
            assertOrder(["src/vs/workbench/node/actions/windowActions.ts", "src/vs/workbench/electron-node/window.ts"], q,
                        ["src/vs/workbench/electron-node/window.ts", "src/vs/workbench/node/actions/windowActions.ts"])
        }
        assertOrder(["mesh_editor_lifetime_job.h", "lifetime_job.h"], "m life, life m", ["lifetime_job.h", "mesh_editor_lifetime_job.h"])
    }
    func testCompareSkipLabelPreferenceWithPathSep() {
        assertOrder(["djangosite/ufrela/def.py", "djangosite/urls/default.py"], "url/def", ["djangosite/urls/default.py", "djangosite/ufrela/def.py"])
    }
    func testCompareBoostConsecutiveMatchesAtBeginning() {
        assertOrder(["src/vs/server/node/extensionHostStatusService.ts", "src/vs/workbench/browser/parts/notifications/notificationsStatus.ts"], "notStatus",
                    ["src/vs/workbench/browser/parts/notifications/notificationsStatus.ts", "src/vs/server/node/extensionHostStatusService.ts"])
    }

    // MARK: - Query preparation and quoting

    func testPrepareQuery() {
        XCTAssertEqual(FuzzyQuery(" f*a ").normalized, "fa")
        XCTAssertEqual(FuzzyQuery(" f…a ").normalized, "fa")
        XCTAssertEqual(FuzzyQuery("main#").normalized, "main")
        XCTAssertEqual(FuzzyQuery("main#").original, "main#")
        XCTAssertEqual(FuzzyQuery("foo*").normalized, "foo")
        let mt = FuzzyQuery("model Tester.ts")
        XCTAssertEqual(mt.normalized, "modelTester.ts")
        XCTAssertFalse(mt.expectContiguousMatch)
        XCTAssertEqual(FuzzyQuery("Model Tester.ts").normalizedLowercase, "modeltester.ts")
        XCTAssertFalse(FuzzyQuery("ModelTester.ts").containsPathSeparator)
        XCTAssertTrue(FuzzyQuery("Model/Tester.ts").containsPathSeparator)
        XCTAssertTrue(FuzzyQuery("\"hello\"").expectContiguousMatch)
        XCTAssertEqual(FuzzyQuery("\"hello\"").normalized, "hello")
        let hw = FuzzyQuery("He*llo World")
        XCTAssertEqual(hw.normalized, "HelloWorld")
        XCTAssertEqual(hw.pieces?.map(\.normalized), ["Hello", "World"])
        XCTAssertEqual(hw.pieces?.map(\.original), ["He*llo", "World"])
        let spaced = FuzzyQuery(" Hello   World  \t")
        XCTAssertEqual(spaced.normalized, "HelloWorld")
        XCTAssertEqual(spaced.pieces?.map(\.normalized), ["Hello", "World"])
        XCTAssertEqual(FuzzyQuery("\\some\\path").pathNormalized, "/some/path")
        XCTAssertTrue(FuzzyQuery("\\some\\path").containsPathSeparator)
    }

    func testQuotesExpectContiguous() {
        XCTAssertEqual(score("contiguous", "\"contguous\"").score, 0)
        XCTAssertGreaterThan(score("contiguous", "\"contiguous\"").score, 0)
        let s = score("2021-7-26.md", "\"26\"")
        XCTAssertEqual(s.score, 14)
        XCTAssertEqual(s.positions, [7, 8])
    }

    func testRangesFromPositionsMergeConsecutive() {
        XCTAssertEqual(FuzzyScorer.ranges(from: [0, 1, 2, 5, 9, 10]), [FuzzyMatchRange(start: 0, end: 3), FuzzyMatchRange(start: 5, end: 6), FuzzyMatchRange(start: 9, end: 11)])
    }
}
