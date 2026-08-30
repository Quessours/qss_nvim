; extends

; width: 100
((ui_binding name: (identifier) @qml.binding.target)
 (#set! priority 126))

; anchors.fill: parent
((ui_binding name: (nested_identifier) @qml.binding.target)
 (#set! priority 126))

; property int count: 0
((ui_property name: (identifier) @qml.binding.target)
 (#set! priority 126))
