import UIKit
import RxSwift
import RxCocoa

class PatientsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)
    private let disposeBag = DisposeBag()
    
    private let viewModel = PatientsViewModel()
    private var patients: [Patient] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
    }
    
    private func setupUI() {
        title = "Patients"
        navigationItem.rightBarButtonItem = addButton
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search patients"
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        tableView.register(PatientCell.self, forCellReuseIdentifier: "PatientCell")
        tableView.rowHeight = 80
    }
    
    private func setupBindings() {
        // Search bar binding
        searchController.searchBar.rx.text
            .orEmpty
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .distinctUntilChanged()
            .bind(to: viewModel.searchQuery)
            .disposed(by: disposeBag)
        
        // Table view data binding
        viewModel.patients
            .observe(on: MainScheduler.instance)
            .do(onNext: { [weak self] patients in
                self?.patients = patients
            })
            .bind(to: tableView.rx.items(cellIdentifier: "PatientCell", cellType: PatientCell.self)) { _, patient, cell in
                cell.configure(with: patient)
            }
            .disposed(by: disposeBag)
        
        // Selection binding
        tableView.rx.modelSelected(Patient.self)
            .subscribe(onNext: { [weak self] patient in
                self?.showPatientDetail(patient)
            })
            .disposed(by: disposeBag)
        
        // Add button binding
        addButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.showAddPatient()
            })
            .disposed(by: disposeBag)
        
        // Initial load
        viewModel.loadPatients()
    }
    
    private func showPatientDetail(_ patient: Patient) {
        let detailVC = PatientDetailViewController(patient: patient)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func showAddPatient() {
        let addVC = AddPatientViewController()
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }
}