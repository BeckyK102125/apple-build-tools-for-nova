# Apple Build Tools for Nova

Build, run, and test Apple apps from Nova on a Mac, with every step designed to work with VoiceOver and the keyboard.

- **Build and Run** on a connected iPhone, on this Mac, or in an iPhone Simulator, as one command.
- **App Console**: everything your app prints while it runs, with errors and warnings first.
- **App Reports**: your app's crash and resource reports, in plain words.
- **Build reports** that start with the errors, and a result message that names the first one.
- **Signing Status** and an Xcode-style **Project Navigator** in Nova's sidebars.
- Every list opens in a small native chooser window that VoiceOver reads, instead of Nova's command palette.

It needs macOS 14 or later, Xcode, and Nova. It is a Mac-only extension.

## Screenshots

These show a made-up app called Sample App.

![The chooser window titled "Select a build destination". It lists Sample iPhone, My Mac, two iPhone Simulators, and Any iOS Device, with the first one selected, and Cancel and Choose buttons at the bottom.](https://raw.githubusercontent.com/BeckyK102125/apple-build-tools-for-nova/main/docs/screenshots/chooser.png)

![A failed build report in Apple Build Reader. Its headings are Summary, Errors, Standard output, and Standard error. The Errors section comes first and lists two Swift errors with their file and line.](https://raw.githubusercontent.com/BeckyK102125/apple-build-tools-for-nova/main/docs/screenshots/build-report.png)

![The App Console for Sample App on Sample iPhone in Apple Build Reader. The summary says the app crashed, with 1 error and 1 warning. Errors and warnings come before the full output, and the crash report is added at the end.](https://raw.githubusercontent.com/BeckyK102125/apple-build-tools-for-nova/main/docs/screenshots/app-console.png)

![A crash report in Apple Build Reader. The "What happened" section explains the crash in one sentence, Details lists the app version, bundle ID, iPhone model, and iOS version, and Full report holds the original report.](https://raw.githubusercontent.com/BeckyK102125/apple-build-tools-for-nova/main/docs/screenshots/crash-report.png)

## Where to find everything

All commands are in the **Extensions** menu, under **Apple Build Tools for Nova**. You never need Nova's command palette (Shift-Command-P), which VoiceOver cannot read. The extension adds no keyboard shortcuts of its own; you can add your own in Nova's settings.

The two sidebars, **Apple Project Navigator** and **Apple Signing Status**, are in Nova's All Sidebars view: choose **View → Show All Sidebars** (it may be inside a **Sidebar** submenu), then choose the sidebar. Extension sidebars are only listed there; they do not get their own menu item.

## Getting started

1. Open your project's top-level folder in Nova.
2. From **Extensions → Apple Build Tools for Nova**, choose, in order:
   - **Apple Build: Select Xcode**
   - **Apple Build: Select Project or Workspace**
   - **Apple Build: Select Scheme**
   - **Apple Build: Select Configuration**
   - **Apple Build: Select Destination**: a connected iPhone, My Mac, or a specific iPhone Simulator. Simulator names include the iOS version and end with the device ID.
3. **Apple Build: Show Current Build Choices** reads back what is selected. Your choices are saved for this Nova workspace.
4. After you connect a device, add a Simulator, or change schemes, choose **Apple Build: Refresh Build Choices**. A destination that is gone is cleared, never silently replaced.

### Choosing from a list

Every list (Xcode, project or workspace, scheme, configuration, destination, and app reports) opens in a small **Apple Build Reader** chooser window. Down Arrow and Up Arrow move through the choices and VoiceOver reads each one. Return chooses. Escape or Command-W cancels and returns you to Nova. If the chooser cannot open, Nova's own palette is used so the command still works.

### Projects outside the open folder

**Apple Build: Select Project or Workspace** first lists the projects inside the folder open in Nova. Its last choice, **Choose a project or workspace path…**, opens a file chooser so you can pick an exact `.xcodeproj` or `.xcworkspace` anywhere, for example in a linked Git worktree. When the project is outside the open folder, or inside a hidden folder such as `.worktrees`, the extension works from the project's own folder. It never switches Git branches.

## Building, testing, and running

These commands are in **Extensions → Apple Build Tools for Nova**. They keep your focus where it is and end with a short message that VoiceOver reads.

- **Apple Build: Run Build**, **Apple Build: Run Clean**, and **Apple Build: Run Tests**. Clean uses Xcode's own clean action; it never deletes DerivedData or other files directly.
- **Apple Build: Build and Run** builds, then opens the app on the selected destination, and stops at the first step that fails:
  - **iPhone**: installs and opens the app with Apple's `devicectl`. The iPhone must be connected and unlocked, trust this Mac, and have Developer Mode on. The project must already be able to sign for the device; this extension never changes signing.
  - **My Mac**: opens the built app and brings it to the front. Running it again closes the previous copy first.
  - **iPhone Simulator**: starts the Simulator if needed, installs the app, and opens it.

  A generic destination such as Any iOS Device cannot be run; choose a specific one.
- **Apple Build: Stop Current Action** stops a build, clean, test, or Build and Run at any step. When nothing is building, it stops recording the App Console. It never closes the app on your iPhone.

When a build fails, the result message names the first error. Choose **View Build Command Report** in that message to read the full report. It starts with a Summary, then an **Errors** heading listing only Xcode's error lines, then the full output.

If Xcode says a scheme is not set up for testing, the message explains how to add a test target in Xcode (**Product → Scheme → Edit Scheme… → Test**).

### Nova's own Tasks

The extension also adds Nova tasks: **Apple Build: <scheme>** (Build and Clean) and **Apple Test: <scheme>** (Run tests). Their output goes to Nova's Reports sidebar, and file-and-line errors go to the Issues sidebar.

## Reading app output and problem reports

Consoles and reports open in **Apple Build Reader**, a native window where each title is a real heading. Use the VoiceOver rotor (VO-U) and choose **Headings** to jump between them. Command-Shift-C copies the whole document. Command-W closes the window and returns you to Nova. If the reader cannot open, the document opens in Nova; use Nova's **Open Preview in Tab** there for headings.

- **Apple Build: Show App Console.** After **Build and Run** opens your app, the extension keeps recording what the app prints (standard output and standard error, such as Swift `print`). The console has the headings Summary, Errors and warnings, Full output, and, after a crash, Crash report. The Summary says whether the app is still running and counts errors and warnings. Only the newest 10,000 lines are kept. Messages written with Apple's `Logger` go to the system log instead and are not shown yet.
- **Apple Build: Show App Reports.** Finds this app's problem reports for the selected destination, from the iPhone itself or from this Mac's DiagnosticReports folder for My Mac and Simulators. It lists the newest 10 in plain words, for example "Crash, October 7 at 6:47 AM". The report you choose opens with the headings What happened, Details, and Full report.

Consoles and reports are saved on this Mac in `~/Library/Logs/Apple Build Tools for Nova/<app name>/`, never in your project. The newest 20 files per app are kept. Nothing is sent anywhere. Function names in crash reports are shown as addresses for now.

## Signing Status

Open **Apple Signing Status** from **View → Show All Sidebars**, then activate its **Refresh** button. You can also choose **Apple Signing: Refresh Status** from the Extensions menu. The sidebar shows each target with its bundle identifier, signing style, team, identity, profile, entitlements file, SDK, and a plain status: Ready, Warning, Unavailable, or Error.

Signing Status only reads. It never creates, downloads, repairs, or changes certificates or provisioning profiles, and it does not read private keys. Ready means the settings look complete; it does not promise that an archive, upload, or App Store submission will succeed.

## Project Navigator

After selecting a project, open **Apple Project Navigator** from **View → Show All Sidebars**. It shows the project's groups, folders, and files the way Xcode does, without Products and SDK references.

- Up Arrow and Down Arrow move between rows. Right Arrow expands and Left Arrow collapses.
- Double-click a file, activate the **Open** button, or choose **Apple Build: Open Selected Project Navigator File**.
- After changing the project outside Nova, activate **Refresh** or choose **Apple Build: Refresh Project Navigator**.

Workspaces (`.xcworkspace`) are not shown in the navigator yet; it says so instead of showing something else.

## Spoken alerts (for people who do not use VoiceOver)

VoiceOver already reads every chooser, message, console, and report, so the extension adds no speech of its own by default. Two settings turn on the Mac's speech voice for people who do not use VoiceOver, for example people with low vision:

- **Announce choices and progress** (off by default): confirms each saved choice, for example "Scheme MyApp selected.", says when a build, clean, test, or Build and Run starts or reaches its next step, and says when a console or report is ready.
- **Announce app crashes and errors** (off by default): while the App Console is recording, says when the app reports its first error, crashes, or quits.

To change them, open Nova's **Extension Library**, choose **Apple Build Tools for Nova**, and open its **Settings**.

## What it does not do

Apart from **Build and Run**, it does not install or open apps. It does not archive, export, upload to TestFlight or the App Store, attach a debugger, change signing, change the Mac's selected Xcode, use the network, or use AI.
