import Foundation
import PDFKit
import UIKit

public final class DocumentGenerator {
    private let dateFormatter: DateFormatter
    
    public init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
    }
    
    public func generateTreatmentPlan(
        measurements: Measurements,
        graftCalculation: GraftCalculation,
        patientInfo: PatientInfo
    ) throws -> Data {
        let pdfDocument = PDFDocument()
        let page = PDFPage()
        
        let content = NSMutableAttributedString()
        
        // Header
        content.append(formatHeader(patientInfo))
        
        // Treatment Summary
        content.append(formatMeasurements(measurements))
        content.append(formatGraftCalculations(graftCalculation))
        
        // Zone Details
        content.append(formatZoneDetails(graftCalculation.zones))
        
        // Visualization placeholders
        content.append(formatVisualization())
        
        // Terms and conditions
        content.append(formatTerms())
        
        // Create PDF
        let pdfData = try render(content)
        return pdfData
    }
    
    private func formatHeader(_ patient: PatientInfo) -> NSAttributedString {
        let header = NSMutableAttributedString()
        header.append(NSAttributedString(
            string: "Hair Transplantation Treatment Plan\n",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 24)]
        ))
        header.append(NSAttributedString(
            string: "Date: \(dateFormatter.string(from: Date()))\n\n",
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        ))
        header.append(NSAttributedString(
            string: "Patient: \(patient.fullName)\n",
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        ))
        return header
    }
    
    private func formatMeasurements(_ measurements: Measurements) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\nArea Measurements\n",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
        )
        text.append(NSAttributedString(
            string: """
            Recipient Area: \(String(format: "%.2f", measurements.recipientArea)) cm²
            Donor Area: \(String(format: "%.2f", measurements.donorArea)) cm²
            Scalp Thickness: \(String(format: "%.2f", measurements.scalpThickness)) mm
            
            """,
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        ))
        return text
    }
    
    private func formatGraftCalculations(_ calculation: GraftCalculation) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\nGraft Details\n",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
        )
        text.append(NSAttributedString(
            string: """
            Total Grafts: \(calculation.totalGrafts)
            Target Density: \(String(format: "%.1f", calculation.density)) grafts/cm²
            
            Distribution:
            """,
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        ))
        
        calculation.distribution.forEach { type, count in
            text.append(NSAttributedString(
                string: "\n- \(type.rawValue): \(count) grafts",
                attributes: [.font: UIFont.systemFont(ofSize: 14)]
            ))
        }
        
        return text
    }
    
    private func formatZoneDetails(_ zones: [GraftZone]) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\n\nZone Planning\n",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
        )
        
        zones.forEach { zone in
            text.append(NSAttributedString(
                string: """
                
                Zone: \(zone.name)
                Area: \(String(format: "%.2f", zone.area)) cm²
                Density: \(String(format: "%.1f", zone.density)) grafts/cm²
                Priority: \(zone.priority.rawValue)
                """,
                attributes: [.font: UIFont.systemFont(ofSize: 14)]
            ))
        }
        
        return text
    }
    
    private func formatVisualization() -> NSAttributedString {
        return NSAttributedString(
            string: "\n\n[3D Visualization Placeholder]\n\n",
            attributes: [.font: UIFont.italicSystemFont(ofSize: 14)]
        )
    }
    
    private func formatTerms() -> NSAttributedString {
        return NSAttributedString(
            string: """
            \nTerms and Conditions:
            - This treatment plan is based on current measurements and analysis
            - Final results may vary based on individual healing and growth patterns
            - A consultation is required before proceeding with the treatment
            """,
            attributes: [.font: UIFont.systemFont(ofSize: 12)]
        )
    }
    
    private func render(_ content: NSAttributedString) throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            content.draw(in: CGRect(x: 36, y: 36, width: 540, height: 720))
        }
    }
}

public struct PatientInfo {
    public let fullName: String
    public let dateOfBirth: Date
    public let patientId: String
    
    public init(fullName: String, dateOfBirth: Date, patientId: String) {
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.patientId = patientId
    }
}