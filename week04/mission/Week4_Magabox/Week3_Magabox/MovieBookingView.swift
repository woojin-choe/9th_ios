//
//  MovieBookingView.swift
//  Week3_Magabox
//
//  Created by 최우진 on 10/13/25.
//

import SwiftUI
import Combine

// MARK: - Domain Models
struct BookingMovie: Identifiable, Hashable {
    let id: UUID = .init()
    let title: String
    let posterName: String   // Assets.xcassets 이미지 이름
    let ageBadge: String?    // 예: "15", "12" 등 (옵션)
}

enum TheaterArea: String, CaseIterable, Identifiable { // 강남, 홍대, 신촌
    case gangnam = "강남"
    case hongdae = "홍대"
    case sinchon = "신촌"
    var id: String { rawValue }
}

struct BookingShowTime: Identifiable, Hashable {
    let id: UUID = .init()
    let theater: TheaterArea
    let date: Date // 상영 날짜(일자)
    let time: String // "10:30", "14:10" 등
    let seatsRemain: Int
}

// MARK: - Fake Repository (Combine 기반 더미 데이터)
protocol BookingRepositoryType {
    func fetchMovies() -> AnyPublisher<[BookingMovie], Never>
    func fetchShowtimes() -> AnyPublisher<[BookingShowTime], Never>
}

final class BookingRepository: BookingRepositoryType {
    func fetchMovies() -> AnyPublisher<[BookingMovie], Never> {
        let items: [BookingMovie] = [
            .init(title: "무한성", posterName: "무한성", ageBadge: "15"),
            .init(title: "어쩔수가 없다", posterName: "어쩔수가 없다", ageBadge: "15"),
            .init(title: "얼굴", posterName: "얼굴", ageBadge: "15"),
            .init(title: "재개봉", posterName: "재개봉", ageBadge: "15"),
            .init(title: "F1", posterName: "f1", ageBadge: "12"),
            .init(title: "image1", posterName: "image 1", ageBadge: nil),
            .init(title: "image2", posterName: "image 2", ageBadge: nil),
            .init(title: "image3", posterName: "image 3", ageBadge: nil)
        ]
        return Just(items).eraseToAnyPublisher()
    }

    func fetchShowtimes() -> AnyPublisher<[BookingShowTime], Never> {
        let base = Calendar.current.startOfDay(for: Date())
        func d(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: base)! }
        let list: [BookingShowTime] = [
            .init(theater: .gangnam, date: d(0), time: "10:40", seatsRemain: 42),
            .init(theater: .gangnam, date: d(0), time: "13:10", seatsRemain: 5),
            .init(theater: .hongdae, date: d(1), time: "12:00", seatsRemain: 23),
            .init(theater: .hongdae, date: d(2), time: "19:40", seatsRemain: 11),
            .init(theater: .sinchon, date: d(3), time: "09:10", seatsRemain: 7),
            .init(theater: .sinchon, date: d(5), time: "21:30", seatsRemain: 18)
        ]
        return Just(list).eraseToAnyPublisher()
    }
}

// MARK: - ViewModel (MVVM + Combine)
final class MovieBookingViewModel: ObservableObject {
    // Input
    @Published var selectedMovie: BookingMovie? = nil
    @Published var selectedArea: TheaterArea? = nil
    @Published var selectedDate: Date? = nil

    // Output
    @Published private(set) var movies: [BookingMovie] = []
    @Published private(set) var daysOfWeek: [Date] = [] // 오늘 포함 7일
    @Published private(set) var showtimes: [BookingShowTime] = []

    // Derived state
    @Published private(set) var isAreaEnabled: Bool = false
    @Published private(set) var isDateEnabled: Bool = false

    private var bag = Set<AnyCancellable>()
    private let repo: BookingRepositoryType

    init(repo: BookingRepositoryType = BookingRepository()) {
        self.repo = repo
        makeDays()
        bind()
        load()
    }

