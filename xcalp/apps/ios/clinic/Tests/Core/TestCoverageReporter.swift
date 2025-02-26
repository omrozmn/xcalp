import Foundation
import Metal

final class TestCoverageReporter {
    private var coverageData: [String: ModuleCoverage] = [:]
    private var testResults: [String: [TestResult]] = [:]
    private let startTime: Date
    
    struct ModuleCoverage {
        var functionsCalled: Set<String> = []
        var totalFunctions: Int = 0
        var branchesCovered: Set<String> = []
        var totalBranches: Int = 0
        var linesExecuted: Set<Int> = []
        var totalLines: Int = 0
        
        var functionCoverage: Double {
            return Double(functionsCalled.count) / Double(totalFunctions)
        }
        
        var branchCoverage: Double {
            return Double(branchesCovered.count) / Double(totalBranches)
        }
        
        var lineCoverage: Double {
            return Double(linesExecuted.count) / Double(totalLines)
        }
    }
    
    struct TestResult {
        let name: String
        let duration: TimeInterval
        let passed: Bool
        let coverageIncrement: ModuleCoverage
        let timestamp: Date
    }
    
    struct CoverageReport {
        let totalCoverage: ModuleCoverage
        let moduleBreakdown: [String: ModuleCoverage]
        let uncoveredFunctions: [String: Set<String>]
        let testResults: [TestResult]
        let duration: TimeInterval
        let timestamp: Date
        
        var summary: String {
            """
            Test Coverage Report
            Generated: \(timestamp)
            Duration: \(String(format: "%.2f", duration))s
            
            Overall Coverage:
            - Functions: \(String(format: "%.1f%%", totalCoverage.functionCoverage * 100))
            - Branches: \(String(format: "%.1f%%", totalCoverage.branchCoverage * 100))
            - Lines: \(String(format: "%.1f%%", totalCoverage.lineCoverage * 100))
            
            Module Breakdown:
            \(moduleBreakdown.map { module, coverage in
                """
                \(module):
                  Functions: \(String(format: "%.1f%%", coverage.functionCoverage * 100))
                  Branches: \(String(format: "%.1f%%", coverage.branchCoverage * 100))
                  Lines: \(String(format: "%.1f%%", coverage.lineCoverage * 100))
                """
            }.joined(separator: "\n"))
            
            Uncovered Functions:
            \(uncoveredFunctions.map { module, functions in
                """
                \(module):
                \(functions.sorted().map { "  - \($0)" }.joined(separator: "\n"))
                """
            }.joined(separator: "\n"))
            """
        }
    }
    
    init() {
        self.startTime = Date()
    }
    
    func beginTracking(module: String, totalFunctions: Int, totalBranches: Int, totalLines: Int) {
        coverageData[module] = ModuleCoverage(
            totalFunctions: totalFunctions,
            totalBranches: totalBranches,
            totalLines: totalLines
        )
    }
    
    func recordFunctionCall(_ function: String, inModule module: String) {
        coverageData[module]?.functionsCalled.insert(function)
    }
    
    func recordBranchExecution(_ branch: String, inModule module: String) {
        coverageData[module]?.branchesCovered.insert(branch)
    }
    
    func recordLineExecution(_ line: Int, inModule module: String) {
        coverageData[module]?.linesExecuted.insert(line)
    }
    
    func recordTestResult(
        name: String,
        duration: TimeInterval,
        passed: Bool,
        coverageIncrement: ModuleCoverage
    ) {
        let result = TestResult(
            name: name,
            duration: duration,
            passed: passed,
            coverageIncrement: coverageIncrement,
            timestamp: Date()
        )
        
        testResults[name, default: []].append(result)
    }
    
    func generateReport() -> CoverageReport {
        let totalCoverage = calculateTotalCoverage()
        let uncoveredFunctions = findUncoveredFunctions()
        let allResults = testResults.values.flatMap { $0 }
        
        return CoverageReport(
            totalCoverage: totalCoverage,
            moduleBreakdown: coverageData,
            uncoveredFunctions: uncoveredFunctions,
            testResults: allResults,
            duration: Date().timeIntervalSince(startTime),
            timestamp: Date()
        )
    }
    
