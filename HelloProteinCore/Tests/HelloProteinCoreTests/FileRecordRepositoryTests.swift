import XCTest
@testable import HelloProteinCore

final class FileRecordRepositoryTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("records-v1.json") }
    private let day = try! CalendarDay(iso8601: "2026-09-28")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelloProteinCoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSaveSurvivesRepositoryRecreation() throws {
        var log = try DailyLog(day: day)
        try log.add(FoodRecord(
            id: "record", day: day, name: "Egg", quantity: nil,
            protein: ProteinAmount(centigrams: 1_250), source: .manual
        ))
        try FileRecordRepository(fileURL: fileURL).save(log)

        let reloaded = try FileRecordRepository(fileURL: fileURL).log(for: day)
        XCTAssertEqual(reloaded, log)
        XCTAssertEqual(try reloaded.totalProteinCentigrams(), 1_250)
    }

    func testSavingSameDayIsUpsertInsteadOfDuplicate() throws {
        let repository = FileRecordRepository(fileURL: fileURL)
        try repository.save(DailyLog(day: day, legacyAdjustmentCentigrams: 1_000))
        try repository.save(DailyLog(day: day, legacyAdjustmentCentigrams: 2_000))
        XCTAssertEqual(try repository.allLogs().count, 1)
        XCTAssertEqual(try repository.log(for: day).totalProteinCentigrams(), 2_000)
    }

    func testMissingDayReturnsEmptyWithoutWritingAFile() throws {
        let log = try FileRecordRepository(fileURL: fileURL).log(for: day)
        XCTAssertEqual(log.detailState, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptFileFailsInsteadOfAppearingAsEmptyHistory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)
        XCTAssertThrowsError(try FileRecordRepository(fileURL: fileURL).allLogs())
    }
}
