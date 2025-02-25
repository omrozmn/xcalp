import Foundation
import PDFKit
import Charts

final class ClinicalReportGenerator {
    private let errorHandler = XCErrorHandler.shared
    private let performanceMonitor = XCPerformanceMonitor.shared
    
    struct ReportData {
        let patientInfo: PatientInfo
        let scanDate: Date
        let scanQualityMetrics: QualityMetrics
        let meshMetrics: MeshQualityMetrics
        let clinicalFindings: ClinicalFindings
        let recommendations: String
    }
    
    struct PatientInfo {
        let id: String
        let name: String
        let age: Int
        let gender: String
        let medicalHistory: String
    }
    
    struct ClinicalFindings {
        let hairlineClassification: String
        let densityMeasurements: [String: Float]
        let recommendations: [String]
        let additionalNotes: String
    }
    
    func generateReport(data: ReportData) -> Result<PDFDocument, ReportGenerationError> {
        performanceMonitor.startMeasuring("ReportGeneration")
        
        do {
            let pdfDocument = PDFDocument()
            
            // Generate report sections
            try addCoverPage(to: pdfDocument, with: data)
            try addPatientInformation(to: pdfDocument, with: data)
            try addScanResults(to: pdfDocument, with: data)
            try addClinicalAnalysis(to: pdfDocument, with: data)
            try addRecommendations(to: pdfDocument, with: data)
            
            performanceMonitor.stopMeasuring("ReportGeneration")
            return .success(pdfDocument)
            
        } catch {
            errorHandler.handle(error, severity: .medium)
            performanceMonitor.stopMeasuring("ReportGeneration")
            return .failure(.generationFailed)
        }
    }
    
    private func addCoverPage(to document: PDFDocument, with data: ReportData) throws {
        let coverPage = PDFPage()
        let title = "Clinical Hair Analysis Report"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        
        // Add cover page content
        let content = """
        \(title)
        
        Patient ID: \(data.patientInfo.id)
        Date: \(dateFormatter.string(from: data.scanDate))
        
        Generated by Xcalp Clinic
        """
        
        // Add content to page
        addFormattedText(content, to: coverPage, at: CGPoint(x: 50, y: 500))
        document.insert(coverPage, at: 0)
    }
    
    private func addPatientInformation(to document: PDFDocument, with data: ReportData) throws {
        let page = PDFPage()
        
        let content = """
        Patient Information
        ------------------
        Name: \(data.patientInfo.name)
        Age: \(data.patientInfo.age)
        Gender: \(data.patientInfo.gender)
        
        Medical History
        --------------
        \(data.patientInfo.medicalHistory)
        """
        
        addFormattedText(content, to: page, at: CGPoint(x: 50, y: 700))
        document.insert(page, at: document.pageCount)
    }
    
    private func addScanResults(to document: PDFDocument, with data: ReportData) throws {
        let page = PDFPage()
        
        // Create quality metrics visualization
        let qualityChart = createQualityMetricsChart(data.scanQualityMetrics)
        addChart(qualityChart, to: page, at: CGPoint(x: 50, y: 500))
        
        // Add mesh metrics
        let meshMetricsContent = """
        Mesh Analysis Results
        -------------------
        Surface Completeness: \(data.meshMetrics.surfaceCompleteness)%
        Feature Preservation: \(data.meshMetrics.featurePreservation)%
        Noise Level: \(data.meshMetrics.noiseLevel)mm
        """
        
        addFormattedText(meshMetricsContent, to: page, at: CGPoint(x: 50, y: 300))
        document.insert(page, at: document.pageCount)
    }
    
    private func addClinicalAnalysis(to document: PDFDocument, with data: ReportData) throws {
        let page = PDFPage()
        
        // Add density measurements visualization
        let densityChart = createDensityChart(data.clinicalFindings.densityMeasurements)
        addChart(densityChart, to: page, at: CGPoint(x: 50, y: 500))
        
        let content = """
        Clinical Analysis
        ---------------
        Hairline Classification: \(data.clinicalFindings.hairlineClassification)
        
        Density Measurements
        ------------------
        \(formatDensityMeasurements(data.clinicalFindings.densityMeasurements))
        
        Additional Notes
        --------------
        \(data.clinicalFindings.additionalNotes)
        """
        
        addFormattedText(content, to: page, at: CGPoint(x: 50, y: 300))
        document.insert(page, at: document.pageCount)
    }
    
    private func addRecommendations(to document: PDFDocument, with data: ReportData) throws {
        let page = PDFPage()
        
        let content = """
        Treatment Recommendations
        ----------------------
        \(formatRecommendations(data.clinicalFindings.recommendations))
        
        Additional Comments
        -----------------
        \(data.recommendations)
        """
        
        addFormattedText(content, to: page, at: CGPoint(x: 50, y: 700))
        document.insert(page, at: document.pageCount)
    }
    
    private func createQualityMetricsChart(_ metrics: QualityMetrics) -> UIView {
        // Create bar chart for quality metrics
        let chart = BarChartView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        
        let entries = [
            BarChartDataEntry(x: 0, y: Double(metrics.pointDensity)),
            BarChartDataEntry(x: 1, y: Double(metrics.surfaceCompleteness)),
            BarChartDataEntry(x: 2, y: Double(metrics.featurePreservation))
        ]
        
        let dataSet = BarChartDataSet(entries: entries, label: "Scan Quality Metrics")
        dataSet.colors = [.systemBlue]
        
        chart.data = BarChartData(dataSet: dataSet)
        chart.xAxis.valueFormatter = IndexAxisValueFormatter(values: ["Point Density", "Completeness", "Feature Preservation"])
        
        return chart
    }
    
    private func createDensityChart(_ measurements: [String: Float]) -> UIView {
        // Create line chart for density measurements
        let chart = LineChartView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        
        let entries = measurements.enumerated().map { index, measurement in
            ChartDataEntry(x: Double(index), y: Double(measurement.value))
        }
        
        let dataSet = LineChartDataSet(entries: entries, label: "Density Distribution")
        dataSet.colors = [.systemBlue]
        dataSet.circleColors = [.systemBlue]
        
        chart.data = LineChartData(dataSet: dataSet)
        chart.xAxis.valueFormatter = IndexAxisValueFormatter(values: Array(measurements.keys))
        
        return chart
    }
    
    private func formatDensityMeasurements(_ measurements: [String: Float]) -> String {
        return measurements.map { region, density in
            "\(region): \(density) hairs/cm²"
        }.joined(separator: "\n")
    }
    
    private func formatRecommendations(_ recommendations: [String]) -> String {
        return recommendations.enumerated().map { index, recommendation in
            "\(index + 1). \(recommendation)"
        }.joined(separator: "\n")
    }
    
    private func addFormattedText(_ text: String, to page: PDFPage, at point: CGPoint) {
        // Add formatted text to PDF page
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        page.addAttributedText(attributedString, at: point)
    }
    
    private func addChart(_ chart: UIView, to page: PDFPage, at point: CGPoint) {
        // Convert chart to image and add to PDF
        UIGraphicsBeginImageContextWithOptions(chart.bounds.size, false, 0.0)
        chart.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let image = image {
            page.addImage(image, at: point)
        }
    }
}

enum ReportGenerationError: Error {
    case generationFailed
    case invalidData
    case chartGenerationFailed
    case pdfCreationFailed
}