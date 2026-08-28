import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "qopen.launcher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖟"
    tooltipText: "QOpen · left: all · right: favorites"
    horizontalMargin: 7.5

    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton)
        root.bar.run("omarchy-shell shell toggle qopen.launcher '{\"favorites\":true}'")
      else
        root.bar.run("omarchy-shell shell toggle qopen.launcher '{}'")
    }
  }
}
