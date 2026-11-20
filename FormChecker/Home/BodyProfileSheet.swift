import PoseEngine
import SwiftUI

/// 내 정보 — 키·몸무게·나이·성별.
///
/// 🔴 **네 값이 각각 독립적으로 없을 수 있다.** 반쯤 채운 상태로 닫아도 넣은 것만
/// 남는다 — 키만 아는 사람에게 몸무게를 강요하면 키까지 못 받는다.
///
/// 🔴 **범위 밖은 저장하지 않는다.** 의학적 판단이 아니라 오타 방어다 — 몸무게에 700을
/// 넣으면 열량이 10배로 나오는데 그게 틀렸다는 것을 사용자가 알 방법이 없다.
///
/// 🔴 **나이·성별은 선택이다.** 없으면 열량 추정이 기본값(30세·남성)을 쓰고 홈이
/// 그 사실을 밝힌다.
struct BodyProfileSheet: View {

    let onDone: () -> Void

    @State private var settings = AppSettings.shared
    @State private var height = ""
    @State private var weight = ""
    @State private var age = ""
    @State private var sex: Sex?
    @FocusState private var focused: Field?

    private enum Field { case height, weight, age }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow("키", unit: "cm", text: $height, field: .height,
                              hint: "\(Int(BodyProfile.heightRangeCm.lowerBound))~\(Int(BodyProfile.heightRangeCm.upperBound))")
                    numberRow("몸무게", unit: "kg", text: $weight, field: .weight,
                              hint: "\(Int(BodyProfile.weightRangeKg.lowerBound))~\(Int(BodyProfile.weightRangeKg.upperBound))")
                } header: {
                    Text("열량 추정에 쓰여요")
                } footer: {
                    Text("키와 몸무게가 둘 다 있어야 소모 열량을 어림할 수 있어요. "
                         + "넣지 않으면 홈에서 열량을 보여주지 않아요.")
                }

                Section {
                    numberRow("나이", unit: "세", text: $age, field: .age,
                              hint: "\(BodyProfile.ageRange.lowerBound)~\(BodyProfile.ageRange.upperBound)")
                    Picker("성별", selection: $sex) {
                        Text("선택 안 함").tag(Sex?.none)
                        Text("남성").tag(Sex?.some(.male))
                        Text("여성").tag(Sex?.some(.female))
                    }
                } header: {
                    Text("선택")
                } footer: {
                    Text("넣지 않으면 \(CalorieEstimate.assumedAge)세 "
                         + "\(CalorieEstimate.assumedSex == .male ? "남성" : "여성")으로 어림하고, "
                         + "홈에서 그 사실을 함께 보여줘요.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bgBase)
            .navigationTitle("내 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { save() }
                        .foregroundStyle(Palette.lime)
                }
            }
        }
        .onAppear { load() }
    }

    private func numberRow(
        _ title: String, unit: String, text: Binding<String>, field: Field, hint: String
    ) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.textPrimary)
            Spacer()
            TextField(hint, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: field)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(Palette.textMuted)
        }
    }

    private func load() {
        height = settings.heightCm.map { format($0) } ?? ""
        weight = settings.weightKg.map { format($0) } ?? ""
        age = settings.age.map(String.init) ?? ""
        sex = settings.sex
    }

    /// 빈 칸은 **"지운다"는 뜻**이다. 범위를 벗어난 값도 저장되지 않는다
    /// (`AppSettings`가 거른다) — 그 경우 값이 없는 것과 같아진다.
    private func save() {
        settings.heightCm = Float(height.trimmingCharacters(in: .whitespaces))
        settings.weightKg = Float(weight.trimmingCharacters(in: .whitespaces))
        settings.age = Int(age.trimmingCharacters(in: .whitespaces))
        settings.sex = sex
        onDone()
    }

    private func format(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
