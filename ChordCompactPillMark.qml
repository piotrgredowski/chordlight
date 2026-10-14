pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
  id: mark

  property color iconColor: "#f3f4f6"

  implicitWidth: 26
  implicitHeight: 24
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    x: 2
    y: 6
    width: 22
    height: 15
    radius: height / 2
    antialiasing: true
    color: "#292b30"
    border.color: mark.iconColor
    border.width: 1.1
  }

  Rectangle {
    x: 2
    y: 3
    width: 22
    height: 15
    radius: height / 2
    antialiasing: true
    color: "#202226"
    border.color: mark.iconColor
    border.width: 1.5
  }

  Shape {
    x: 6
    y: 3.5
    width: 14
    height: 14
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: mark.iconColor
      strokeColor: "transparent"
      startX: 7
      startY: 0
      PathCubic {
        x: 14; y: 7
        control1X: 7.3; control1Y: 4.6
        control2X: 10.2; control2Y: 7
      }
      PathCubic {
        x: 7; y: 14
        control1X: 10.2; control1Y: 7
        control2X: 7.3; control2Y: 9.4
      }
      PathCubic {
        x: 0; y: 7
        control1X: 7.3; control1Y: 9.4
        control2X: 3.8; control2Y: 7
      }
      PathCubic {
        x: 7; y: 0
        control1X: 3.8; control1Y: 7
        control2X: 6.7; control2Y: 4.6
      }
    }
  }
}
