import UIKit
import RxSwift
import RxCocoa

class PatientDetailViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let profileHeaderView = PatientProfileHeaderView()
    private let scanCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 200, height: 250)
        layout.minimumLineSpacing = 20
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    private let newScanButton = UIButton(type: .system)
    private let historyTableView = UITableView(frame: .zero, style: .plain)
    
    private let viewModel: PatientDetailViewModel
    private let disposeBag = DisposeBag()
    
    init(patient: Patient) {
        self.viewModel = PatientDetailViewModel(patient: patient)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        viewModel.loadScans()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = viewModel.patient.fullName
        
        // Setup navigation items
        let editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: nil, action: nil)
        navigationItem.rightBarButtonItem = editButton
        
        // Add scrollView and contentView
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(view)
        }
        
        // Add subviews
        contentView.addSubview(profileHeaderView)
        contentView.addSubview(scanCollectionView)
        contentView.addSubview(newScanButton)
        contentView.addSubview(historyTableView)
        
        // Configure profile header
        profileHeaderView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(200)
        }
        
        // Configure scan section
        let scanSectionHeader = createSectionHeader(title: "3D Scans")
        contentView.addSubview(scanSectionHeader)
        
        scanSectionHeader.snp.makeConstraints { make in
            make.top.equalTo(profileHeaderView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        
        scanCollectionView.snp.makeConstraints { make in
            make.top.equalTo(scanSectionHeader.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(250)
        }
        
        scanCollectionView.register(ScanPreviewCell.self, forCellWithReuseIdentifier: "ScanPreviewCell")
        scanCollectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        scanCollectionView.showsHorizontalScrollIndicator = false
        
        // Configure new scan button
        newScanButton.setTitle("New Scan", for: .normal)
        newScanButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        newScanButton.backgroundColor = .systemBlue
        newScanButton.tintColor = .white
        newScanButton.layer.cornerRadius = 8
        newScanButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        
        newScanButton.snp.makeConstraints { make in
            make.top.equalTo(scanCollectionView.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }
        
        // Configure history section
        let historyHeader = createSectionHeader(title: "Medical History")
        contentView.addSubview(historyHeader)
        
        historyHeader.snp.makeConstraints { make in
            make.top.equalTo(newScanButton.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        
        historyTableView.snp.makeConstraints { make in
            make.top.equalTo(historyHeader.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(300)
            make.bottom.equalToSuperview().offset(-20)
        }
        
        historyTableView.register(MedicalHistoryCell.self, forCellReuseIdentifier: "MedicalHistoryCell")
        historyTableView.isScrollEnabled = false
    }
    
    private func setupBindings() {
        // Profile header
        profileHeaderView.configure(with: viewModel.patient)
        
        // Scans collection
        viewModel.scans
            .bind(to: scanCollectionView.rx.items(cellIdentifier: "ScanPreviewCell", cellType: ScanPreviewCell.self)) { _, scan, cell in
                cell.configure(with: scan)
            }
            .disposed(by: disposeBag)
        
        scanCollectionView.rx.modelSelected((SCNGeometry, ScanMetadata).self)
            .subscribe(onNext: { [weak self] scan in
                self?.showScanDetail(scan)
            })
            .disposed(by: disposeBag)
        
        // New scan button
        newScanButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.startNewScan()
            })
            .disposed(by: disposeBag)
        
        // Medical history
        viewModel.medicalHistory
            .bind(to: historyTableView.rx.items(cellIdentifier: "MedicalHistoryCell", cellType: MedicalHistoryCell.self)) { _, history, cell in
                cell.configure(with: history)
            }
            .disposed(by: disposeBag)
        
        // Edit button
        navigationItem.rightBarButtonItem?.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.showEditPatient()
            })
            .disposed(by: disposeBag)
    }
    
    private func createSectionHeader(title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 20, weight: .bold)
        return label
    }
    
    private func showScanDetail(_ scan: (SCNGeometry, ScanMetadata)) {
        let detailVC = ScanDetailViewController(mesh: scan.0, metadata: scan.1)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func startNewScan() {
        let scanVC = ScanViewController()
        scanVC.patientId = viewModel.patient.id
        navigationController?.pushViewController(scanVC, animated: true)
    }
    
    private func showEditPatient() {
        let editVC = EditPatientViewController(patient: viewModel.patient)
        let nav = UINavigationController(rootViewController: editVC)
        present(nav, animated: true)
    }
}