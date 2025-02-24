import UIKit
import UniformTypeIdentifiers

class ClinicalExportViewController: UIViewController {
    private let exporter = ClinicalDataExporter()
    private let errorHandler = XCErrorHandler.shared
    
    private var selectedFormat: ExportFormat = .pdf
    private var caseId: String
    private var exportConfig = ExportConfiguration(
        format: .pdf,
        includePatientData: true,
        includeScanData: true,
        includeAnalysis: true,
        encryptionRequired: false,
        recipientPublicKey: nil
    )
    
    // MARK: - UI Components
    private lazy var formatSegmentControl: UISegmentedControl = {
        let items = ["PDF", "DICOM", "JSON", "Encrypted"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(formatChanged(_:)), for: .valueChanged)
        return control
    }()
    
    private lazy var dataOptionsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var patientDataSwitch = createOptionSwitch(title: "Include Patient Data")
    private lazy var scanDataSwitch = createOptionSwitch(title: "Include Scan Data")
    private lazy var analysisSwitch = createOptionSwitch(title: "Include Analysis")
    private lazy var encryptionSwitch = createOptionSwitch(title: "Encrypt Export")
    
    private lazy var exportButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Export Data", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Initialization
    init(caseId: String) {
        self.caseId = caseId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Export Clinical Data"
        
        view.addSubview(formatSegmentControl)
        view.addSubview(dataOptionsStackView)
        view.addSubview(exportButton)
        view.addSubview(activityIndicator)
        
        formatSegmentControl.translatesAutoresizingMaskIntoConstraints = false
        dataOptionsStackView.translatesAutoresizingMaskIntoConstraints = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Add options to stack view
        dataOptionsStackView.addArrangedSubview(createOptionView(with: patientDataSwitch, title: "Patient Data"))
        dataOptionsStackView.addArrangedSubview(createOptionView(with: scanDataSwitch, title: "Scan Data"))
        dataOptionsStackView.addArrangedSubview(createOptionView(with: analysisSwitch, title: "Analysis"))
        dataOptionsStackView.addArrangedSubview(createOptionView(with: encryptionSwitch, title: "Encryption"))
        
        NSLayoutConstraint.activate([
            formatSegmentControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            formatSegmentControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            formatSegmentControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            dataOptionsStackView.topAnchor.constraint(equalTo: formatSegmentControl.bottomAnchor, constant: 40),
            dataOptionsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            dataOptionsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            exportButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            exportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            exportButton.heightAnchor.constraint(equalToConstant: 50),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func createOptionSwitch(title: String) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.addTarget(self, action: #selector(optionChanged(_:)), for: .valueChanged)
        return toggle
    }
    
    private func createOptionView(with toggle: UISwitch, title: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = title
        
        container.addSubview(label)
        container.addSubview(toggle)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    // MARK: - Actions
    @objc private func formatChanged(_ sender: UISegmentedControl) {
        selectedFormat = ExportFormat(rawValue: sender.selectedSegmentIndex) ?? .pdf
        updateExportConfiguration()
    }
    
    @objc private func optionChanged(_ sender: UISwitch) {
        updateExportConfiguration()
    }
    
    @objc private func exportButtonTapped() {
        startExport()
    }
    
    private func updateExportConfiguration() {
        exportConfig = ExportConfiguration(
            format: selectedFormat,
            includePatientData: patientDataSwitch.isOn,
            includeScanData: scanDataSwitch.isOn,
            includeAnalysis: analysisSwitch.isOn,
            encryptionRequired: encryptionSwitch.isOn,
            recipientPublicKey: nil // Will be set during export if needed
        )
    }
    
    private func startExport() {
        activityIndicator.startAnimating()
        exportButton.isEnabled = false
        
        if exportConfig.encryptionRequired {
            promptForRecipientKey { [weak self] key in
                guard let self = self else { return }
                var updatedConfig = self.exportConfig
                updatedConfig.recipientPublicKey = key
                self.performExport(with: updatedConfig)
            }
        } else {
            performExport(with: exportConfig)
        }
    }
    
    private func performExport(with config: ExportConfiguration) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let exportURL = try self.exporter.exportClinicalCase(self.caseId, config: config)
                
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.exportButton.isEnabled = true
                    self.presentShareSheet(for: exportURL)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.exportButton.isEnabled = true
                    self.errorHandler.handle(error, severity: .medium)
                    self.showExportError(error)
                }
            }
        }
    }
    
    private func promptForRecipientKey(completion: @escaping (SecKey?) -> Void) {
        // In a real app, this would integrate with a key management system
        // For now, we'll simulate key selection
        completion(nil)
    }
    
    private func presentShareSheet(for url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityVC.popoverPresentationController?.sourceView = exportButton
        }
        
        present(activityVC, animated: true)
    }
    
    private func showExportError(_ error: Error) {
        let alert = UIAlertController(
            title: "Export Failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ExportFormat {
    init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .pdf
        case 1: self = .dicom
        case 2: self = .json
        case 3: self = .encrypted
        default: return nil
        }
    }
}