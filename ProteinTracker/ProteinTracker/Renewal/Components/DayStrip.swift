import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct DayStrip: View {
    let days: [CalendarDay]
    let selected: CalendarDay
    let today: CalendarDay
    let recordedDays: Set<CalendarDay>
    let onSelect: (CalendarDay) -> Void
    let onShift: (Int) -> Void
    @Environment(\.sizeCategory) private var sizeCategory

    /// Seven equal-width buttons at standard text sizes: on a 375 pt phone the
    /// content width is 335 pt, so 7 × 44 pt plus 6 × 4 pt (332 pt) fits
    /// without horizontal scrolling. Accessibility sizes keep the original
    /// scrolling strip so the labels and the 44 pt touch targets stay intact.
    private var fitsWithoutScrolling: Bool { !sizeCategory.isAccessibilityCategory }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button { onShift(-7) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("renewal_previous_week"))
                Spacer(minLength: 8)
                Text(RecordHomeView.longDate(selected))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { onShift(7) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("renewal_next_week"))
            }
            if fitsWithoutScrolling {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        dayButton(day).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 2)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(days, id: \.self) { day in
                                dayButton(day).id(day)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
                    .onChange(of: selected) { day in proxy.scrollTo(day, anchor: .center) }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dayButton(_ day: CalendarDay) -> some View {
        let isSelected = day == selected
        return Button { onSelect(day) } label: {
            VStack(spacing: 5) {
                Text(RecordHomeView.weekdaySymbol(day)).font(.caption)
                Text("\(day.day)").font(.body.weight(.semibold)).monospacedDigit()
                HStack(spacing: 4) {
                    Circle().fill(day == today ? (isSelected ? .white : RenewalTheme.ink) : .clear)
                        .frame(width: 5, height: 5)
                    Capsule().fill(recordedDays.contains(day) ? (isSelected ? .white : RenewalTheme.action) : .clear)
                        .frame(width: 12, height: 4)
                }
            }
            .padding(.vertical, 10)
            .frame(minWidth: 44, minHeight: 64)
            .frame(maxWidth: fitsWithoutScrolling ? .infinity : nil)
            .foregroundColor(isSelected ? RenewalTheme.canvas : RenewalTheme.ink)
            .background(isSelected ? RenewalTheme.ink : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(RecordHomeView.longDate(day)))
        .accessibilityValue(Text(accessibilityValue(day)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityValue(_ day: CalendarDay) -> String {
        [day == today ? RenewalStrings.text("renewal_today") : nil,
         recordedDays.contains(day) ? RenewalStrings.text("renewal_has_records") : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
