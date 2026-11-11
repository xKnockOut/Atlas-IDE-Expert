# Forms

Back to the [README](../../../README.md)

- Open forms are sent to the server as the designer has them: references, renames and checks also see unsaved components
- Renaming an event handler also updates its assignment in the designer
- The form's components in completion, `Sender` with the matching typecast
- Checks between form and code and **property rules** for form files with quick fix
- Convert binary forms to text forms

## In the designer

Commands of the [designer bar](Navigating.md#designer-bar) for the selection in the form designer:

- **Select similar** (#738): all components of the same class, also with descendants (from the common base class for a multiple selection), with the same parent, the children or all descendants of a container, with the same stored property value (`Font.Name = 'Tahoma'`) or the same event handler; plus “Invert selection”. Every entry shows its hit count, Shift while clicking adds to the selection. Scope is the whole form or the parent only (`designer.selectSimilar.scope`).
- **Selection sets** (#739): In the same menu, “Save selection …” (or Ctrl+Shift+S in the designer) stores the selection under a name per form. Ctrl+Shift+1…9 restores the first nine sets; in the menu a click restores, Shift+click adds, Ctrl+click removes, plus overwrite, extend, rename, move and delete. Renamed components stay in the set, deleted ones drop out. Stored locally or shared next to the form (`designer.selectionSets.storage`); the .dfm stays unchanged.