    private func load() {
        repo.fetchMovies()
            .receive(on: DispatchQueue.main)
            .assign(to: &$movies)

        // 상영정보는 내부 저장 후 필터링해서 showtimes로 노출
        repo.fetchShowtimes()
            .combineLatest($selectedArea.removeDuplicates(), $selectedDate.removeDuplicates())
            .map { all, area, date -> [BookingShowTime] in
                guard let area, let date else { return [] }
                let day = Calendar.current.startOfDay(for: date)
                return all.filter { $0.theater == area && Calendar.current.isDate($0.date, inSameDayAs: day) }
                    .sorted { $0.time < $1.time }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$showtimes)
    }

    private func makeDays() {
        let today = Calendar.current.startOfDay(for: Date())
        daysOfWeek = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func bind() {
        $selectedMovie
            .map { $0 != nil }
            .removeDuplicates()
            .assign(to: &$isAreaEnabled)

        Publishers.CombineLatest($selectedMovie, $selectedArea)
            .map { movie, area in movie != nil && area != nil }
            .removeDuplicates()
            .assign(to: &$isDateEnabled)
    }

    // Helpers
    func selectTodayIfNeeded() {
        if selectedDate == nil { selectedDate = daysOfWeek.first }
    }
}

// MARK: - View
struct MovieBookingView: View {
    @StateObject private var vm = MovieBookingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ageAndTitle
                    posterCarousel
                    areaChips
                    dateSelector
                    showtimeSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        }
        .onAppear { vm.selectTodayIfNeeded() }
    }
}

// MARK: - Subviews
private extension MovieBookingView {
    var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.purple.ignoresSafeArea(edges: .top)
            Text("영화별 예매")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 14)
        }
        .frame(height: 100)
    }

    var ageAndTitle: some View {
        HStack(spacing: 8) {
            if let age = vm.selectedMovie?.ageBadge {
                Text(age)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.orange)
                    )
            }

            Text(vm.selectedMovie?.title ?? "어쩔수가없다")
                .font(.system(size: 24, weight: .semibold))

        }
    }

    var posterCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(vm.movies) { movie in
                    VStack(spacing: 6) {
                        Image(movie.posterName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(vm.selectedMovie == movie ? Color.purple : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture { vm.selectedMovie = movie }
                        Text(movie.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .frame(width: 96)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    var areaChips: some View {
        HStack(spacing: 10) {
            ForEach(TheaterArea.allCases) { area in
                Button {
                    guard vm.isAreaEnabled else { return }
                    vm.selectedArea = area
                } label: {
                    Text(area.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(vm.selectedArea == area ? Color.white : Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(vm.isAreaEnabled ? (vm.selectedArea == area ? Color.purple : Color.gray.opacity(0.2)) : Color.gray.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!vm.isAreaEnabled)
            }
        }
        .padding(.top, 8)
    }

    var dateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(vm.daysOfWeek, id: \.self) { day in
                    let selected = vm.selectedDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                    Button {
                        guard vm.isDateEnabled else { return }
                        vm.selectedDate = day
                    } label: {
                        VStack(spacing: 6) {
                            Text(dayFormatted(day, pattern: "M.dd"))
                                .font(.system(size: 18, weight: .bold))
                            Text(weekdayK(day))
                                .font(.system(size: 12))
                        }
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selected ? Color.purple : Color.gray.opacity(0.15))
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.isDateEnabled)
                }
            }
            .padding(.vertical, 12)
        }
    }

    var showtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.selectedMovie == nil {
                Text("영화 선택하지 않았습니다. 극장 선택 버튼 활성화되면 안됩니다")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else if vm.selectedArea == nil {
                Text("극장을 선택하세요. 포스터 선택 후 가능")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else if vm.showtimes.isEmpty {
                Text("선택한 극장에 상영시간표가 없습니다")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
            } else {
                ForEach(vm.showtimes) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("상영관 \(s.theater.rawValue)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(s.time)
                                .font(.system(size: 18, weight: .bold))
                        }
                        Spacer()
                        Text("잔여 \(s.seatsRemain)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Utilities
private func dayFormatted(_ date: Date, pattern: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = pattern
    return f.string(from: date)
}

private func weekdayK(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "E" // 월 화 수 ...
    var s = f.string(from: date)
    if Calendar.current.isDateInToday(date) { s = "오늘" }
    return s
}

#Preview {
    MovieBookingView()
}
