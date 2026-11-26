import Foundation

public protocol MonitorSource: Sendable {
    @MainActor
    func fetchEvents(
        definition: MonitorDefinition,
        cursor: String?,
        session: GitHubSession
    ) async throws -> (events: [MonitorEvent], fetchedEvents: [MonitorEvent], nextCursor: String?)
}

public struct AccountEventsMonitorSource: MonitorSource {
    public init() {}

    @MainActor
    public func fetchEvents(
        definition: MonitorDefinition,
        cursor: String?,
        session: GitHubSession
    ) async throws -> (events: [MonitorEvent], fetchedEvents: [MonitorEvent], nextCursor: String?) {
        guard case let .account(login) = definition.target, let restClient = session.restClient else {
            return ([], [], cursor)
        }

        let rawEvents = try await restClient.fetchUserEvents(username: login)
        let fetchedEvents = rawEvents.map { monitorEvent(from: $0, definition: definition) }
        let (eventsToProcess, nextCursor) = rawEventsSinceCursor(rawEvents, cursor: cursor)
        let filteredEvents = eventsToProcess.filter { event in
            let kind = event.monitorKind
            if let enabled = definition.eventToggles[kind] {
                return enabled
            }
            return true
        }

        var monitorEvents = filteredEvents.map { monitorEvent(from: $0, definition: definition) }
        monitorEvents.sort { $0.occurredAt < $1.occurredAt }

        return (monitorEvents, fetchedEvents, nextCursor)
    }
}

public struct RepositoryEventsMonitorSource: MonitorSource {
    public init() {}

    @MainActor
    public func fetchEvents(
        definition: MonitorDefinition,
        cursor: String?,
        session: GitHubSession
    ) async throws -> (events: [MonitorEvent], fetchedEvents: [MonitorEvent], nextCursor: String?) {
        guard case let .repository(owner, name) = definition.target, let restClient = session.restClient else {
            return ([], [], cursor)
        }

        let rawEvents = try await restClient.fetchRepoEvents(owner: owner, repo: name)
        let fetchedEvents = rawEvents.map { monitorEvent(from: $0, definition: definition) }
        let (eventsToProcess, nextCursor) = rawEventsSinceCursor(rawEvents, cursor: cursor)
        let filteredEvents = eventsToProcess.filter { event in
            let kind = event.monitorKind
            if let enabled = definition.eventToggles[kind] {
                return enabled
            }
            return true
        }

        var monitorEvents = filteredEvents.map { monitorEvent(from: $0, definition: definition) }
        monitorEvents.sort { $0.occurredAt < $1.occurredAt }

        return (monitorEvents, fetchedEvents, nextCursor)
    }
}

private func monitorEvent(from event: GitHubEvent, definition: MonitorDefinition) -> MonitorEvent {
    MonitorEvent(
        id: monitorEventId(definition: definition, sourceId: event.id),
        kind: event.monitorKind,
        targetId: definition.id,
        actor: event.actor.login,
        repo: event.repo.name,
        title: event.monitorTitle,
        url: event.monitorURL,
        occurredAt: event.createdAt,
        number: event.monitorNumber
    )
}

func rawEventsSinceCursor(_ rawEvents: [GitHubEvent], cursor: String?) -> (events: [GitHubEvent], nextCursor: String?) {
    let nextCursor = rawEvents.first?.id ?? cursor
    guard let cursor, let cursorIndex = rawEvents.firstIndex(where: { $0.id == cursor }) else {
        return (rawEvents, nextCursor)
    }
    return (Array(rawEvents.prefix(upTo: cursorIndex)), nextCursor)
}

private func monitorEventId(definition: MonitorDefinition, sourceId: String) -> String {
    "\(definition.id.uuidString):\(sourceId)"
}
