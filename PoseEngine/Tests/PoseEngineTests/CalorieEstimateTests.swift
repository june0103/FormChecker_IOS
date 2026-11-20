import XCTest
@testable import PoseEngine

final class CalorieEstimateTests: XCTestCase {

    private let height: Float = 170
    private let weight: Float = 70

    func test_기초대사량이_Mifflin_St_Jeor_식과_같다() {
        XCTAssertEqual(
            CalorieEstimate.restingKcalPerDay(heightCm: 170, weightKg: 70, age: 25, sex: .male),
            1642.5, accuracy: 0.01
        )
        XCTAssertEqual(
            CalorieEstimate.restingKcalPerDay(heightCm: 170, weightKg: 70, age: 25, sex: .female),
            1642.5 - 166, accuracy: 0.01
        )
    }

    /// 🔴 **독립 실측과의 일치를 붙든다.** 상수를 손대면 여기서 깨진다.
    func test_문헌_실측_신뢰구간_안에_들어온다() throws {
        let perRep = try XCTUnwrap(
            CalorieEstimate.perRep(heightCm: height, weightKg: weight, age: 25, sex: .male)
        )
        XCTAssertTrue((0.42...0.58).contains(perRep),
                      "1회당 \(perRep) kcal — Nakagata 95% CI(0.42~0.58) 밖이다")
    }

    func test_스쿼트_MET는_Compendium_코드_02052_값이다() {
        XCTAssertEqual(CalorieEstimate.squatMET, 5.0, accuracy: 1e-6)
    }

    func test_총_열량은_횟수에_비례한다() throws {
        let ten = try XCTUnwrap(CalorieEstimate.forSession(reps: 10, heightCm: height, weightKg: weight))
        let twenty = try XCTUnwrap(CalorieEstimate.forSession(reps: 20, heightCm: height, weightKg: weight))
        XCTAssertEqual(twenty.kcal / ten.kcal, 2, accuracy: 1e-4)
        XCTAssertEqual(twenty.reps, 20)
    }

    func test_횟수가_0이면_nil이다() {
        XCTAssertNil(CalorieEstimate.forSession(reps: 0, heightCm: height, weightKg: weight))
    }

    /// **깊이도 템포도 보지 않는다** — 같은 입력이면 항상 같은 값이다.
    func test_1회당_열량에_시간이_들어가지_않는다() throws {
        let a = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight))
        let b = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight))
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    func test_몸무게가_많으면_더_많이_나온다() throws {
        let light = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: 50))
        let heavy = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: 90))
        XCTAssertGreaterThan(heavy, light)
    }

    /// **키가 여기서 쓰인다** — MET 표준식은 체중만 보지만 기초대사량 식이 키를 쓴다.
    func test_키가_크면_더_많이_나온다() throws {
        let short = try XCTUnwrap(CalorieEstimate.perRep(heightCm: 150, weightKg: weight))
        let tall = try XCTUnwrap(CalorieEstimate.perRep(heightCm: 190, weightKg: weight))
        XCTAssertGreaterThan(tall, short, "키가 결과를 바꾸지 않는다")
    }

    func test_나이가_많으면_조금_줄어든다() throws {
        let young = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight, age: 20))
        let old = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight, age: 70))
        XCTAssertGreaterThan(young, old)
    }

    func test_여성이_남성보다_낮게_나온다() throws {
        let male = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight, sex: .male))
        let female = try XCTUnwrap(CalorieEstimate.perRep(heightCm: height, weightKg: weight, sex: .female))
        XCTAssertGreaterThan(male, female)
    }

    /// **가정했다는 사실이 결과에 남아야 한다** — 화면이 그걸 밝힌다.
    func test_가정을_썼는지_결과에_남는다() throws {
        let assumed = try XCTUnwrap(CalorieEstimate.forSession(reps: 10, heightCm: height, weightKg: weight))
        XCTAssertTrue(assumed.assumedAge)
        XCTAssertTrue(assumed.assumedSex)
        XCTAssertFalse(assumed.exact)

        let given = try XCTUnwrap(CalorieEstimate.forSession(
            reps: 10, heightCm: height, weightKg: weight, age: 25, sex: .male))
        XCTAssertTrue(given.exact)
    }

    func test_키나_몸무게가_없으면_nil이다() {
        XCTAssertNil(CalorieEstimate.perRep(heightCm: 0, weightKg: weight))
        XCTAssertNil(CalorieEstimate.perRep(heightCm: height, weightKg: 0))
    }
}
