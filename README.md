# xcdoctor

A command-line tool that helps diagnosing your Xcode project for common defects.

| [Latest release (0.5.1)](https://github.com/jhauberg/xcdoctor/releases/tag/0.5.1) | Download the latest stable release.                 |
| :-------------------------------------------------------------------------------- | :-------------------------------------------------- |
| [Issue tracker](https://github.com/jhauberg/xcdoctor/issues)                      | Contribute your bugs, comments or feature requests. |

<br />

## Install

| Dependency                                                              | Description                                   | Version | License            |
| :---------------------------------------------------------------------- | :-------------------------------------------- | :------ | :----------------- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Describe and manage a command-line interface. | 0.3.0   | Apache License 2.0 |

<br />

**Requires Swift 5+**

First, build the program:

```shell
$ swift build --configuration release
```

Then, copy the executable to `usr/local/bin`. You can either do this manually, or by running:

```shell
$ cd .build/release
$ cp -f xcdoctor /user/local/bin/xcdoctor
```

## Use

If `xcdoctor` was installed as expected, you can now run `xcdoctor`:

```shell
$ xcdoctor --help
```
```console
USAGE: xcdoctor <xcodeproj> [--verbose]

ARGUMENTS:
  <xcodeproj>             A path to an Xcode project file.

                          You can put in a path to a directory to automatically
                          look for a project at that location, or "." to look
                          for a project in the current working directory.

OPTIONS:
  -v, --verbose           Show diagnostic messages.
  -h, --help              Show help information.
  --version               Show the version.
```

At this point, you can now run `xcdoctor` and point it directly to your Xcode project to initiate an [examination](#examination):

```shell
$ xcdoctor ~/path/to/my/Project.xcodeproj
```

*Add the `--verbose` option to see an indication of progress during examination.*

# Examination

The purpose of an examination is to discover and identify defects in an Xcode project.

This process includes resolving and validating file/group references, determining unused resources and more. For a complete list of checks, see [Diagnosis.swift](https://github.com/jhauberg/xcdoctor/blob/master/Sources/XCDoctor/Diagnosis.swift#L14-L49).

**No files are touched during an examination**, and the user must manually take action on any reported defects.

# Diagnosis

If, during an [examination](#examination), a defect is discovered, `xcdoctor` will form a diagnosis for each defect, including advice on how to treat it.

The diagnoses are reported in _reverse order of importance_, such that the last diagnosis is more important than the first. This is important to note, as treating one defect could have a cascading effect on other diagnoses (sometimes even solving them).

<br />

<table>
  <tr>
    <td>
      This is a Free and Open-Source Software project released under the <a href="LICENSE">MIT License</a>.
    </td>
  </tr>
</table>
