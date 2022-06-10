//
//  DiagnosticOutputStream.swift
//  xcdoctor
//
//  Created by Jacob Hauberg Hansen on 26/06/2020.
//  Copyright © 2020 Jacob Hauberg Hansen. All rights reserved.
//

import Foundation

enum Diagnostic {
    case important
    case information
    case result
    case note

    var stream: FileHandle {
        switch self {
        case .information:
            return .standardError
        case .important:
            return .standardOutput
        case .result:
            return .standardOutput
        case .note:
            return .standardOutput
        }
    }

    /**
      Determine whether the output stream supports escape codes for applying colors.

      Output piped to a file that is not any of the standard file descriptors typically do not respond as a TTY.
     */
    var supportsColor: Bool {
        let tty = isatty(stream.fileDescriptor)

        guard Bool(truncating: tty as NSNumber) else {
            // terminal must respond as a TTY
            return false
        }

        return true
    }
}

final class DiagnosticOutputStream: TextOutputStream {
    /**
     Determine whether the terminal supports escape codes for applying colors.
     */
    var supportsColor: Bool {
        guard let term = getenv("TERM") else {
            // terminal must have declared $TERM
            return false
        }

        let name = String(cString: term)

        guard !name.isEmpty, name.lowercased() != "dumb" else {
            // $TERM must be anything but empty or "dumb", literally
            return false
        }

        guard kind.supportsColor else {
            return false
        }

        return true
    }

    var kind: Diagnostic = .information

    func write(_ string: String) {
        kind.stream.write(Data(string.utf8))
    }
}
