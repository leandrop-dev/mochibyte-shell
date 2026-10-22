pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    // Versions are short git commit hashes of the installed and latest upstream revision.
    property bool isChecking: false
    property string localVersion: "unknown"
    property string remoteVersion: ""
    property bool updateAvailable: false
    property string lastNotifiedVersion: ""

    function reevaluateUpdate() {
        if (!root.remoteVersion || root.localVersion === "unknown") {
            root.updateAvailable = false;
            return;
        }
        root.updateAvailable = root.remoteVersion !== root.localVersion;
    }

    function saveNotifiedVersion(ver) {
        if (typeof Caching === "undefined" || !Caching.mochibyteDir) return;
        let stateDir = Caching.getStateDir();
        Quickshell.execDetached([
            "python3",
            Caching.mochibyteDir + "/scripts/updater.py",
            "--state-dir",
            stateDir,
            "--save-notified",
            ver
        ]);
    }

    function sendNotification() {
        let mochiDir = (typeof Caching !== "undefined" && Caching.mochibyteDir) ? Caching.mochibyteDir : "";
        let appName = I18n.t("updater.notification.app_name");
        let actionText = I18n.t("updater.notification.action_open_guide");
        let notifTitle = I18n.t("updater.notification.update_available_title", { "remote": root.remoteVersion });
        let notifBody = I18n.t("updater.notification.update_available_body", { "local": root.localVersion });
        let actionArg = "default=" + actionText;

        let script = 'if command -v notify-send >/dev/null 2>&1; then ' +
            'ACTION=$(notify-send -a "' + appName.replace(/"/g, '\\"') + '" ' +
            '-i "software-update-available" ' +
            '-A "' + actionArg.replace(/"/g, '\\"') + '" ' +
            '"' + notifTitle.replace(/"/g, '\\"') + '" ' +
            '"' + notifBody.replace(/"/g, '\\"') + '"); ' +
            'if [ "$ACTION" = "default" ]; then ' +
            'DIR="' + mochiDir + '"; ' +
            'if [ -n "$DIR" ] && [ -f "$DIR/scripts/settings.sh" ]; then ' +
            'bash "$DIR/scripts/settings.sh" open about; ' +
            'fi; fi; fi';
        Quickshell.execDetached(["bash", "-c", script]);
    }

    function checkUpdate() {
        if (typeof Caching === "undefined" || !Caching.mochibyteDir) return;
        if (updateProc.running) return;
        root.isChecking = true;
        updateProc.running = true;
    }

    function scheduleInitialCheck() {
        if (typeof Caching === "undefined" || !Caching.mochibyteDir) return;
        if (checkDelayProc.running) return;
        checkDelayProc.running = true;
    }

    FileView {
        id: versionFileView
        path: (typeof Caching !== "undefined" ? Caching.getStateDir() : "") + "/version"
        onFileChanged: {
            versionFileView.reload();
        }
        onLoaded: {
            let content = this.text();
            if (!content) return;
            let lines = content.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("MOCHIBYTE_COMMIT=") === 0) {
                    let v = line.substring("MOCHIBYTE_COMMIT=".length).replace(/["']/g, "").trim();
                    if (v) {
                        root.localVersion = v;
                        root.reevaluateUpdate();
                    }
                    break;
                }
            }
        }
    }

    Timer {
        id: startupTimer
        interval: 500
        repeat: false
        running: !Caching.isStandalone
        onTriggered: root.scheduleInitialCheck()
    }

    Timer {
        id: initialDelayTimer
        interval: 1500
        repeat: false
        running: false
        onTriggered: {
            root.checkUpdate();
            periodicTimer.restart();
        }
    }

    Timer {
        id: periodicTimer
        interval: 60 * 60 * 1000
        repeat: true
        running: !Caching.isStandalone
        onTriggered: root.checkUpdate()
    }

    Process {
        id: checkDelayProc
        running: false
        command: [
            "python3",
            (typeof Caching !== "undefined" ? Caching.mochibyteDir : "") + "/scripts/updater.py",
            "--state-dir",
            (typeof Caching !== "undefined" ? Caching.getStateDir() : ""),
            "--delay"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                let delay = parseInt(out, 10);
                if (isNaN(delay) || delay <= 0) {
                    initialDelayTimer.interval = 1500;
                } else {
                    initialDelayTimer.interval = Math.max(1500, delay);
                }
                initialDelayTimer.running = true;
            }
        }
    }

    Process {
        id: updateProc
        running: false
        command: [
            "python3",
            (typeof Caching !== "undefined" ? Caching.mochibyteDir : "") + "/scripts/updater.py",
            "--state-dir",
            (typeof Caching !== "undefined" ? Caching.getStateDir() : "")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") {
                    try {
                        let data = JSON.parse(out);
                        if (data.local) root.localVersion = data.local;
                        if (data.remote) root.remoteVersion = data.remote;
                        if (data.last_notified !== undefined) root.lastNotifiedVersion = data.last_notified;
                        root.reevaluateUpdate();

                        if (!Caching.isStandalone && root.updateAvailable && root.remoteVersion !== root.lastNotifiedVersion) {
                            root.lastNotifiedVersion = root.remoteVersion;
                            root.saveNotifiedVersion(root.remoteVersion);
                            root.sendNotification();
                        }
                    } catch (e) {}
                }
            }
        }
        onExited: {
            root.isChecking = false;
        }
    }
}
