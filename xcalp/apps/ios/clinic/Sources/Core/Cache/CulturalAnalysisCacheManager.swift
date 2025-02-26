import Foundation

actor CulturalAnalysisCacheManager {
    static let shared = CulturalAnalysisCacheManager()
    private let performanceMonitor = PerformanceMonitor.shared
    
    private var cache = NSCache<NSString, CachedAnalysis>()
    private var metadataCache = [String: AnalysisMetadata]()
    
    private init() {
        setupCache()
    }
    
    private func setupCache() {
        cache.countLimit = 100 // Maximum number of analyses to cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    func cacheAnalysis(_ analysis: CulturalAnalysisResult, for scanId: String, metadata: AnalysisMetadata) {
        performanceMonitor.startMeasuring("cache_analysis")
        
        let cached = CachedAnalysis(
            result: analysis,
            timestamp: Date(),
            metadata: metadata
        )
        
        cache.setObject(cached, forKey: scanId as NSString)
        metadataCache[scanId] = metadata
        
        performanceMonitor.stopMeasuring("cache_analysis")
    }
    
    func getCachedAnalysis(for scanId: String) -> (CulturalAnalysisResult, AnalysisMetadata)? {
        performanceMonitor.startMeasuring("cache_lookup")
        defer { performanceMonitor.stopMeasuring("cache_lookup") }
        
        guard let cached = cache.object(forKey: scanId as NSString),
              cached.isValid else {
            return nil
        }
        
        return (cached.result, cached.metadata)
    }
    
    func invalidateCache(for scanId: String) {
        cache.removeObject(forKey: scanId as NSString)
        metadataCache.removeValue(forKey: scanId)
    }
    
    func invalidateAllCaches() {
        cache.removeAllObjects()
        metadataCache.removeAll()
    }
    
    func getAnalysisMetadata(for scanId: String) -> AnalysisMetadata? {
        return metadataCache[scanId]
    }
    
    func optimizeCacheForRegion(_ region: Region) {
        // Preload common cultural patterns for the region
        Task {
            do {
                let commonPatterns = try await loadCommonPatternsForRegion(region)
                for pattern in commonPatterns {
                    let metadata = AnalysisMetadata(
                        region: region,
                        patternType: pattern.type,
                        timestamp: Date()
                    )
                    cacheAnalysis(pattern.analysis, for: pattern.id, metadata: metadata)
                }
            } catch {
                Logger.shared.error("Failed to preload patterns for region \(region): \(error.localizedDescription)")
            }
        }
    }
    
    private func loadCommonPatternsForRegion(_ region: Region) async throws -> [RegionalPattern] {
        // This would load pre-analyzed common patterns for the region
        // Implementation would depend on your data source
        return []
    }
}

// MARK: - Supporting Types

final class CachedAnalysis {
    let result: CulturalAnalysisResult
    let timestamp: Date
    let metadata: AnalysisMetadata
    
    init(result: CulturalAnalysisResult, timestamp: Date, metadata: AnalysisMetadata) {
        self.result = result
        self.timestamp = timestamp
        self.metadata = metadata
    }
    
    var isValid: Bool {
        // Cache entries are valid for 1 hour
        return Date().timeIntervalSince(timestamp) < 3600
    }
}

struct AnalysisMetadata: Codable {
    let region: Region
    let patternType: String
    let timestamp: Date
    let parameters: [String: String]?
    
    init(region: Region, patternType: String, timestamp: Date, parameters: [String: String]? = nil) {
        self.region = region
        self.patternType = patternType
        self.timestamp = timestamp
        self.parameters = parameters
    }
}

struct RegionalPattern {
    let id: String
    let type: String
    let analysis: CulturalAnalysisResult
}