    func exportReport(_ report: CoverageReport, to url: URL) throws {
        // Generate HTML report
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Coverage Report</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 2em; }
                .module { margin: 1em 0; padding: 1em; border: 1px solid #ccc; }
                .good { color: green; }
                .warning { color: orange; }
                .poor { color: red; }
                .metric { margin: 0.5em 0; }
            </style>
        </head>
        <body>
            <h1>Test Coverage Report</h1>
            <p>Generated: \(report.timestamp)</p>
            <p>Duration: \(String(format: "%.2f", report.duration))s</p>
            
            <h2>Overall Coverage</h2>
            \(generateCoverageHTML(report.totalCoverage))
            
            <h2>Module Breakdown</h2>
            \(report.moduleBreakdown.map { module, coverage in
                """
                <div class="module">
                    <h3>\(module)</h3>
                    \(generateCoverageHTML(coverage))
                </div>
                """
            }.joined(separator: "\n"))
            
            <h2>Uncovered Functions</h2>
            \(report.uncoveredFunctions.map { module, functions in
                """
                <div class="module">
                    <h3>\(module)</h3>
                    <ul>
                        \(functions.sorted().map { "<li>\($0)</li>" }.joined(separator: "\n"))
                    </ul>
                </div>
                """
            }.joined(separator: "\n"))
            
            <h2>Test Results</h2>
            <table>
                <tr>
                    <th>Test</th>
                    <th>Duration</th>
                    <th>Status</th>
                    <th>Coverage Impact</th>
                </tr>
                \(report.testResults.map { result in
                    """
                    <tr>
                        <td>\(result.name)</td>
                        <td>\(String(format: "%.3f", result.duration))s</td>
                        <td class="\(result.passed ? "good" : "poor")">\(result.passed ? "Pass" : "Fail")</td>
                        <td>\(String(format: "%.1f%%", result.coverageIncrement.lineCoverage * 100))</td>
                    </tr>
                    """
                }.joined(separator: "\n"))
            </table>
        </body>
        </html>
        """
        
        try html.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func calculateTotalCoverage() -> ModuleCoverage {
        var total = ModuleCoverage()
        
        for coverage in coverageData.values {
            total.totalFunctions += coverage.totalFunctions
            total.totalBranches += coverage.totalBranches
            total.totalLines += coverage.totalLines
            total.functionsCalled.formUnion(coverage.functionsCalled)
            total.branchesCovered.formUnion(coverage.branchesCovered)
            total.linesExecuted.formUnion(coverage.linesExecuted)
        }
        
        return total
    }
    
    private func findUncoveredFunctions() -> [String: Set<String>] {
        var uncovered: [String: Set<String>] = [:]
        
        for (module, coverage) in coverageData {
            let allFunctions = Set(0..<coverage.totalFunctions).map { "function_\($0)" }
            uncovered[module] = allFunctions.subtracting(coverage.functionsCalled)
        }
        
        return uncovered
    }
    
    private func generateCoverageHTML(_ coverage: ModuleCoverage) -> String {
        return """
        <div class="coverage">
            <div class="metric \(getCoverageClass(coverage.functionCoverage))">
                Functions: \(String(format: "%.1f%%", coverage.functionCoverage * 100))
            </div>
            <div class="metric \(getCoverageClass(coverage.branchCoverage))">
                Branches: \(String(format: "%.1f%%", coverage.branchCoverage * 100))
            </div>
            <div class="metric \(getCoverageClass(coverage.lineCoverage))">
                Lines: \(String(format: "%.1f%%", coverage.lineCoverage * 100))
            </div>
        </div>
        """
    }
    
    private func getCoverageClass(_ coverage: Double) -> String {
        switch coverage {
        case 0.9...: return "good"
        case 0.75...: return "warning"
        default: return "poor"
        }
    }
}