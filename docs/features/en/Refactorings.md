# Refactorings and code actions

Back to the [README](../../../README.md)

Alt+Enter opens the code actions; everything is also in the *Atlas* menu and the editor context menu.

## Rename and signature

- **Rename** project-wide with preview, including `.dfm`/`.fmx` and automatically named event handlers
- **Change signature** in a dialog: add, remove, move and rename parameters, with preview

## Extract and introduce

- **Extract method**
- **Introduce variable**
- **Extract condition to function**

## Conditions and statements

- **Resolve `with`**
- **Complete `case`**
- **Convert `if` chain ⇄ `case`**
  - in both directions, sets and ranges included
  - comments stay
- **Rewrite conditions**
  - invert a condition with readable negation
  - introduce an early `Exit`/`Continue`
  - merge nested `if`s
  - remove double negation
- **Convert `if` statement ⇄ conditional expression**
  - Delphi 13 `X := if C then A else B` for assignments, `Exit` and calls
  - `else if` chains as nested expressions
  - parentheses only where precedence needs them
  - replace `IfThen`, which evaluates both branches

## Routines, variables and methods

### Convert local routine ⇄ method

- A nested routine becomes a private method or a unit routine:
  - the outer variables it uses become `var`/`const` parameters
  - the calls get the arguments
- A private method or unit routine with exactly one caller becomes a local routine of that caller
  - optionally without the parameters that only pass the caller's variables through
- Preview with the new signature first
- A hint instead of the action when the meaning of a name would change

### Convert local variable ⇄ field

- A local or inline variable of a method becomes a private field behind the last field:
  - `LLineNo` → `FLineNo` with the name editable
  - an initialisation stays as an assignment
  - the type of an untyped inline variable is inferred
- A private field used by only one method, which writes it first on every path, becomes a local variable
  - not for fields behind a property, published or form fields
- Preview with warnings such as the changed lifetime of an object

### Convert anonymous method ⇄ method

- An anonymous method becomes a private method, or a unit routine in a free routine:
  - named from the context such as `HandleClick` or `CompareByName`
  - captured variables become parameters and a short forwarding anonymous method stays in place
  - or the values go into fields for deferred calls if configured
- A private method passed exactly once to a `reference to` type becomes an anonymous method again
  - never for `of object` targets or form events
- The preview explains the chosen form

### Convert a method without `Self`

- A method that uses neither `Self` nor instance members gets a “no Self” marker and becomes:
  - a `class … static` method,
  - a class method with its calls rewritten to the class,
  - a free routine,
  - or a record helper for the type of its first parameter
- Across all units with a preview of every changed call
- Optional hint rule `method-without-self`

### Create overload

- As a copy right behind the original:
  - both with `overload`
  - then Tab through parameter list and body
- As a forwarding overload without the last parameter:
  - calls the existing one with the default value of its type, e.g. `Write(AText, llInfo)`
- `override` and `virtual` are not copied
- Atlas never writes default parameters

## Types

### Introduce and inline type aliases

- `TList<TKunde>`, arrays, sets and method references get a named alias placed before their first use
- Replacing this spot, every equal expression of the unit or of the project
  - equality by resolved types
- Open generic parameters are refused with the reason
- “Inline alias” replaces `X = Y` by `Y` where Delphi accepts it and removes the alias

### Enumeration name tables

- Create `CStateNames: array[TState] of string` with texts from the value names, optionally as resourcestrings
- When values are added or removed, each table gets “add missing entry”/“remove surplus entry” at the right position
- “Update tables” fixes every table over the type in the project and completes `case` statements without `else`, with a preview

## Safe delete

- Shortcut Alt+Del
- Delete a method, field, property, type, constant, variable, routine or a whole unit only after searching for usages:
  - in the project
  - in forms
  - in uses clauses
- Overrides and members that become unused can go too

## Experimental

- **Inline variable and method** *(experimental)*
- **Move class to its own unit** *(experimental)*
- **Update uses after renaming a unit** *(experimental)*

## Class actions

- Implement interface
- Override methods
- Generate getter, setter and field
- Property from existing accessors
- Extract interface from a class
- Extract superclass
- Pull members up or push them down
- Replace trivial accessors with their field (one at a time or for a unit or project)
- Create method from a call
- Add forward declaration

## Strings, uses, fixes, undo

- **Strings:** move a string literal to a `resourcestring`
- **uses:** add the missing unit, sort, remove unused ones
- **Quick fixes** for many check rules, also "fix all"
- **Undo Atlas changes** (Ctrl+Alt+Z): changes across several files as one step
