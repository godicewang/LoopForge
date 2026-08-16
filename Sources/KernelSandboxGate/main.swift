import Darwin

@_silgen_name("_NSGetEnviron")
private func kernelSandboxGateEnvironmentPointer()
    -> UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>

private let handshakeDescriptor: Int32 = 198
private func fail(_ code: Int32, _ failure: Int32) -> Never {
    var value = failure
    _ = withUnsafeBytes(of: &value) {
        Darwin.write(handshakeDescriptor, $0.baseAddress, $0.count)
    }
    let message = "kernel-sandbox-gate:\(code):\(failure)\n"
    _ = message.withCString { Darwin.write(STDERR_FILENO, $0, strlen($0)) }
    Darwin.exit(code)
}

private let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2,
      Int32(arguments[0]) == handshakeDescriptor,
      !arguments.contains(where: { $0.contains("\0") }) else {
    fail(64, EINVAL)
}

var targetStart = 1
if arguments.count >= 5,
   arguments[1] == "--kernel-resource-limits-v1",
   let maximumOutputFileBytes = rlim_t(arguments[2]),
   let maximumProcessCount = rlim_t(arguments[3]),
   maximumProcessCount == 1 {
    _ = Darwin.signal(SIGXFSZ, SIG_DFL)
    var fileLimit = rlimit(
        rlim_cur: maximumOutputFileBytes,
        rlim_max: maximumOutputFileBytes
    )
    guard setrlimit(RLIMIT_FSIZE, &fileLimit) == 0 else {
        fail(68, errno)
    }
    var processLimit = rlimit(
        rlim_cur: maximumProcessCount,
        rlim_max: maximumProcessCount
    )
    guard setrlimit(RLIMIT_NPROC, &processLimit) == 0 else {
        fail(69, errno)
    }
    targetStart = 4
}
guard arguments.indices.contains(targetStart),
      arguments[targetStart].hasPrefix("/") else {
    fail(64, EINVAL)
}

// A successful exec closes the descriptor and gives the parent EOF. If exec
// fails, the gate writes the exact errno before exiting. The gate changes no
// environment variables and executes no shell.
guard fcntl(handshakeDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
    fail(65, errno)
}
guard raise(SIGSTOP) == 0 else {
    fail(66, errno)
}

let executable = arguments[targetStart]
let targetArguments = Array(arguments.dropFirst(targetStart))
let allocated = targetArguments.map { strdup($0) }
guard allocated.allSatisfy({ $0 != nil }) else {
    fail(67, ENOMEM)
}
defer { allocated.forEach { Darwin.free($0) } }
var vector = allocated + [nil]
let result: Int32 = vector.withUnsafeMutableBufferPointer { buffer in
    executable.withCString { path in
        Darwin.execve(
            path,
            buffer.baseAddress!,
            kernelSandboxGateEnvironmentPointer().pointee
        )
    }
}
fail(126, result == -1 ? errno : EINVAL)
