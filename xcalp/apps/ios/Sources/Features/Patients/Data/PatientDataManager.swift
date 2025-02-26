import Foundation
import RxSwift
import CoreData

class PatientDataManager {
    static let shared = PatientDataManager()
    private let fileManager = FileManager.default
    private let disposeBag = DisposeBag()
    
    private var patientsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Patients", isDirectory: true)
    }
    
    init() {
        try? fileManager.createDirectory(at: patientsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - CRUD Operations
    
    func createPatient(_ patient: Patient) -> Single<Void> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(PatientError.internalError))
                return Disposables.create()
            }
            
            do {
                let patientURL = self.patientsDirectory.appendingPathComponent("\(patient.id).json")
                let data = try JSONEncoder().encode(patient)
                try data.write(to: patientURL)
                single(.success(()))
            } catch {
                single(.failure(PatientError.saveFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func getPatient(id: String) -> Single<Patient> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(PatientError.internalError))
                return Disposables.create()
            }
            
            do {
                let patientURL = self.patientsDirectory.appendingPathComponent("\(id).json")
                let data = try Data(contentsOf: patientURL)
                let patient = try JSONDecoder().decode(Patient.self, from: data)
                single(.success(patient))
            } catch {
                single(.failure(PatientError.loadFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func updatePatient(_ patient: Patient) -> Single<Void> {
        return createPatient(patient)
    }
    
    func deletePatient(id: String) -> Single<Void> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(PatientError.internalError))
                return Disposables.create()
            }
            
            do {
                let patientURL = self.patientsDirectory.appendingPathComponent("\(id).json")
                try self.fileManager.removeItem(at: patientURL)
                
                // Also delete associated scans
                ScanDataManager.shared.listScansForPatient(id: id)
                    .flatMap { scans in
                        Observable.from(scans)
                            .flatMap { scan in
                                ScanDataManager.shared.deleteScan(id: scan.id)
                                    .asObservable()
                            }
                            .toArray()
                            .asSingle()
                    }
                    .subscribe(
                        onSuccess: { _ in
                            single(.success(()))
                        },
                        onFailure: { error in
                            single(.failure(PatientError.deleteFailed(error)))
                        }
                    )
                    .disposed(by: self.disposeBag)
                
            } catch {
                single(.failure(PatientError.deleteFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func getAllPatients() -> Single<[Patient]> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(PatientError.internalError))
                return Disposables.create()
            }
            
            do {
                let files = try self.fileManager.contentsOfDirectory(
                    at: self.patientsDirectory,
                    includingPropertiesForKeys: nil
                )
                
                let patients = try files
                    .filter { $0.pathExtension == "json" }
                    .map { url -> Patient in
                        let data = try Data(contentsOf: url)
                        return try JSONDecoder().decode(Patient.self, from: data)
                    }
                
                single(.success(patients))
            } catch {
                single(.failure(PatientError.listFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func searchPatients(query: String) -> Single<[Patient]> {
        return getAllPatients()
            .map { patients in
                let lowercaseQuery = query.lowercased()
                return patients.filter {
                    $0.fullName.lowercased().contains(lowercaseQuery) ||
                    $0.email?.lowercased().contains(lowercaseQuery) == true ||
                    $0.phone?.contains(query) == true
                }
            }
    }
    
    // MARK: - Scan Management
    
    func addScanToPatient(patientId: String, scanId: String) -> Single<Void> {
        return getPatient(id: patientId)
            .map { patient -> Patient in
                var updatedPatient = patient
                updatedPatient.scans.append(scanId)
                return updatedPatient
            }
            .flatMap { updatedPatient in
                self.updatePatient(updatedPatient)
            }
    }
    
    func getPatientScans(patientId: String) -> Single<[(SCNGeometry, ScanMetadata)]> {
        return getPatient(id: patientId)
            .flatMap { patient -> Single<[(SCNGeometry, ScanMetadata)]> in
                let scanObservables = patient.scans.map { scanId in
                    ScanDataManager.shared.loadScan(id: scanId).asObservable()
                }
                
                return Observable.zip(scanObservables)
                    .asSingle()
            }
    }
}

// MARK: - Error Types

enum PatientError: Error {
    case internalError
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case listFailed(Error)
    case invalidData
}