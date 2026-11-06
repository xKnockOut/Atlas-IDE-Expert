# Writing

Back to the [README](../../../README.md)

## Code completion

### Popup

Code completion in its own popup:

- detail panel with coloured declaration and docs
- filter chips
- fuzzy matching
- learning order
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
- **Slash commands** run after Enter, such as `/uses Unit`, `/extract`, `/inline`, `/fix`, `/explain`, `/case`, `/helper`, `/test`, `/component`, `/unit`, `/sortuses`, `/cleanuses`
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

- Keep method bodies in declaration order (#660):
  - new bodies from class completion move to their place in one undo step
  - "Order implementation like class" with preview
- Maintain var blocks (#644):
  - convert a variable to an inline variable at its first assignment and back
  - tidy the var section (remove unused, sort by first use or name, merge equal types)
  - comments move along

### More editing

- **Complete statement** (Ctrl+Shift+Enter)
- **Continue patterns** as ghost text
- **Continue comments** on Enter
- **Indentation while typing** (#1827, `smartIndent`, page *Typing aids*): after Enter Atlas works out with the formatter's block logic where the caret belongs: one level deeper after `begin`, `then`, `do`, `try`, `case` labels and sections, back after the single statement, inside an open parenthesis under the first argument. If the line above starts with `end`, `until`, `finally`, `except` or `else`, it moves to its counterpart. Enter inside a string closes it with `' +` and reopens it on the new line, indented or aligned (`smartIndent.splitStringsIndent`). If the file deviates from the style, Atlas follows its existing indentation. Ctrl+Z undoes just the indentation. Atlas never inserts `end;`.
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
