import UIKit

class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewControllers()
        setupAppearance()
    }
    
    private func setupViewControllers() {
        let dashboardVC = UINavigationController(rootViewController: DashboardViewController())
        dashboardVC.tabBarItem = UITabBarItem(title: "Dashboard", image: UIImage(systemName: "house"), tag: 0)
        
        let patientsVC = UINavigationController(rootViewController: PatientsViewController())
        patientsVC.tabBarItem = UITabBarItem(title: "Patients", image: UIImage(systemName: "person.2"), tag: 1)
        
        let scanVC = UINavigationController(rootViewController: ScanViewController())
        scanVC.tabBarItem = UITabBarItem(title: "Scan", image: UIImage(systemName: "camera"), tag: 2)
        
        let treatmentVC = UINavigationController(rootViewController: TreatmentViewController())
        treatmentVC.tabBarItem = UITabBarItem(title: "Treatment", image: UIImage(systemName: "cross"), tag: 3)
        
        let moreVC = UINavigationController(rootViewController: MoreViewController())
        moreVC.tabBarItem = UITabBarItem(title: "More", image: UIImage(systemName: "ellipsis"), tag: 4)
        
        viewControllers = [dashboardVC, patientsVC, scanVC, treatmentVC, moreVC]
    }
    
    private func setupAppearance() {
        tabBar.tintColor = .systemBlue
        tabBar.backgroundColor = .systemBackground
    }
}