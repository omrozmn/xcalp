import Foundation
import simd
import SharedTypes

public struct GraftPlan {
    public let totalGrafts: Int
    public let regions: [String: Int]
    public let directions: [Direction]
    
    public init(
        totalGrafts: Int,
        regions: [String: Int],
        directions: [Direction]
    ) {
        self.totalGrafts = totalGrafts
        self.regions = regions
        self.directions = directions
    }
}