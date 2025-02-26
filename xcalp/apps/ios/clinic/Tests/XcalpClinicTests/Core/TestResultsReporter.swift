import Foundation
import Charts
import MetalKit

final class TestResultsReporter {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    func generateReport(
        performanceResults: PerformanceReport,
        concurrentResults: ConcurrentTestResult,
        meshQualities: [String: QualityMetrics]
    ) -> TestReport {
        let timestamp = Date()
        
        // Generate performance summary
        let performanceSummary = generatePerformanceSummary(from: performanceResults)
        
        // Generate quality summary
        let qualitySummary = generateQualitySummary(from: meshQualities)
        
        // Generate concurrency summary
        let concurrencySummary = generateConcurrencySummary(from: concurrentResults)
        
        // Create full report
        return TestReport(
            timestamp: timestamp,
            performanceSummary: performanceSummary,
            qualitySummary: qualitySummary,
            concurrencySummary: concurrencySummary,
            recommendations: generateRecommendations(
                performance: performanceResults,
                quality: meshQualities,
                concurrency: concurrentResults
            )
        )
    }
    
    func exportReport(_ report: TestReport, to url: URL) throws {
        // Generate markdown report
        var markdown = """
        # Mesh Processing Pipeline Test Report
        Generated: \(dateFormatter.string(from: report.timestamp))
        
        ## Performance Summary
        \(report.performanceSummary)
        
        ## Quality Metrics
        \(report.qualitySummary)
        
        ## Concurrency Analysis
        \(report.concurrencySummary)
        
        ## Recommendations
        \(report.recommendations.joined(separator: "\n"))
        """
        
        // Add charts if available
        if let charts = generateCharts(from: report) {
            markdown += "\n\n## Visual Analysis\n"
            markdown += charts
        }
        
        // Write to file
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generatePerformanceSummary(from report: PerformanceReport) -> String {
        return """
        ### Processing Times
        - Average processing time: \(String(format: "%.3f", report.averageProcessingTime))s
        - Peak memory usage: \(ByteCountFormatter.string(fromByteCount: Int64(report.peakMemoryUsage), countStyle: .memory))
        
        ### Performance Metrics
        \(report.metrics.map { "- \($0.key): \($0.value)" }.joined(separator: "\n"))
        """
    }
    
    private func generateQualitySummary(from qualities: [String: QualityMetrics]) -> String {
        return qualities.map { meshId, metrics in
            """
            ### \(meshId)
            - Point density: \(String(format: "%.1f", metrics.pointDensity)) points/m³
            - Surface completeness: \(String(format: "%.1f%%", metrics.surfaceCompleteness * 100))
            - Noise level: \(String(format: "%.3f", metrics.noiseLevel))mm
            - Feature preservation: \(String(format: "%.1f%%", metrics.featurePreservation * 100))
            """
        }.joined(separator: "\n\n")
    }
    
    private func generateConcurrencySummary(from results: ConcurrentTestResult) -> String {
        return """
        ### Concurrent Operation Results
        - Successful operations: \(results.successfulOperations)
        - Failed operations: \(results.failedOperations)
        - Average processing time: \(String(format: "%.3f", results.averageProcessingTime))s
        - Peak memory under concurrency: \(ByteCountFormatter.string(fromByteCount: Int64(results.peakMemoryUsage), countStyle: .memory))
        
        ### Errors Encountered
        \(results.errors.map { "- \($0.localizedDescription)" }.joined(separator: "\n"))
        """
    }
    
    private func generateRecommendations(
        performance: PerformanceReport,
        quality: [String: QualityMetrics],
        concurrency: ConcurrentTestResult
    ) -> [String] {
        var recommendations: [String] = []
        
        // Performance recommendations
        if performance.averageProcessingTime > TestConfiguration.maxProcessingTime {
            recommendations.append("⚠️ Consider optimizing mesh processing pipeline to reduce processing time")
        }
        
        if performance.peakMemoryUsage > UInt64(TestConfiguration.maxMemoryUsage) {
            recommendations.append("⚠️ Implement memory optimization strategies to reduce peak memory usage")
        }
        
        // Quality recommendations
        for (meshId, metrics) in quality {
            if metrics.pointDensity < 100 {
                recommendations.append("⚠️ Increase point density for \(meshId)")
            }
            if metrics.surfaceCompleteness < 0.9 {
                recommendations.append("⚠️ Improve surface completeness for \(meshId)")
            }
            if metrics.noiseLevel > 0.1 {
                recommendations.append("⚠️ Enhance noise reduction for \(meshId)")
            }
        }
        
        // Concurrency recommendations
        if concurrency.failedOperations > 0 {
            recommendations.append("⚠️ Address concurrent operation failures")
        }
        
        return recommendations
    }
    
    private func generateCharts(from report: TestReport) -> String? {
        // Generate charts using Charts framework
        // Implementation would go here
        return nil
    }
}

struct TestReport {
    let timestamp: Date
    let performanceSummary: String
    let qualitySummary: String
    let concurrencySummary: String
    let recommendations: [String]
    
    var isSuccessful: Bool {
        return recommendations.isEmpty
    }
}