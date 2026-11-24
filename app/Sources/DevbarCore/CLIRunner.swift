import Foundation
import Darwin

/// Esegue la CLI `devbar`. Finto nei test.
public protocol CLIRunning: Sendable {
    func run(_ args: [String], timeout: TimeInterval) async -> (rc: Int32, stdout: Data, stderr: String)
}

/// Runner reale. Il figlio parte in un gruppo di processi suo: al timeout si manda
/// SIGTERM a tutto il gruppo (anche `npm`, `brew`, …), SIGKILL dopo 2 s, e si torna rc 2.
public struct CLIRunner: CLIRunning {
    public let environment: [String: String]
    public let home: String
    private let isExecutable: @Sendable (String) -> Bool

    /// Attesa tra SIGTERM e SIGKILL.
    static let killGrace: TimeInterval = 2
    /// Dopo l'uscita (o l'uccisione), quanto aspettare l'EOF delle pipe: un nipote
    /// staccato (es. demone avviato da `colima start`) può tenerle aperte.
    static let drainGrace: TimeInterval = 2

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory(),
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.environment = environment
        self.home = home
        self.isExecutable = isExecutable
    }

    /// `DEVBAR_BIN`, poi il motore nel bundle (`<Resources>/engine/bin/devbar`), poi
    /// `~/.local/bin/devbar`, poi `/opt/homebrew/bin/devbar`.
    public static func locate(environment: [String: String], home: String,
                              resourceDirectory: String? = Bundle.main.resourcePath,
                              isExecutable: (String) -> Bool) -> String? {
        var candidates: [String] = []
        if let b = environment["DEVBAR_BIN"], !b.isEmpty { candidates.append(b) }
        if let r = resourceDirectory, !r.isEmpty {
            candidates.append((r as NSString).appendingPathComponent("engine/bin/devbar"))
        }
        candidates.append((home as NSString).appendingPathComponent(".local/bin/devbar"))
        candidates.append("/opt/homebrew/bin/devbar")
        return candidates.first(where: isExecutable)
    }

    /// Un LaunchAgent riceve un PATH minimo: si antepongono i bin di Homebrew e
    /// `~/.local/bin` (claude-usage, rtk-run, devbar stesso).
    public static func childPath(inherited: String?, home: String) -> String {
        let base = (inherited?.isEmpty == false) ? inherited! : "/usr/bin:/bin:/usr/sbin:/sbin"
        let local = (home as NSString).appendingPathComponent(".local/bin")
        return "/opt/homebrew/bin:/usr/local/bin:\(local):" + base
    }

    public func run(_ args: [String], timeout: TimeInterval) async -> (rc: Int32, stdout: Data, stderr: String) {
        guard let bin = Self.locate(environment: environment, home: home, isExecutable: isExecutable) else {
            return (2, Data(), "devbar non trovato (DEVBAR_BIN, motore nel bundle, ~/.local/bin, /opt/homebrew/bin)")
        }
        var env = environment
        env["PATH"] = Self.childPath(inherited: environment["PATH"], home: home)
        let envList = env.map { "\($0.key)=\($0.value)" }
        let argv = [bin] + args
        // Tutto il lavoro bloccante (waitpid, read) gira fuori dal main actor.
        return await withCheckedContinuation { cont in
            Thread.detachNewThread {
                cont.resume(returning: Self.spawnAndWait(bin: bin, argv: argv, env: envList, timeout: timeout))
            }
        }
    }

    // MARK: - Implementazione bloccante

    /// Buffer condiviso tra il thread lettore e quello che attende.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) { lock.withLock { data.append(d) } }
        var value: Data { lock.withLock { data } }
    }

    private static func reader(_ fd: Int32, into sink: Sink, done: DispatchSemaphore) {
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if n > 0 { sink.append(Data(buf[0..<n])) }
                else if n < 0 && errno == EINTR { continue }
                else { break }
            }
            close(fd)
            done.signal()
        }
    }

    static func spawnAndWait(bin: String, argv: [String], env: [String], timeout: TimeInterval)
        -> (rc: Int32, stdout: Data, stderr: String) {
        var outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { return (2, Data(), "pipe fallita") }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            return (2, Data(), "pipe fallita")
        }

        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fa, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&fa, errPipe[1], 2)
        for fd in [outPipe[0], outPipe[1], errPipe[0], errPipe[1]] {
            posix_spawn_file_actions_addclose(&fa, fd)
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)

        let cArgv = argv.map { strdup($0) } + [nil]
        let cEnv = env.map { strdup($0) } + [nil]
        defer { cArgv.forEach { free($0) }; cEnv.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnErr = posix_spawn(&pid, bin, &fa, &attr, cArgv, cEnv)
        close(outPipe[1]); close(errPipe[1])
        if spawnErr != 0 {
            close(outPipe[0]); close(errPipe[0])
            return (2, Data(), "avvio di devbar fallito: \(String(cString: strerror(spawnErr)))")
        }
        let child = pid

        // Le pipe si leggono in parallelo fino a EOF: niente stallo con output grandi.
        let out = Sink(), err = Sink()
        let drained = DispatchSemaphore(value: 0)
        reader(outPipe[0], into: out, done: drained)
        reader(errPipe[0], into: err, done: drained)

        let exited = DispatchSemaphore(value: 0)
        let statusBox = Sink()
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(child, &status, 0) < 0 && errno == EINTR {}
            withUnsafeBytes(of: status) { statusBox.append(Data($0)) }
            exited.signal()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            killpg(child, SIGTERM)
            if exited.wait(timeout: .now() + killGrace) == .timedOut {
                killpg(child, SIGKILL)
                exited.wait()
            }
        }
        // EOF di entrambe le pipe, ma senza aspettare per sempre.
        let deadline = DispatchTime.now() + drainGrace
        _ = drained.wait(timeout: deadline)
        _ = drained.wait(timeout: deadline)

        let stderrText = String(decoding: err.value, as: UTF8.self)
        if timedOut {
            let note = "devbar ucciso dopo il timeout di \(Int(timeout.rounded())) s"
            return (2, out.value, stderrText.isEmpty ? note : stderrText + "\n" + note)
        }
        let status = statusBox.value.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        // WIFEXITED / WEXITSTATUS a mano: le macro non arrivano in Swift.
        let rc: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 2
        return (rc, out.value, stderrText)
    }
}
