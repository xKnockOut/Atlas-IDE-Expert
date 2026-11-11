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
- **Spatial navigation** (#745): Alt+Arrow selects the next control in that direction, Alt+Shift+Arrow adds it, Alt+Home selects the parent, Alt+End the top-left child, Alt+Page Up/Down switches the container. At the edge of a panel it continues into the panel next to it (`designer.spatialNavigation.crossContainers`); a short frame shows the target.
- **Arrange › Width from text** (#730): sets the selected buttons, check boxes and labels to the width of the longest text plus padding, at least 75 px. In a row the gaps stay, and so does the right edge if the row is anchored right; AutoSize and Align without free width stay.
- **Arrange › Arrange button bar** (#732): OK, Cancel, Apply and Help in the right order, equally wide, anchored bottom right; plus Default, Cancel and ModalResult unless the handler closes the form itself. Role from caption, name or ModalResult, own terms in `designer.buttonBar.roles`.
- **Arrange › Duplicate in row …** (#736): select a label/field pair, enter the list “Fax, Mobile, Home”, press Enter: three pairs `lblFax`/`edtFax` etc. with captions “Fax:” … below at the same gap, tab order after the original, `FocusControl` pointing to the new field. Without a list the number counts up (`edtTelefon2`). Outlines of the copies appear in the designer while you type, red on overflow; “Move following controls” makes room. “Undo duplicate” removes the last run.
- **Arrange › Insert space … / Remove space …** (#740): select row 3 of a form, insert 30 px: row 3 and everything below moves down 30 px, a memo with `[akTop, akBottom]` crossing the line gets longer, the form grows if the content no longer fits. Removing stops at the next control above. Columns work the same at the left edge. “Undo space” reverts the last step.
- **Arrange › Fit to content** (#742): a group box with two radio buttons shrinks until both fit with an 8 px margin and the caption; without a selection the form fits itself, buttons with `[akRight, akBottom]` end up 8 px from the edge. Submenu: width and height, width only, height only, all to the same width. “Undo fit to content” reverts the last step.
- **Arrange › Near-aligned edges** (#746): three edits stacked with Left 90, 92 and 90: “Show” reports `edtFax.left -2` and outlines edtFax in the designer for a few seconds; with an offset of 4 px and tolerance 3 nothing is reported. “Align all” moves edtFax to 90 (revert with “Undo align edges”). What is intended is marked with “Mark selection as intended”; the exception is stored in `.atlas-nearalign.json` next to the form and can be checked in. Text baselines of a label and an edit side by side are compared too (approximated from the font).

## Own buttons in the designer bar

Larger features have their own button in the designer bar and their own setting:

- **Measure distances** (#605): while dragging and resizing, guide lines to the nearest neighbour in the same parent or to the inner edge of the parent (padding included) show the distance in DFM pixels, also at 150 % scaling. An edit between two labels shows “8 px” upwards; if two other fields in the same panel are 8 px apart as well, the line turns accent coloured with “8 px as above”. Resizing adds width × height, with “width as btnOk” when a neighbour has the same width. With Alt held, hovering another control shows the distances between the selection and that control without changing anything. The button turns the display off for the session; `designer.measureDistances` and `designer.measureAltKey` switch it off completely.
