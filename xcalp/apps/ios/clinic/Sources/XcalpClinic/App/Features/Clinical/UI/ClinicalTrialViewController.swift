import UIKit
import Charts
import Combine

class ClinicalTrialViewController: UIViewController {
    private let trialManager = ClinicalTrialManager.shared
    private let errorHandler = XCErrorHandler.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var currentTrial: TrialConfiguration?
    private var trialData: [ProcessedTrialData] = []
    
    // MARK: - UI Components
    private lazy var trialStatusView: TrialStatusView = {
        let view = TrialStatusView()
        return view
    }()
    
    private lazy var progressChart: BarChartView = {
        let chart = BarChartView()
        chart.legend.enabled = true
        chart.rightAxis.enabled = false
        chart.xAxis.labelPosition = .bottom
        return chart
    }()
    
    private lazy var qualityMetricsView: QualityMetricsView = {
        let view = QualityMetricsView()
        return view
    }()
    
    private lazy var participantTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.register(ParticipantCell.self, forCellReuseIdentifier: "ParticipantCell")
        table.delegate = self
        table.dataSource = self
        return table
    }()
    
    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        loadTrialData()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Clinical Trial Management"
        
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        [trialStatusView, progressChart, qualityMetricsView, participantTableView, actionButton].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            trialStatusView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            trialStatusView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            trialStatusView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            trialStatusView.heightAnchor.constraint(equalToConstant: 100),
            
            progressChart.topAnchor.constraint(equalTo: trialStatusView.bottomAnchor, constant: 20),
            progressChart.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            progressChart.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            progressChart.heightAnchor.constraint(equalToConstant: 200),
            
            qualityMetricsView.topAnchor.constraint(equalTo: progressChart.bottomAnchor, constant: 20),
            qualityMetricsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            qualityMetricsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            qualityMetricsView.heightAnchor.constraint(equalToConstant: 150),
            
            participantTableView.topAnchor.constraint(equalTo: qualityMetricsView.bottomAnchor, constant: 20),
            participantTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            participantTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            participantTableView.heightAnchor.constraint(equalToConstant: 300),
            
            actionButton.topAnchor.constraint(equalTo: participantTableView.bottomAnchor, constant: 20),
            actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            actionButton.heightAnchor.constraint(equalToConstant: 50),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        
        updateActionButton()
    }
    
    private func setupBindings() {
        // Observe trial status changes
        NotificationCenter.default.publisher(for: .trialStatusChanged)
            .sink { [weak self] notification in
                guard let self = self,
                      let trialStatus = notification.object as? TrialConfiguration else {
                    return
                }
                self.updateTrialStatus(trialStatus)
            }
            .store(in: &cancellables)
        
        // Observe data quality updates
        NotificationCenter.default.publisher(for: .dataQualityUpdated)
            .sink { [weak self] notification in
                guard let self = self,
                      let qualityData = notification.object as? [String: Float] else {
                    return
                }
                self.updateQualityMetrics(qualityData)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    private func loadTrialData() {
        Task {
            do {
                currentTrial = try await trialManager.getCurrentTrialConfiguration()
                if let trial = currentTrial {
                    trialData = try await trialManager.fetchTrialData(for: trial.trialId)
                    
                    await MainActor.run {
                        updateUI()
                    }
                }
            } catch {
                errorHandler.handle(error, severity: .medium)
                showErrorAlert(error)
            }
        }
    }
    
    // MARK: - UI Updates
    private func updateUI() {
        guard let trial = currentTrial else {
            showNoActiveTrialState()
            return
        }
        
        trialStatusView.configure(with: trial)
        updateProgressChart(with: trialData)
        updateQualityMetrics(with: trialData)
        participantTableView.reloadData()
        updateActionButton()
    }
    
    private func updateTrialStatus(_ trial: TrialConfiguration) {
        currentTrial = trial
        trialStatusView.configure(with: trial)
        updateActionButton()
    }
    
    private func updateProgressChart(with data: [ProcessedTrialData]) {
        let entries = data.reduce(into: [String: Int]()) { result, data in
            let dateKey = dateFormatter.string(from: data.timestamp)
            result[dateKey, default: 0] += 1
        }
        
        let chartEntries = entries.map { BarChartDataEntry(x: Double($0.key.hash), y: Double($0.value)) }
        let dataSet = BarChartDataSet(entries: chartEntries, label: "Daily Scans")
        dataSet.colors = [.systemBlue]
        
        progressChart.data = BarChartData(dataSet: dataSet)
        progressChart.notifyDataSetChanged()
    }
    
    private func updateQualityMetrics(with data: [ProcessedTrialData]) {
        let qualityMetrics = calculateQualityMetrics(from: data)
        qualityMetricsView.update(with: qualityMetrics)
    }
    
    private func updateActionButton() {
        switch currentTrial?.phase {
        case .preparation:
            actionButton.setTitle("Start Trial", for: .normal)
        case .recruitment:
            actionButton.setTitle("Add Participant", for: .normal)
        case .dataCollection:
            actionButton.setTitle("Record Data", for: .normal)
        case .analysis:
            actionButton.setTitle("View Analysis", for: .normal)
        case .validation:
            actionButton.setTitle("Validate Results", for: .normal)
        case .completion:
            actionButton.setTitle("View Report", for: .normal)
        case .none:
            actionButton.setTitle("Create Trial", for: .normal)
        }
    }
    
    private func showNoActiveTrialState() {
        trialStatusView.showNoActiveTrial()
        progressChart.clear()
        qualityMetricsView.showNoData()
        participantTableView.reloadData()
        updateActionButton()
    }
    
    // MARK: - Actions
    @objc private func actionButtonTapped() {
        switch currentTrial?.phase {
        case .preparation:
            startTrial()
        case .recruitment:
            showAddParticipant()
        case .dataCollection:
            showDataCollection()
        case .analysis:
            showAnalysis()
        case .validation:
            validateResults()
        case .completion:
            showReport()
        case .none:
            showCreateTrial()
        }
    }
    
    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Helper Methods
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private func calculateQualityMetrics(from data: [ProcessedTrialData]) -> [String: Float] {
        // Calculate quality metrics from trial data
        return [
            "scan_quality": calculateAverageScanQuality(data),
            "analysis_confidence": calculateAverageConfidence(data),
            "compliance_rate": calculateComplianceRate(data)
        ]
    }
}

// MARK: - UITableViewDataSource
extension ClinicalTrialViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return trialData.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ParticipantCell", for: indexPath) as! ParticipantCell
        let data = trialData[indexPath.row]
        cell.configure(with: data)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ClinicalTrialViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let data = trialData[indexPath.row]
        showParticipantDetails(data)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let trialStatusChanged = Notification.Name("trialStatusChanged")
    static let dataQualityUpdated = Notification.Name("dataQualityUpdated")
}