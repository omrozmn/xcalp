import Foundation
import Metal
import Combine

final class TestObservationLogger {
    private let queue = DispatchQueue(label: "com.xcalp.testobservation")
    private var observations: [Observation] = []
    private var currentSession: ObservationSession?
    private let observationSubject = PassthroughSubject<Observation, Never>()
    
    struct Observation: Codable {
        let id: UUID
        let timestamp: Date
        let category: Category
        let detail: String
        let measurements: [String: Double]
        let context: [String: String]
        let sessionId: UUID
        
        enum Category: String, Codable {
            case performance
            case quality
            case resource
            case behavior
            case error
            case recovery
        }
    }
    
    struct ObservationSession: Codable {
        let id: UUID
        let startTime: Date
        var endTime: Date?
        let configuration: TestConfiguration
        var observations: [Observation]
        
        var duration: TimeInterval? {
            guard let endTime = endTime else { return nil }
            return endTime.timeIntervalSince(startTime)
        }
    }
    
    struct ObservationPattern {
        let category: Observation.Category
        let predicate: (Observation) -> Bool
        let threshold: Int
        let timeWindow: TimeInterval
        let action: (([Observation]) -> Void)?
    }
    
    var observationPublisher: AnyPublisher<Observation, Never> {
        return observationSubject.eraseToAnyPublisher()
    }
    
    private var patterns: [ObservationPattern] = []
    
    func beginSession(configuration: TestConfiguration) {
        queue.async {
            self.currentSession = ObservationSession(
                id: UUID(),
                startTime: Date(),
                endTime: nil,
                configuration: configuration,
                observations: []
            )
        }
    }
    
    func endSession() {
        queue.async {
            guard var session = self.currentSession else { return }
            session.endTime = Date()
            
            // Archive session data
            self.archiveSession(session)
            self.currentSession = nil
        }
    }
    
    func observe(
        category: Observation.Category,
        detail: String,
        measurements: [String: Double] = [:],
        context: [String: String] = [:]
    ) {
        queue.async {
            guard let session = self.currentSession else { return }
            
            let observation = Observation(
                id: UUID(),
                timestamp: Date(),
                category: category,
                detail: detail,
                measurements: measurements,
                context: context,
                sessionId: session.id
            )
            
            self.observations.append(observation)
            self.observationSubject.send(observation)
            
            // Check for patterns
            self.checkPatterns(observation)
        }
    }
    
    func registerPattern(_ pattern: ObservationPattern) {
        queue.async {
            self.patterns.append(pattern)
        }
    }
    
    func generateReport(timeRange: TimeInterval? = nil) -> ObservationReport {
        var report = ObservationReport()
        let relevantObservations: [Observation]
        
        if let timeRange = timeRange {
            let cutoffDate = Date().addingTimeInterval(-timeRange)
            relevantObservations = observations.filter { $0.timestamp >= cutoffDate }
        } else {
            relevantObservations = observations
        }
        
        // Process observations by category
        for category in Observation.Category.allCases {
            let categoryObservations = relevantObservations.filter { $0.category == category }
            report.addCategoryAnalysis(
                category: category,
                observations: categoryObservations
            )
        }
        
        return report
    }
    
    private func checkPatterns(_ observation: Observation) {
        for pattern in patterns {
            guard pattern.category == observation.category else { continue }
            
            let timeWindow = observation.timestamp.addingTimeInterval(-pattern.timeWindow)
            let matchingObservations = observations.filter {
                $0.category == pattern.category &&
                $0.timestamp >= timeWindow &&
                pattern.predicate($0)
            }
            
            if matchingObservations.count >= pattern.threshold {
                pattern.action?(matchingObservations)
            }
        }
    }
    
    private func archiveSession(_ session: ObservationSession) {
        // Archive session data to persistent storage
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let sessionData = try? encoder.encode(session) else { return }
        
        let filename = "test_session_\(session.id.uuidString).json"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        try? sessionData.write(to: fileURL)
    }
}

struct ObservationReport {
    private var categoryAnalysis: [Observation.Category: CategoryAnalysis] = [:]
    
    struct CategoryAnalysis {
        let observationCount: Int
        let timeDistribution: [Date: Int]
        let commonPatterns: [(pattern: String, count: Int)]
        let metrics: [String: Statistics]
        
        struct Statistics {
            let mean: Double
            let standardDeviation: Double
            let min: Double
            let max: Double
        }
    }
    
    mutating func addCategoryAnalysis(
        category: Observation.Category,
        observations: [Observation]
    ) {
        let timeDistribution = Dictionary(grouping: observations) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }.mapValues { $0.count }
        
        let metrics = processMetrics(from: observations)
        let patterns = findCommonPatterns(in: observations)
        
        categoryAnalysis[category] = CategoryAnalysis(
            observationCount: observations.count,
            timeDistribution: timeDistribution,
            commonPatterns: patterns,
            metrics: metrics
        )
    }
    
    private func processMetrics(
        from observations: [Observation]
    ) -> [String: CategoryAnalysis.Statistics] {
        var metrics: [String: CategoryAnalysis.Statistics] = [:]
        
        // Group measurements by metric name
        let measurementsByMetric = Dictionary(
            grouping: observations.flatMap { observation in
                observation.measurements.map { ($0.key, $0.value) }
            }
        ) { $0.0 }
        
        // Calculate statistics for each metric
        for (metricName, measurements) in measurementsByMetric {
            let values = measurements.map { $0.1 }
            metrics[metricName] = calculateStatistics(values)
        }
        
        return metrics
    }
    
    private func calculateStatistics(_ values: [Double]) -> CategoryAnalysis.Statistics {
        let count = Double(values.count)
        let sum = values.reduce(0, +)
        let mean = sum / count
        
        let sumSquaredDiff = values.reduce(0) { $0 + pow($1 - mean, 2) }
        let standardDeviation = sqrt(sumSquaredDiff / count)
        
        return CategoryAnalysis.Statistics(
            mean: mean,
            standardDeviation: standardDeviation,
            min: values.min() ?? 0,
            max: values.max() ?? 0
        )
    }
    
    private func findCommonPatterns(
        in observations: [Observation]
    ) -> [(pattern: String, count: Int)] {
        // Simple pattern detection based on detail string frequency
        let patternCounts = Dictionary(grouping: observations) { $0.detail }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
        
        return patternCounts
    }
}