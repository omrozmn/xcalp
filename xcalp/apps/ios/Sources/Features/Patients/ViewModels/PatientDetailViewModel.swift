import Foundation
import RxSwift
import RxRelay
import SceneKit

class PatientDetailViewModel {
    // Input
    let patient: Patient
    
    // Output
    let scans = BehaviorRelay<[(SCNGeometry, ScanMetadata)]>(value: [])
    let medicalHistory = BehaviorRelay<[MedicalHistoryItem]>(value: [])
    let isLoading = BehaviorRelay<Bool>(value: false)
    let error = PublishRelay<Error>()
    
    private let disposeBag = DisposeBag()
    
    init(patient: Patient) {
        self.patient = patient
        self.medicalHistory.accept(patient.medicalHistory)
    }
    
    func loadScans() {
        isLoading.accept(true)
        
        PatientDataManager.shared.getPatientScans(patientId: patient.id)
            .subscribe(
                onSuccess: { [weak self] scans in
                    self?.scans.accept(scans)
                    self?.isLoading.accept(false)
                },
                onFailure: { [weak self] error in
                    self?.error.accept(error)
                    self?.isLoading.accept(false)
                }
            )
            .disposed(by: disposeBag)
    }
    
    func refreshPatientData() {
        PatientDataManager.shared.getPatient(id: patient.id)
            .subscribe(
                onSuccess: { [weak self] updatedPatient in
                    self?.medicalHistory.accept(updatedPatient.medicalHistory)
                    self?.loadScans()
                },
                onFailure: { [weak self] error in
                    self?.error.accept(error)
                }
            )
            .disposed(by: disposeBag)
    }
    
    func addNewScan(_ scanId: String) {
        PatientDataManager.shared.addScanToPatient(patientId: patient.id, scanId: scanId)
            .subscribe(
                onSuccess: { [weak self] in
                    self?.loadScans()
                },
                onFailure: { [weak self] error in
                    self?.error.accept(error)
                }
            )
            .disposed(by: disposeBag)
    }
}