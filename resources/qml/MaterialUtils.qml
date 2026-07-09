pragma Singleton
import QtQuick 2.15

// =====================================================================
// MaterialUtils — shared helper functions for materials list management
// =====================================================================
// Provides parseMaterials() and stringifyMaterials() used across
// ExamForm.qml, ExamInfoEditor.qml, and EditorWindow.qml.
//
// QML ListModel converts JS arrays into ListModel objects, which break
// JSON.stringify, so materials are stored as JSON strings in the exam
// list model.
// =====================================================================

QtObject {
    id: utils

    /// Parse a materials value (JSON string, JS array, or undefined) into a JS array.
    function parseMaterials(value) {
        if (value === undefined || value === null) return []
        if (typeof value === "string") {
            try { return JSON.parse(value) } catch (e) { return [] }
        }
        if (Array.isArray(value)) return value
        return []
    }

    /// Serialize a JS array of materials into a JSON string for storage.
    function stringifyMaterials(arr) {
        return JSON.stringify(arr || [])
    }

    /// Build a materials array from a ListModel (for syncing back to exam data).
    function materialsFromModel(listModel) {
        var arr = []
        for (var i = 0; i < listModel.count; i++) {
            var m = listModel.get(i)
            arr.push({
                name: m.name || "",
                quantity: m.quantity !== undefined ? m.quantity : 1,
                unit: m.unit || "份"
            })
        }
        return arr
    }

    /// Populate a ListModel from a materials JSON string.
    function materialsToModel(jsonStr, listModel) {
        listModel.clear()
        var arr = parseMaterials(jsonStr)
        for (var i = 0; i < arr.length; i++) {
            listModel.append({
                name: arr[i].name || "",
                quantity: arr[i].quantity !== undefined ? arr[i].quantity : 1,
                unit: arr[i].unit || "份"
            })
        }
    }

    /// Sync materials from a ListModel back to the examListModel property.
    function syncMaterialsToExam(examListModel, examIndex, materialsModel) {
        if (examIndex < 0 || examIndex >= examListModel.count) return
        var arr = materialsFromModel(materialsModel)
        examListModel.setProperty(examIndex, "materials", stringifyMaterials(arr))
    }
}
