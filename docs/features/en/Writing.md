# Writing

Back to the [README](../../../README.md)

## Code completion

### Popup

Code completion in its own popup:

- detail panel with coloured declaration and docs
- filter chips
- fuzzy matching
- learning order
- ranking from usage in the project (#2109, `completion.projectFrequency`): while your own weighting is empty, `X.` lists the members whose name occurs most often in the project's units first, tagged “in project 214×”. Your own picks (“recent”, “frequent”) and better matches come first. Counted by name from the index usages; libraries do not count, and the number is right after a change without a rebuild.
- favourites (Ctrl+D)
- typo suggestions ("did you mean")
- in-editor preview
- `+ Unit` hint for units not yet in `uses`

### Context-aware

- Enum values first
- Set elements with checkboxes
- `case` with all or the missing values
- Only types after `:`
- Type arguments matching constraints
- Attributes after `[` without the `Attribute` suffix (#465)
  - DUnitX and JSON first
  - constructor in the parameter hint
- Exceptions (#483, `completion.exceptionClasses`):
  - only exception classes after `raise` and `on E:`
  - inserted as `EFoo.Create('')` with `CreateFmt` alongside
  - after `on E:` the classes the `try` block can raise first (XMLDoc `<exception cref>`, `StrToInt` → `EConvertError`)
  - a warning when an earlier handler already catches the class
- Members of `with` objects tagged “aus qryOrders” (#481, `completion.withOrigin`)
  - with a warning when they hide `Self.Name` or a local
- Anonymous method skeletons where a method reference is expected (#468, `completion.anonymousMethods`)
  - `TTask.Run(` gives `procedure begin … end`
  - `TPredicate<TCustomer>` gives `function(const Value: TCustomer): Boolean`
- Full `inherited` call
- Field and parameter names in `FieldByName('`
- The form's components
- `Sender` with the matching typecast
- After a type check the members of the checked type (#2107, `completion.typeGuards`)
  - in the then branch of `if X is T then` (also in `and` chains) and after `if not (X is T) then Exit;` up to the end of the block, `X.` lists the members only `T` has at the top under “X is T here (is check, line n)”
  - accepting writes `T(X).Name` or `(X as T).Name` according to `completion.senderCast`
  - not after an assignment to `X`, after passing it to a `var` or `out` parameter, in the else branch, and for fields after any further statement
  - after `X is ` and `X as ` the descendants of the type of `X` come first
- Matches that are only missing because of their visibility (#2108, `completion.hiddenMembers`)
  - after `X.Pr` the footer names private, protected and strict protected members that match what was typed, such as “1 match not visible: FPrivate (private in TCounter) · Ctrl+Space shows it”
  - a second Ctrl+Space shows them dimmed at the end of the list under “Not visible · Enter offers actions” with the tag “private · TCounter”
  - Enter does not insert them but offers “Raise visibility of FPrivate to protected/public” and, for fields, “Create property Private in TCounter” (read-only or read and write); the change goes to the file of the declaration, even if it is not open. Members from external code (libraries, `$(BDS)`) get no actions
  - without visible matches the empty state names them
  - only with a typed prefix; a visible member of the same name (overload) suppresses the notice
- Same names from different units
- Helper methods
- `uses` list with groups

### Incomplete code (#457, `completion.syntaxNotice`)

- If a syntax error before the cursor in the current routine or class declaration limits the context, a warning bar on top of the list says “Results may be incomplete · syntax error in line n”
- Clicking the line jumps there
- Without suggestions the empty state names the error
- Errors in other routines and the spot being typed do not count

### Unknown names

- Create a local variable, inline variable, field or method right from the list
- Name suggestions from the type

### Parameter hint

- With all overloads, the active parameter and overload choice by argument types
- For `Format` and other format routines (#451, `completion.formatPlaceholders`):
  - names the placeholder of the argument at the cursor ("placeholder 2 of 2 expects integer")
  - warns about surplus arguments, invalid placeholders and literals of the wrong type
  - colours each placeholder and its argument alike in the editor
  - own routines via `formatFunctions` in `.atlas` or `formatMethods` of `format-args`

## Templates and generators

- **Templates:**
  - code templates (`tryf`, `forin`, `prop`, …)
  - your own `*.atlas-snippet` files
  - the IDE's Live Templates
  - class-aware templates (`prop`, `create`, `free`)
  - postfix templates (`List.forin`, `Obj.notnil`, `Obj.free`)
- **Slash commands** run after Enter, such as `/uses Unit`, `/extract`, `/inline`, `/fix`, `/explain`, `/case`, `/helper`, `/test`, `/mock`, `/testcase`, `/dump`, `/assert`, `/component`, `/unit`, `/sortuses`, `/cleanuses`
- **Generate menu** (Alt+Ins): constructor, properties, overridden methods, interface methods, surround, templates
- **Guard the free:** after `X := TFoo.Create;` an offer for `try … finally X.Free; end;`
- **Documentation comments:** `///` creates the XMLDoc skeleton with placeholders

## Editing helpers

| Helper | Shortcut / issue |
|---|---|
| Highlight text matching the selection | #709 |
| Highlight exit points of a routine, with F3 between them | #698 |
| Underline reassigned variables with a hover count and an optional "declare as constant" fix | #712 |
| Show the type of the selected expression with conversions, chosen overload and constant value, expanding on repeat | #689, Ctrl+Shift+T |
| Toggle block comment | #703, Shift+Alt+A |
| New line above or below | #700, Shift+Enter, Ctrl+Alt+Enter |
| Surround the selection while typing | #672 |
| Remove the surrounding construct, with preview | #657, Ctrl+Shift+Del |
| Atlas column in the gutter | #768 |

- Order method bodies (#660, #1836; `editor.methodPlacement`):
  - default "grouped, constructors first": constructors and destructor, then get/set pairs in property order, then overrides, then the rest as declared; also "like the declaration" and "alphabetically", where `classCompletion.lifecycleFirst` also puts constructors first
  - new bodies from class completion move to their place in one undo step
  - "Order implementation like class" with preview; the comment above a class section and a `{$REGION 'TCustomer'}` move along
- Class completion (#1834, `classCompletion.*`):
  - comment above a class section (#1835, `typeComment`): `{ TCustomer }` like the IDE (default), separator line with `// TCustomer`, `{ TCustomer: first sentence of the doc }`, a region around all bodies, or none; an existing one is not duplicated
  - prefilled new bodies (#1837, `bodyStubs`): `inherited` for `override`, at the end of the destructor, getter `Result := FName` and setter `FName := AValue`
  - Rename and "Move class" take the `{ TCustomer }` comment along (#1838)
- Maintain var blocks (#644):
  - convert a variable to an inline variable at its first assignment and back
  - tidy the var section (remove unused, sort by first use or name, merge equal types)
  - comments move along

### More editing

- **Complete statement** (Ctrl+Shift+Enter)
- **Continue patterns** as ghost text
- **Continue comments** on Enter
- **Indentation while typing** (#1827, `smartIndent`, page *Typing aids*): after Enter Atlas works out with the formatter's block logic where the caret belongs: one level deeper after `begin`, `then`, `do`, `try`, `case` labels and sections, back after the single statement, inside an open parenthesis under the first argument. If the line above starts with `end`, `until`, `finally`, `except` or `else`, it moves to its counterpart. Enter inside a string closes it with `' +` and reopens it on the new line, indented or aligned (`smartIndent.splitStringsIndent`). If the file deviates from the style, Atlas follows its existing indentation. Ctrl+Z undoes just the indentation. Atlas never inserts `end;`.
- **Learned suggestions** (#1890, `suggestions.*`, page *Completion*): while indexing Atlas notes per unit which statement follows another: after `X := TFoo.Create;` a `try … finally X.Free; end;`, after `L.BeginUpdate;` a `try … finally L.EndUpdate; end;`, after `Q.Open;` a `while not Q.Eof do … Q.Next;`. If a pattern follows at `suggestions.minCount` places or more (default 5) with a share of `suggestions.minShare` percent (default 70), it appears after Enter and a typing pause (`suggestions.delayMs`, 300 ms) as grey ghost text on one line. Tab writes the whole block and puts the caret into the body, Ctrl+→ accepts word by word, Esc discards. The status field shows "learned from N places"; its hint names three examples, a click jumps there. Before showing a suggestion Atlas checks it with the parser and name resolution. Discarded patterns appear less often, accepted ones more readily (`suggestions.learnFromUsage`, per project group in `%LOCALAPPDATA%\Atlas`). "Show learned suggestions …" (context menu, command palette) lists all patterns with share and origin, turns single ones off and forgets their counters. Team house rules live in `atlas.json` under `suggestions.patterns` and take precedence over learned ones. No AI and no network; can be turned off with `suggestions.learned`.
- **Move and duplicate lines** (Alt+↑/↓, Shift+Alt+↑/↓)
- **Multiple cursors** *(experimental)*
- **Linked editing of identifiers** *(experimental)*
- **Paste with uses completion** *(experimental)*

## Formatting

- **Formatting** by its own rules (Ctrl+Shift+Alt+L), since RAD Studio 13 no longer has a formatter
- Regions between `// atlas-format: off` and `// atlas-format: on` stay untouched
- The same formatter runs without the IDE (`--format-check`, `--format-write`, MCP `format_code`, see [Formatting without the IDE](Command-line.md#formatting-without-the-ide))

## Language support

### Conditional compilation

- Outline, hover, go to and checks see only the active `{$IFDEF}` branches of the project; the outline shows the branch condition (#845)
- `{$IF}` understands `SizeOf`, `High`, `Low`, `RTLVersion111` and `Declared` (#847)
- `{$IFOPT}` follows the switches of the `.dproj` and local `{$R-}`
- Unknown values keep both branches active
- The hover on a condition explains its value (#847)

### Defines from include files (#860)

- A `{$DEFINE}` in a file pulled in with `{$I}` counts for greying out, the outline, checks and the linter
- An inlay hint behind `{$I}` lists the symbols the file defines

### Variant records (#846)

- Fields such as `TRect.Left` or `TMessage.WParam` appear in completion, hover, go to and the outline, tagged with their branch

### Class helpers with an ancestor (#848)

- `class helper (TBaseHelper) for TFoo` is read as a helper
- `Foo.` also offers the members of the ancestor helper

### Less common syntax

The following parse without errors:

- several constraints per type parameter
- named OLE arguments (`Open(FileName := 'a.docx')`)
- calling conventions without a semicolon
- `cdecl varargs`, `assembler asm`
- local routines in anonymous methods
- `{$I file.inc}` as a constant value
- long `else if` chains
- `@@End` labels in `asm` blocks (#861)
- control characters such as `^C` and the brackets `(.` `.)` (#862, with an inlay hint showing the code)
- identifiers with `&&` such as Spring4D's `&&op_Equality` (#1137)
- empty record constants `= ()` (#1138)
- `class threadvar`, `class operator In` and `type AnsiString(1252)` (#1140)
- `end align 16`, attributes in variant record parts, `IBaz<string>=nil` and `%_0101` (#1142)
- named arguments with a reserved word such as `Foo(Type := 1)`, calling conventions on anonymous methods and attributes on inline variables (`var [Weak] Obj: IFoo := nil`, #1167)
- method resolution clauses for functions such as `function IFoo.GetX = MyGetX` (#1134)

Also:

- under `{$SCOPEDENUMS ON}` values need their type prefix
- members from `{$I}` inside a class belong to the class (#849)
