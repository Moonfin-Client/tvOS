import Foundation
import os

enum SeerrPersonDetailsState {
    case loading
    case loaded
    case error(String)
}

@MainActor
final class SeerrPersonDetailsViewModel: ObservableObject {
    @Published var state: SeerrPersonDetailsState = .loading
    @Published var details: SeerrPersonDetailsDto?
    @Published var appearances: [SeerrDiscoverItemDto] = []
    @Published var isBioExpanded = false

    private let personId: Int
    private let seerrRepository: SeerrRepositoryProtocol

    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SeerrPersonDetails")

    var name: String { details?.name ?? "" }

    var profileUrl: String? {
        details?.profilePath.map { SeerrImageUrl.profile($0) }
    }

    var biography: String? {
        guard let bio = details?.biography, !bio.isEmpty else { return nil }
        return bio
    }

    var birthInfo: String? {
        var parts: [String] = []
        if let birthday = details?.birthday {
            parts.append(Strings.seerrBornDate(formatDate(birthday)))
        }
        if let place = details?.placeOfBirth, !place.isEmpty {
            parts.append(Strings.seerrInPlace(place))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    var deathInfo: String? {
        guard let deathday = details?.deathday else { return nil }
        return Strings.seerrDiedDate(formatDate(deathday))
    }

    var knownFor: String? {
        details?.knownForDepartment
    }

    init(personId: Int, seerrRepository: SeerrRepositoryProtocol) {
        self.personId = personId
        self.seerrRepository = seerrRepository
    }

    func loadDetails() {
        guard case .loading = state else { return }

        Task {
            do {
                details = try await seerrRepository.getPersonDetails(personId: personId)
                state = .loaded
                loadCredits()
            } catch {
                logger.error("Failed to load person details: \(error.localizedDescription)")
                state = .error(error.localizedDescription)
            }
        }
    }

    private func loadCredits() {
        Task {
            do {
                let credits = try await seerrRepository.getPersonCombinedCredits(personId: personId)
                appearances = credits.cast
                    .filter { $0.posterPath != nil }
                    .sorted { $0.displayTitle < $1.displayTitle }
            } catch {
                logger.warning("Failed to load person credits: \(error.localizedDescription)")
            }
        }
    }

    func itemJson(_ item: SeerrDiscoverItemDto) -> String? {
        guard let data = try? JSONEncoder().encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
