import Foundation
import UIKit

public class ThermalMonitor {
    public static let shared = ThermalMonitor()
    
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var batteryObserver: NSObjectProtocol?
    private var onThermalStateChange: ((ThermalState) -> Void)?
    
    public struct ThermalState {
        let temperature: Float
        let batteryLevel: Float
        let thermalStatus: ProcessInfo.ThermalState
        let isCharging: Bool
        
        var requiresIntervention: Bool {
            return thermalStatus == .serious || 
                   thermalStatus == .critical ||
                   batteryLevel < 0.15
        }
        
        var recommendedAction: RecommendedAction {
            if thermalStatus == .critical {
                return .stopScanning
            } else if thermalStatus == .serious {
                return .reducedPerformance
            } else if batteryLevel < 0.15 && !isCharging {
                return .connectCharger
            } else {
                return .none
            }
        }
    }
    
    public enum RecommendedAction {
        case none
        case reducedPerformance
        case connectCharger
        case stopScanning
        
        var message: String {
            switch self {
            case .none:
                return ""
            case .reducedPerformance:
                return "Device temperature high - reducing performance"
            case .connectCharger:
                return "Battery low - connect charger"
            case .stopScanning:
                return "Device too hot - scanning stopped"
            }
        }
    }
    
    private init() {
        setupBatteryMonitoring()
        setupThermalMonitoring()
    }
    
    public func startMonitoring(onStateChange: @escaping (ThermalState) -> Void) {
        self.onThermalStateChange = onStateChange
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) { [weak self] _ in
            self?.checkDeviceState()
        }
        
        checkDeviceState()
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkDeviceState()
        }
    }
    
    private func setupThermalMonitoring() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkDeviceState()
        }
    }
    
    private func checkDeviceState() {
        let device = UIDevice.current
        let thermalState = ProcessInfo.processInfo.thermalState
        
        let state = ThermalState(
            temperature: estimateTemperature(from: thermalState),
            batteryLevel: device.batteryLevel,
            thermalStatus: thermalState,
            isCharging: device.batteryState == .charging || 
                       device.batteryState == .full
        )
        
        onThermalStateChange?(state)
    }
    
    private func estimateTemperature(from state: ProcessInfo.ThermalState) -> Float {
        // Estimate temperature based on thermal state
        switch state {
        case .nominal:
            return 25.0
        case .fair:
            return 30.0
        case .serious:
            return 35.0
        case .critical:
            return 40.0
        @unknown default:
            return 25.0
        }
    }
    
    deinit {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = batteryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopMonitoring()
    }
}