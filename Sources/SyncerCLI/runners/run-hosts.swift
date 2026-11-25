import Syncer

enum HostsRunner {
    static func run() {
        let hosts = SSHHosts.list()
        if hosts.isEmpty {
            print("No SSH hosts found.")
        } else {
            hosts.forEach { print($0) }
        }
    }
}
