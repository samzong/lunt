import Foundation
import os

public enum ActivityFilter: String, CaseIterable, Sendable {
    case all
    case created
    case assigned
    case mentioned
    case reviewRequested
}

@Observable
@MainActor
public class ActivityService {
    public var items: [SearchResultItem] {
        let all = (createdItems + assignedItems + mentionedItems + reviewRequestedItems)
        var seenIds = Set<String>()
        var merged: [SearchResultItem] = []
        for item in all where !seenIds.contains(item.id) {
            seenIds.insert(item.id)
            merged.append(item)
        }
        return merged.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var createdItems: [SearchResultItem] {
        (createdIssues + createdPRs).sorted { $0.updatedAt > $1.updatedAt }
    }

    public var assignedItems: [SearchResultItem] {
        (assignedIssues + assignedPRs).sorted { $0.updatedAt > $1.updatedAt }
    }

    public var mentionedItems: [SearchResultItem] {
        (mentionedIssues + mentionedPRs).sorted { $0.updatedAt > $1.updatedAt }
    }

    public var reviewRequestedItems: [SearchResultItem] {
        reviewRequestedPRs.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var createdIssues: [SearchResultItem] = []
    private var createdPRs: [SearchResultItem] = []

    private var assignedIssues: [SearchResultItem] = []
    private var assignedPRs: [SearchResultItem] = []

    private var mentionedIssues: [SearchResultItem] = []
    private var mentionedPRs: [SearchResultItem] = []

    private var reviewRequestedPRs: [SearchResultItem] = []

    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastSyncedAt: Date?

    private let session: GitHubSession
    private let logger = Logger(subsystem: "com.samzong.lunt", category: "ActivityService")
    @ObservationIgnored private nonisolated(unsafe) var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    private var activeFetchType: SearchResultItem.ItemType?
    private var refreshInterval: TimeInterval = 60

    public init(session: GitHubSession) {
        self.session = session
    }

    deinit {
        autoRefreshTask?.cancel()
        activeFetchTask?.cancel()
    }

    public func configure(interval: TimeInterval = 60) {
        refreshInterval = max(1, interval)
        startAutoRefresh()
    }

    public func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(1, interval)
        if autoRefreshTask != nil {
            startAutoRefresh()
        }
    }

    public func clearToken() {
        stopAutoRefresh()
        activeFetchTask?.cancel()
        activeFetchTask = nil
        activeFetchType = nil
        createdIssues = []
        createdPRs = []
        assignedIssues = []
        assignedPRs = []
        mentionedIssues = []
        mentionedPRs = []
        reviewRequestedPRs = []
        errorMessage = nil
        lastSyncedAt = nil
        isLoading = false
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        let interval = refreshInterval
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.fetchMyItems()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    public func fetchMyItems(type: SearchResultItem.ItemType? = nil) async {
        while let activeTask = activeFetchTask {
            let inFlightType = activeFetchType
            await activeTask.value
            if inFlightType == nil || inFlightType == type {
                return
            }
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activeFetchTask = nil
                self.activeFetchType = nil
            }
            await self.performFetchMyItems(type: type)
        }
        activeFetchType = type
        activeFetchTask = task
        await task.value
    }

    private func performFetchMyItems(type: SearchResultItem.ItemType?) async {
        guard let graphqlClient = session.graphqlClient else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var nextCreatedIssues = createdIssues
            var nextAssignedIssues = assignedIssues
            var nextMentionedIssues = mentionedIssues
            var nextCreatedPRs = createdPRs
            var nextAssignedPRs = assignedPRs
            var nextMentionedPRs = mentionedPRs
            var nextReviewRequestedPRs = reviewRequestedPRs

            if type == nil || type == .issue {
                async let created = graphqlClient.search(query: "is:open is:issue author:@me", first: 30)
                async let assigned = graphqlClient.search(query: "is:open is:issue assignee:@me", first: 30)
                async let mentioned = graphqlClient.search(query: "is:open is:issue mentions:@me", first: 30)

                nextCreatedIssues = try await created
                nextAssignedIssues = try await assigned
                nextMentionedIssues = try await mentioned
            }

            if type == nil || type == .pullRequest {
                async let created = graphqlClient.search(query: "is:open is:pr author:@me", first: 30)
                async let assigned = graphqlClient.search(query: "is:open is:pr assignee:@me", first: 30)
                async let mentioned = graphqlClient.search(query: "is:open is:pr mentions:@me", first: 30)
                async let reviewRequested = graphqlClient.search(query: "is:open is:pr review-requested:@me", first: 30)

                nextCreatedPRs = try await created
                nextAssignedPRs = try await assigned
                nextMentionedPRs = try await mentioned
                nextReviewRequestedPRs = try await reviewRequested
            }

            guard !Task.isCancelled, session.isAuthenticated else {
                isLoading = false
                return
            }

            if type == nil || type == .issue {
                createdIssues = nextCreatedIssues
                assignedIssues = nextAssignedIssues
                mentionedIssues = nextMentionedIssues
            }

            if type == nil || type == .pullRequest {
                createdPRs = nextCreatedPRs
                assignedPRs = nextAssignedPRs
                mentionedPRs = nextMentionedPRs
                reviewRequestedPRs = nextReviewRequestedPRs
            }

            lastSyncedAt = Date()
        } catch {
            if !Task.isCancelled {
                logger.error("Failed to fetch activity items: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    public func items(for filter: ActivityFilter) -> [SearchResultItem] {
        switch filter {
        case .all: items
        case .created: createdItems
        case .assigned: assignedItems
        case .mentioned: mentionedItems
        case .reviewRequested: reviewRequestedItems
        }
    }

    public func pullRequests(for filter: ActivityFilter) -> [SearchResultItem] {
        items(for: filter).filter { $0.itemType == .pullRequest }
    }

    public func issues(for filter: ActivityFilter) -> [SearchResultItem] {
        items(for: filter).filter { $0.itemType == .issue }
    }

    public func count(for filter: ActivityFilter) -> Int {
        items(for: filter).count
    }
}
