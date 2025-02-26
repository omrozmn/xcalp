import UIKit
import SnapKit

class PatientCell: UITableViewCell {
    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let detailsLabel = UILabel()
    private let nextAppointmentLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Profile Image
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 25
        profileImageView.backgroundColor = .systemGray5
        
        // Labels
        nameLabel.font = .systemFont(ofSize: 17, weight: .medium)
        detailsLabel.font = .systemFont(ofSize: 14)
        detailsLabel.textColor = .secondaryLabel
        nextAppointmentLabel.font = .systemFont(ofSize: 12)
        nextAppointmentLabel.textColor = .secondaryLabel
        
        // Layout
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailsLabel)
        contentView.addSubview(nextAppointmentLabel)
        
        profileImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(50)
        }
        
        nameLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalTo(profileImageView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-16)
        }
        
        detailsLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(4)
            make.leading.equalTo(nameLabel)
            make.trailing.equalTo(nameLabel)
        }
        
        nextAppointmentLabel.snp.makeConstraints { make in
            make.top.equalTo(detailsLabel.snp.bottom).offset(4)
            make.leading.equalTo(nameLabel)
            make.trailing.equalTo(nameLabel)
            make.bottom.lessThanOrEqualToSuperview().offset(-12)
        }
    }
    
    func configure(with patient: Patient) {
        nameLabel.text = patient.fullName
        
        let age = Calendar.current.dateComponents([.year], from: patient.dateOfBirth, to: Date()).year ?? 0
        detailsLabel.text = "\(age) years • \(patient.gender.rawValue.capitalized)"
        
        if let nextAppointment = patient.nextAppointmentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            nextAppointmentLabel.text = "Next: \(formatter.string(from: nextAppointment))"
            nextAppointmentLabel.isHidden = false
        } else {
            nextAppointmentLabel.isHidden = true
        }
        
        if let photoUrl = patient.profilePhotoUrl {
            // TODO: Implement image loading with proper caching
            // For now, just show a placeholder
            profileImageView.image = UIImage(systemName: "person.circle.fill")
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
        }
    }
}