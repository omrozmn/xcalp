import Foundation
import RxSwift
import RxRelay

class PatientsViewModel {
    // Output
    let patients = BehaviorRelay<[Patient]>(value: [])
    let isLoading = BehaviorRelay<Bool>(value: false)
    let error = PublishRelay<Error>()
    
    // Input
    let searchQuery = BehaviorRelay<String>(value: "")
    
    private let disposeBag = DisposeBag()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        searchQuery
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .distinctUntilChanged()
            .subscribe(onNext: { [weak self] query in
                self?.searchPatients(query: query)
            })
            .disposed(by: disposeBag)
    }
    
    func loadPatients() {
        isLoading.accept(true)
        
        PatientDataManager.shared.getAllPatients()
            .subscribe(
                onSuccess: { [weak self] patients in
                    self?.patients.accept(patients)
                    self?.isLoading.accept(false)
                },
                onFailure: { [weak self] error in
                    self?.error.accept(error)
                    self?.isLoading.accept(false)
                }
            )
            .disposed(by: disposeBag)
    }
    
    private func searchPatients(query: String) {
        guard !query.isEmpty else {
            loadPatients()
            return
        }
        
        isLoading.accept(true)
        
        PatientDataManager.shared.searchPatients(query: query)
            .subscribe(
                onSuccess: { [weak self] patients in
                    self?.patients.accept(patients)
                    self?.isLoading.accept(false)
                },
                onFailure: { [weak self] error in
                    self?.error.accept(error)
                    self?.isLoading.accept(false)
                }
            )
            .disposed(by: disposeBag)
    }
}