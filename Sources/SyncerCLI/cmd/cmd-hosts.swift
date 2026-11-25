import Foundation
import ArgumentParser
import Syncer

struct HostsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hosts",
        abstract: "See hosts"
    )

    func run() async throws {
        let hosts = SSHHosts.list()
        if hosts.isEmpty {
            print("No SSH hosts found.")
        } else {
            hosts.forEach { print($0) }
        }
    }
}
