# Contribution Guide

We appreciate your interest in contributing to this project! This document outlines the process for submitting code, documentation, or other types of contributions. Please read and follow these guidelines to ensure a smooth collaboration with the project maintainers.

Before participating in the project, please read our [Code of Conduct](https://github.com/bilbilak/claudebar?tab=coc-ov-file#readme). By engaging with this repository and its respective community, you agree to abide by its terms.

## 💻 Setting up your development environment

1. [Fork](https://github.com/bilbilak/claudebar/fork) the project on _GitHub_ to your own account.
    - If you are new to forking repositories, you can find a detailed guide on forking [here](https://docs.github.com/en/get-started/quickstart/fork-a-repo).
2. Clone your fork to your local development environment:
    ```
    git clone git@github.com:bilbilak/claudebar.git
    cd claudebar
    ```
3. Pick the platform you plan to work on and install its native toolchain. **_ClaudeBar_** is a monorepo of per-desktop-environment front-ends sharing a small _Rust_ helper binary; each front-end has its own `README.md` under `apps/` listing its build-time dependencies:
    - **macOS** — _Swift 5.9+_, _Xcode 15+_
    - **Windows** — _.NET 8 SDK_
    - **Linux / GNOME** — _Node.js 20+_ (_TypeScript_, _esbuild_)
    - **Linux / KDE** — _kf6_, _kpackagetool6_
    - **Linux / Cinnamon** — _cjs_, _libsecret_, _libsoup_
    - **Linux / XFCE** — _libxfce4panel_, _meson_
    - **Linux / MATE** — _python3_, _PyGObject_, _mate-panel_
    - **Linux / Budgie** — _Vala_, _libpeas_, _budgie-desktop_
    - **Linux / LXQt** — _Qt5_, _liblxqt_
    - **Linux helper** — _Rust_ (stable)

**NOTE:** If you'd like to contribute to our documentation, please use [MyRepos](https://myrepos.branchable.com) tool to clone the project's _Wiki_. You can initiate the clone by running `mr checkout` as configured in the `.mrconfig` file. This will create the sub-repository under the `docs/wiki/` directory, separate from the main repository. To interact with this sub-repository, it's important to familiarize yourself with other `mr` commands.

## 📐 Coding conventions and best practices

When contributing to this project, please adhere to the following guidelines:

1. **Coding Conventions:** Follow each platform's established conventions. Before submitting your code, run it through the formatter and linter of the language you are working in:
    - **Swift** — [swift-format](https://github.com/apple/swift-format)
    - **C#** — `dotnet format` and the _Roslyn_ analyzers shipped with _.NET_
    - **TypeScript / JavaScript** — [Prettier](https://prettier.io) and [ESLint](https://eslint.org)
    - **Rust** — [Rustfmt](https://github.com/rust-lang/rustfmt) and [Clippy](https://github.com/rust-lang/rust-clippy)
    - **Python** — [Black](https://black.readthedocs.io) and [Ruff](https://docs.astral.sh/ruff/)
    - **C / C++** — [clang-format](https://clang.llvm.org/docs/ClangFormat.html) and [clang-tidy](https://clang.llvm.org/extra/clang-tidy/)
    - **Vala** — project-standard 4-space indentation; compile with `-Wall`
    - **QML** — [qmlformat](https://doc.qt.io/qt-6/qtquick-tool-qmlformat.html)

    Address any issues or warnings that these tools report before submitting your contribution.
2. **Code Refactoring:** Consider using refactoring techniques to improve the structure of existing code without changing its behavior. Familiarize yourself with various design patterns that can make your code more efficient, scalable, and maintainable. You can find comprehensive guides and examples at [Refactoring Guru](https://refactoring.guru/).
3. **Cross-Platform Compatibility:** **_ClaudeBar_** targets every major desktop — _macOS_, _Windows_, and seven _Linux_ desktop environments. When changes might affect multiple platforms, coordinate the equivalent update across each affected front-end so their behavior stays in lockstep. Keep _OAuth_, settings storage, and rendering logic feature-matched across implementations.
4. **Performance Optimization:** The indicator runs continuously in the user's panel — write efficient and performant code that does not consume unnecessary CPU, memory, or battery. Poll the _Anthropic_ API no more frequently than the user's configured interval; cache results; avoid redrawing the icon on every tick unless the pixels actually changed.
5. **Testing:** For each functionality you add or change, make sure to create corresponding tests where the platform's toolchain supports them. Run the full test matrix for the platform you touched before submitting your changes to ensure they pass.

## 📤 Submitting your contribution

1. Create a new branch for your contribution:
    ```
    git checkout -b feature/your-feature
    ```
2. Make your changes and commit them with a descriptive message:
    ```
    git add .
    git commit -m "Add a brief description of your changes"
    ```
    - Writing clear and concise commit messages is important. For tips on how to write good commit messages, you can refer to [this guide](https://chris.beams.io/posts/git-commit/) tailored for projects following the _Gitflow_ approach.
    - All commits to the repository must be _GPG_-signed — run `git commit -S` (or configure `commit.gpgsign=true` in your local _Git_ config).
3. Push your changes to your fork on _GitHub_:
    ```
    git push origin feature/your-feature
    ```
4. Create a pull request on the project's _GitHub_ repository, comparing the project's `main` branch with your feature branch.
5. Fill out the pull request template with a description of your changes, and reference any relevant issues or discussions.

## 🧐 Review process

After submitting your pull request, the project maintainers will review your contribution. They may request changes or provide feedback before merging your changes into the development branch. Please be patient and address any comments or concerns raised by the maintainers.

<br>

💖 Thank you for your contribution! Your collaboration helps improve the project for everyone.
