# Code analysis

Back to the [README](../../../README.md)

The server checks every unit while you type. Findings appear:

- as squiggles,
- in the tooltip,
- shortened at the end of the line,
- project-wide in the dockable window **"Atlas Findings"** (Ctrl+Alt+P).

Marks move along while typing.

## Findings window, hover and options page

### Window "Atlas Findings"

- Live findings of the file, the current project or the project group
- With a group open, the scope list shows every project of the group below a separator, so the window can show a project without activating it (can be switched off: `problems.window.scopeProjects`)
- Filters per kind, category and text
- Grouping by file, rule or category; sortable columns
- Keys:

  | Key | Action |
  |---|---|
  | Enter | jumps |
  | Alt+Enter | fixes |

- Context menu:
  - suppress, configure, disable and explain the rule
  - "Fix all safe findings of …": bulk fix with a preview per file, deselectable, one undo step per file (`fix.bulk`)
- "Open first":
  - the unit in the editor is pinned on top
  - the other open units follow
  - units that are not open come last, dimmed (or shown normally or hidden)
  - optionally the active unit also shows without findings ("No findings")

### When the check runs

- `problems.update` (*Tools › Options › Atlas › Rules › Check window*):
  - live while typing, with its own delay `problems.liveDelayMs` in milliseconds (100 to 10000, default 400)
  - on save
  - only on request via "Check file now" (command palette, editor context menu, own shortcut Ctrl+Shift+Alt+P `keys.checkFile`, click on the check field in the Atlas status bar, e.g. "on save · project 91 %")
- The former setting "Check while typing" is carried over

### Finding hover

- Shows severity and rule
- Action line "Alt+Enter: fix", "Suppress for this line", "Configure rule…"

### Page "Check rules" in the options

- Per rule group a master switch
- A table with severity, exclusions and options of every rule
- Search and catalog text with examples

## Check rules

**313 check rules** in four categories: 204 bugs, 99 code smells, 5 vulnerabilities, 5 security hotspots. Among them:

### Correctness

- `Result` not set
- Possibly uninitialized variables
- Unreachable code
- Unused variables, parameters and assignments
- Declared but not implemented methods
  - also with special forms such as `class constructor`, a short-form implementation `function Foo;`, `Execute()` with empty parentheses, constraints only in the declaration, `asm` or `external` bodies and interface method resolutions
  - these are neither reported as missing overloads nor as unknown directives
- Missing `override`, hidden virtual methods
- Overflows, float comparison
- `raise` in `finally`
- Overlooked precedence of `not` (`not X in Set`)
- Empty statement after `then`/`do`/`else`
- Loops one step too far (`0 to List.Count`)
- Lists changed inside their own loop (`Delete` in a forward loop)
- Objects used after `Free` (with a jump to the release)
- Access before the nil check (`X.Name` before `if Assigned(X)`)
- Fields:
  - freed outside the destructor without `nil`
  - created in the constructor that the destructor never frees
- Destructors that use a field which is still nil after an exception in the constructor
  - e.g. `FLines.Clear` when `TFileStream.Create` raised before
  - quick fix `if Assigned`
- Windows handles from `CreateFile`, `FindFirstFile`, `RegOpenKeyEx`, `LoadLibrary`, `GetDC` or GDI objects that are not closed on every path (quick fix `try … finally CloseHandle`)
- Objects created in `initialization` or a `class constructor` that `finalization` or the `class destructor` never frees
- Constructors and destructors without `inherited`
- `Destroy` instead of `Free`
- `FillChar`/`Move`/`GetMem` on records with strings or interfaces
- `PChar` of temporary strings
- `out` parameters read before they are set
- `Find` on unsorted `TStringList`s
- `DelimitedText` without `StrictDelimiter`
- Changes to the global `FormatSettings` that affect the whole application and all threads (quick fix: a local `TFormatSettings`)
- `Writeln` in programs without a console
- `raise` in destructors
- Duplicate conditions and identical branches
- `case` over enumerations with missing values
- `DisableControls`/`BeginUpdate`/`Screen.Cursor` without `try`/`finally`
- `StrToInt` on `Edit.Text` without a check
- Numbers from the database, registry or text cast to an enumeration without a range check (quick fix with `InRange`)
- `CreateProcess` with a read-only command line such as `PChar('notepad.exe')` (quick fix with a copy and `UniqueString`)
- Access in `OnCreate` to a form that the `.dpr` creates only later
- `on E: Exception` before a more specific handler that is never reached (quick fix moves it up)
- `raise E;` in a handler, which loses the original fault address (quick fix `raise;`)
- `Dict[Key]` without `ContainsKey` or `TryGetValue`
- `Copy(S, 0, N)` and `Pos(…) > -1` (strings count from 1)
- Events like `FOnChange(Self)` called without `Assigned` (quick fix adds the check)
- Items of an owning `TObjectList` freed by hand (double free)
- `TStringList.Create;` without assignment (quick fix with variable and `try`/`finally`)
- `Self` passed as an interface while reference counting can already free the object
  - own reference counting in the constructor, `TInterfacedObject` after `inherited AfterConstruction`
  - quick fix moves the call before `inherited`
- Forms and other components stored as an interface (`Bus.Subscribe(FView as IObserver)`) and then freed without unregistering (quick fix inserts the unregistration before `Free`)
- Comparisons with `Null` whose result depends on `NullEqualityRule` (quick fix `Field.IsNull` or `VarIsNull`)
- Memory from `GetMem` or `New` that is never released (quick fix with `try … finally FreeMem`)
- Objects added with `AddObject` to a `TStringList` that does not own them (quick fix `TStringList.Create(True)`)
- The same field or property assigned twice in a row (`Panel.Left` twice instead of `Left`/`Top`)
- Conditions that are always true or false
  - `if (Count > 0) or True`, `if DEBUG_MODE then` with a constant
  - quick fix removes the dead branch
- Loops without an exit (`while True do` without `Break`, `Exit` or `raise`)
- Loop conditions that never change in the body (`while I < List.Count` without `Inc(I)`)
- Recursion without a stop (a routine that calls itself on every path)
- Swapped arguments of Pos, StartsText or ContainsText
- Integer division assigned to a floating-point number
- Strings, dynamic arrays, interfaces and type parameters in the variant part of a record or after `file of` (quick fix moves the field before `case`)
- Interface GUIDs not in the form `{8-4-4-4-12}` (quick fix generates a new one)
- Interfaces and strings assigned through `Pointer(FIntf) := …`, which bypasses reference counting (quick fix `[weak]` or `[unsafe]`)
- Static arrays and records of 2 GB or more, computed from the declarations
- `noreturn` routines (Delphi 13) that can still return normally at the end of the body or through `Exit`
- Hard casts between classes that are neither ancestor nor descendant of each other (`TButton(mEdit)`)
  - silent for the accessor class trick
  - option `allowTypes`
  - quick fix `(mEdit as TButton)`
- `@S[1]` or `PChar(@S[1])` as the address of the characters (range error for an empty string; quick fix `PChar(S)`)
- Loops that run at most once because every path through the body ends with Exit, Break or raise (option `allowFirstElement` for fetching the first element)
- Format strings that do not match their arguments (`Format('%d', [Name])`, too few arguments, `%q`)

### Threads

- VCL access from threads
- Locks without `finally`
- `FreeOnTerminate` traps
- `Synchronize` in the destructor
- `threadvar` with strings
- `Application.ProcessMessages` in loops and event handlers
- `TThread.Queue(nil, …)` in packages (quick fix to your own wrapper)
- `Sleep`/`WaitFor` in forms and event handlers that freeze the user interface
- Loops in `Execute` that never check `Terminated` (quick fix adds it)
- `CreateAnonymousThread` without `Start` (quick fix appends it)
- `TTask.Run` without `try … except` whose exceptions get lost (quick fix wraps the body)
- Variables and collections from outside written in `TParallel.For` or in tasks started in a loop without a lock (quick fix uses `TInterlocked` or a `TMonitor` lock)
- Counters increased with `Inc` in `Execute`, `TTask.Run` or anonymous threads without a lock (quick fix `TInterlocked.Increment`)

### Database

- `while not Q.Eof` loops without `Q.Next` on every path (quick fix inserts it)
- `Edit`/`Append` without `Post` or `Cancel` (quick fix with `try … except Cancel`)
- Transactions without `Rollback` on exceptions
  - FireDAC, IBX, dbExpress, ADO
  - quick fix with `try … except Rollback`
- `UPDATE`/`DELETE` without `WHERE` in code, constants and the form file (option `allowTables` for tables emptied on purpose)
- `SELECT *` (off by default; quick fix inserts the persistent fields of the dataset)

### Compiler ahead

Compiler errors while typing, without a build.

#### Display of compiler findings

- When the next build reports the same error on the same line, Atlas shows a single entry marked “Atlas + dcc” and “confirmed by the compiler (E2035)”
  - setting “Confirmed compiler messages”: merge or show both
- The “Compiler” column of the “Atlas Findings” window names the code.
- Under Rules › Compiler ahead:
  - the master switch turns off every rule of the group
  - “Check level T rules” turns off only those that need expression types
- The compiler code in message, column and hover can be hidden.

#### Method headers, interfaces, units

- Method headers in the implementation that differ from the declaration
  - parameters, `const`/`var`, result type, calling convention
  - like E2037, the quick fix aligns either side
- Interface methods missing in a class
  - like E2291, also with a different header or a resolution clause for an interface not listed
  - quick fix declares and implements them
- Units in `uses` the compiler cannot find in the project, search and library paths
  - also as `.dcu`
  - like F2613, with similar names
  - quick fixes for the namespace prefix or a missing search path in the `.dproj`
- Missing files from `in '…'` (also without a project), packages from `requires` and units that use themselves
- Attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing
  - like W1074, after `{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}` like E1074
  - quick fix adds the unit
- Unit routines whose body differs from the interface header (like E2037)

#### Statements and labels

- Comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`)
- Duplicate `case` labels
  - also through ranges and constants with the same value, and in variant records
  - like E2030, E2027
  - quick fix removes the later value
- `Break` and `Continue` outside a loop, and `Break`, `Continue` and `Exit` that leave a `finally` block (like E2097, E2126; quick fix replaces `Break` with `Exit`)
- `raise;` without an argument outside an `except` block, for example in a local procedure called from the handler (like E2145)
- Misused labels: set twice, never set, not declared, or a `goto` into or out of a `try` block (like E2073, E2074, E2093, E2127)
- Conditions that are not Boolean in if, while and until (like E2012; quick fix adds <> 0, > 0, <> nil or Assigned)
- for-in over types without enumerator (like E2430, E2431)

#### Loop variables

- Loop variables that are assigned in the body, changed with `Inc`/`Dec`, passed as a `var` parameter or are not a simple local variable
  - like E2081, W1015, E1019
  - quick fixes convert to `while` or use `for var`
- Loop variables read after the loop ended normally (like W1037, quick fix converts to `while`)
- `to` loops that never run (`High … to Low`, constant bounds such as `10 to 1`; like H2135, quick fix `downto`)

#### Declarations and class structure

- Fields after methods or properties in the same section, which FPC accepts but Delphi does not
  - like E2169
  - quick fixes move the field up or put `var` in front
- Overloads without `overload` or with identical parameters
  - like E2254, E2267, E2252, E2301
  - quick fix appends `overload;` everywhere
- Identifiers declared twice in the same scope and units listed twice in `uses`
  - like E2004
  - overloaded array properties are allowed, #1383
  - quick fix removes the second one
- `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one
  - like E2137, E2170, E2352, E2353
  - quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`
- `Create` on a class with abstract methods that are not overridden
  - like W1020
  - a class declared `abstract` without abstract methods stays silent as with dcc, #1383
  - the message names the open methods, quick fix overrides them in a class of the file
- `inherited Name(…)` on a method that is abstract in the ancestor
  - a warning: the call raises EAbstractError at runtime, Delphi 13 compiles it without E2373, #1383
  - quick fix removes the call
- `Create` through a class reference (`class of TBase`) whose constructor is not virtual, so the base constructor always runs (like E2391; quick fix adds `virtual` and `override` in descendants)
- Declarations dcc rejects for their form alone (rule `declaration-invalid`: E2006, E2024, E2062, E2128, W1029, #1380):
  - `packed` before a simple type
  - result type `file`
  - virtual constructor in an `object` type
  - property without `read`/`write` in an interface or `automated` section
  - equal constructor parameters with C++ output
- Incomplete types as ancestor, in the interface list or as the record's own field (like E2086)
- `sealed` classes with abstract or unimplemented inherited abstract methods (like E2383, E2539, E2540)
- Two default properties with different names (like E2131)
- Field selectors behind class properties (like E2459)
- Assign without a var parameter of the own type (like E2617)
- Varargs without external on Win32 (like E2277)
- Integer and HRESULT interchanged between an interface method and its implementation (like W1008; quick fix aligns the result type)
- Local (nested) routines assigned or passed to a procedural type (like E2094, E2278; quick fix moves the routine to unit level)

#### Properties

- Getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors
  - like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562
  - quick fix creates a missing `FName`, `GetName` or `SetName`
- Assignments to a field of a record that a property, default property or function only returns as a copy, and to constants
  - like E2064
  - quick fix assigns through a local variable and writes it back
- Assignments to properties without `write` and reads of properties without `read`
  - like E2129, E2130
  - quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter

#### Calls and arguments

- Calls with too many or too few arguments for a routine without overloads (like E2034, E2035; quick fix opens the parameter hint inside the parentheses)
- Calls of overloaded routines and methods that match no overload, such as a float where only `Integer` and `string` are offered (like E2250)
- Calls that are ambiguous because the overloads only differ in parameters with default values (like E2251)
  - checked only when all overloads are known
- Invalid arguments for var and out parameters: constants, properties, function results and expressions
  - like E2197, E2192, E2036
  - `Slice` on var and out open arrays and string elements such as `S[1]` stay silent as with dcc, #1383
  - quick fix passes a local variable
- `@` before an expression (like E2036)
- Invalid default values of parameters
  - several names with one default, a parameter without default after one with default, `var`/`out`, records and large sets
  - like E2237, E2238, E2239, E2268, E2146
  - quick fixes split the names or move the parameters with defaults to the end

#### Generics

- Type arguments that violate the constraint of their type parameter (`class`, `record`, `constructor`, interface or base class)
- `T.Create` without a `constructor` constraint and method calls on values of an unconstrained `T`
  - like E2511–E2515, E2568, E2571
  - quick fix adds the constraint
- Generic declarations Delphi rejects (like E2528, E2552, E2553, E2570, E2574; quick fix removes `type`):
  - now also type parameters on constructors
  - a class next to `class`/`record` or two classes as constraints with classes from other units such as `TStream` (symbol index)
  - local routines in generic methods and methods of generic types
  - `type TList<Integer>`
- Calls of generic methods without type arguments whose type parameter cannot be inferred, because it occurs in no parameter or the arguments are a number and a string (like E2531, E2532; level T)

#### Types

- Unknown type names in declarations, casts and pointer targets, and names that are not a type (like E2003, E2005, E2564; quick fix adds the declaring unit to uses)
- `New`, `Dispose` and `SetLength` without a length on dynamic arrays (like E2255, E2256, E2246, E2307, E2308; quick fixes `A := nil` and `SetLength(A, 1)`)
- Operations that need a kind of type the operand surely lacks (`type-kind-required`, #1370):
  - an index, `^`, a dot or `with` on a number, Boolean, character or enumeration (like E2016, E2017, E2018)
  - `^` on classes, records and interfaces (the quick fix removes it before a dot)
  - wrong ancestors of object types, classes and class helpers and record helpers for classes (like E2019, E2021, E2022, E2474)
  - `New`/`Dispose` with constructor or destructor and `TypeOf` on simple types (like E2467, E2019)
  - an instance method called through the class type outside the class and its descendants (like E2076)
  - `Slice` outside an open array argument (like E2193)
  - records in `array of const` (like E2150)
  - classes, records or interfaces in `Write`/`Read` (like E2054, E2055; quick fix `ToString`)
- Dispinterface declarations with an ancestor, without a GUID, with method directives such as `stdcall` or with `read`/`write` on properties (like E2228–E2231; quick fixes remove the ancestor or the directive and insert a GUID)
- Incompatible types in assignment, call, default value and operator (`type-mismatch`, #1369, like E2008, E2009, E2010, E2015, E2033, E2089):
  - `S := 1` with `S: string`, `'a' + 1`, `div` on `Double`, `not` on a string, an `AnsiString` passed to `var S: string`, `Integer(1.5)` or an event with a different parameter list
  - only what is certain is reported (no aliases with `{$IFDEF}`, no overloads, no operator overloading)
  - Delphi 13 reports property accessors and `Dispose`/`New` with a length as E2008, so `property-accessor-invalid` and `dynamic-array-misuse` now report that code as well
- These rules compare types like the compiler (#1324):
  - aliases across units (`TIdPort = Word`, `LongInt = Integer`, `IUnknown = IInterface`)
  - unit qualifiers, comments and directives in the header do not count
  - `type A = type B` stays a distinct type
  - constants apply typecasts such as `Cardinal(-1)`

#### Constants and numbers

- Errors in constant expressions (like E2098, E2099, E2011, E1012, W1012, E2102, E2028, E2572):
  - division by zero
  - overflow (already beyond Int64 when all operands are signed, such as `High(Int64) + 1`)
  - ranges like `array[5..1]`
  - values outside the type (an error like E1012, a warning like W1012 only when the value fits the same width with the other sign)
  - constant indexes outside a static array and case labels outside the type of the case expression
  - too large hex literals
  - sets with more than 256 elements and numbers in `{$RTTI}` visibility sets
- Signed and unsigned operands mixed in comparisons or arithmetic
  - Integer with Cardinal, anything with UInt64
  - like W1023, W1024, W1073
  - quick fix converts the unsigned operand to Int64
- Assignments with possible data loss, off by default
  - Int64 or NativeInt to Integer, configurable pairs such as Double>Single
  - like W1072, W1066, integers without a code because Delphi 13 does not report W1071, #1383
  - quick fixes convert explicitly or widen the target's type
- Typed constants that are modified by assignment or as var argument, and 0 instead of nil for pointer constants
  - like W1016, W1017; with {$J-} like E2064, E2197; silent with {$J+} before the declaration, as with dcc, #1328
  - 0 instead of nil: like W1013
  - quick fixes turn the constant into an initialised variable or write nil

#### Strings

- String limits exceeded (quick fixes declare the target as string or split the literal):
  - literals truncated to `string[N]`/ShortString (like W1014)
  - literals over 255 characters before Delphi 12 (like E2056)
  - resourcestrings over 4096 characters (like E2381)
- Conversions between Unicode and ANSI strings (like W1057, W1058, W1059, W1060, W1062, W1050, W1068; silent like dcc after `{$WARN … OFF}`; quick fixes convert explicitly or use `CharInSet`, #1377):
  - implicit to `string` or `AnsiString` in assignments, inline variables and arguments
  - explicit casts after `{$WARN EXPLICIT_STRING_CAST ON}`
  - string constants with characters the ANSI code page lacks
  - `C in ['0'..'9']` with a `Char`
  - `S[1] := 'x'` after `{$WARN IMMUTABLE_STRINGS ON}`

#### Compiler directives

- Conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values
  - like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573
  - quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo
- Compiler directives that dcc rejects or reports itself (like W1054, H1054, E2222, E2224, E2560, E1030, F1026, E1026, E2245; #1379):
  - `{$MESSAGE WARN|HINT}` with its text
  - `{$WEAKPACKAGEUNIT ON}` with `{$DENYPACKAGEUNIT ON}`
  - `{$DESIGNONLY}`/`{$RUNONLY}` in a unit
  - `{$OBJTYPENAME}` on an alias
  - `{$CODEPAGE}` above 65535
  - missing files from `{$I}` and `{$R}` (searched like dcc: next to the unit, search paths, `DCC_IncludePath`, `DCC_ResourcePath`, library)
  - include files that include themselves

#### Language versions, deprecated symbols, unsafe code

- Conditional expressions `X := if C then A else B` in projects that must still compile with Delphi 12 or older (like E2029; quick fix, also for the whole unit, converts to an `if` statement)
- Language features the oldest supported Delphi version of the project does not know yet (if expression, `is not`, `not in`, inline variable, multiline string …; `language-feature`)
  - the yardstick is `minDelphiVersion` in atlas.json, e.g. `"12"` for code that Delphi 12 and 13 must compile
  - code actions and slash commands then do not generate such features
- Symbols and units marked `deprecated`, `experimental`, `platform` or `library` (like W1000–W1007)
  - all four kinds by default as in dcc
  - silent where the `.dproj` (`DCC_SYMBOL_PLATFORM = false` …) or `{$WARN …}` switches the warning off
  - plus the .NET directive `{$UNSAFECODE}` as platform specific (like W1002)
- Unsafe code only where the warning is switched on as in dcc (`{$WARN UNSAFE_CODE ON}`, `DCC_UNSAFE_CAST = true` …; rule `unsafe-code`, #1378):
  - `@` on variables, fields and parameters (like W1047)
  - casts of a `Pointer` to a class (like W1048)

#### OLE Automation (#1373)

- In the deprecated `automated` section (like E2175–E2182, E2096, E2185):
  - fields, constructors, dynamic and message methods
  - calling conventions other than register
  - duplicate dispids
  - property redeclarations and the clauses index, stored, default and nodefault
  - read or write on a field there
  - records, pointers and sets as types there
- Calls through Variant or OleVariant (like E2160, E2281, E2166):
  - records or pointers as arguments
  - unnamed after named arguments

#### Assembler

- Invalid statements in `asm` blocks (`asm-invalid`):
  - a missing operand
  - registers of different size such as `mov al, ebx`
  - `lea` with a number
  - `db` with a local variable
  - `OFFSET a + OFFSET b`
  - numbers beyond 64 bits
  - a string constant too long for the register
  - division by zero

#### Compiler codes and hints

- The messages name the code Delphi 13 reports (#1382, e.g. E2058/E2059, E2123, W1008, W1019, E1030; with `delphiVersion` below 13 the older W1030)
- `TextFile`, `Text` and the old `object` syntax (`New(P, Init)`, `Dispose(P, Done)`, `Fail`) are known to name resolution, so they no longer give a false E2003
- Compiler hints without a rule of their own (`compiler-hints`, #1381):
  - published in a class compiled without RTTI (like W1055; silent with `{$M+}` or an ancestor with RTTI such as `TPersistent`)
  - `Initialize`/`Finalize` on an `Integer`, `Double` or similar type (like H2243) or on a `PString` instead of `P^` (like H2244)
- `inline-not-expanded`:
  - now also reports H2445 for inline functions whose body uses nothing from other units
  - no longer reports `TList<T>.Add` and similar for System.TypInfo (aliases of System declarations) or cycles for bodies with only built-in types and intrinsics

### Exceptions

- Empty `except` blocks
- Catch-all without re-raise
- Exceptions created but not raised
- Empty `finally` blocks
- Constructors that enter `try` before `inherited Create` (quick fix moves the call before `try`)

### Components and forms

- Missing `inherited`, `Notification`
- Wrong `default` values
- Fields without a form object and vice versa
- Data bindings and data sources in DFM files
- Message handlers (`message WM_SIZE`) without `inherited`
- IDE notifiers without `RemoveNotifier` (quick fix keeps the index and removes it on unload)
- DUnitX tests without any assert
- `inherited` in the wrong place
  - before freeing own fields in the destructor, after using inherited properties in the constructor
  - quick fix moves it
- `inherited Laden` in the overridden `Speichern` (quick fix uses the own name, option `allowed`)
- Getters that change the state of their object (`Inc(FAbrufe)` in `GetWert`, lazy initialization allowed)
- `Equals` overridden without `GetHashCode` (quick fix with `THashBobJenkins`)
- Records with `class operator Equal` as dictionary keys without a comparer
- Form units without `{$R *.dfm}` (quick fix inserts it) and `{$R}` on a missing form file
- Forms created by `Application.CreateForm` and again by hand (quick fix removes the line from the `.dpr`)
- Handlers in inherited forms that no longer call the ancestor's handler (quick fix inserts `inherited;`)
- Forms that free themselves in their own event handler (quick fix uses `Release` or `Action := caFree`)
- References in the form file to components of another form or data module whose unit is not in the uses clause (`Connection = Form1.Connection`; quick fix adds the unit)

### Runtime environment

- Dialogs (`ShowMessage`, `MessageDlg`, `InputBox`) in console programs, Windows services and DLLs without forms
- `LoadFromFile`/`SaveToFile` and `TFile.ReadAllText` without an encoding (quick fix `TEncoding.UTF8`)
- Writes to `HKEY_LOCAL_MACHINE` (quick fix `HKEY_CURRENT_USER`)
- Elapsed time measured with `Now` (quick fix `TStopwatch`)

### Files and system

- Paths joined without a delimiter (`TPath.GetDocumentsPath + 'export.csv'`, quick fix `TPath.Combine`)
- Hard-coded drive, user and network paths (option `allowUnits`)
- File names compared with `=` instead of `SameFileName` (silent for platform-dependent comparisons with `SameText` and in test units)
- DLL exports without a calling convention or with strings, dynamic arrays, objects or interfaces without GUID (quick fix `stdcall`, option `allowShareMem`)

### Security

- SQL and command injection
- Path traversal
- Weak cryptography
- Disabled TLS verification
- Insecure HTTP and random
- Trojan Source (bidi control, invisible and confusable characters)
- Control characters and invalid UTF-8 bytes
  - like dcc, Atlas reads a file without a BOM as UTF-8 only if the whole file is valid UTF-8
  - a stray valid UTF-8 pair in an ANSI file does not turn its umlauts into errors
  - `control-char` ignores U+FFFD in comments and reports it in strings only as a hint (#1327)

### Architecture and style

- Forbidden uses, role-based import rules
- Compiler warnings, hints, range or overflow checks switched off up to the end of the unit (option `allow`)
- `with`
- Redundant parentheses and `begin … end`
- Conditions and loops without `begin … end` (quick fix for the statement, the method or the file; silences the redundant `begin … end` rule)
- File header
- Hard-coded strings
- Metric limits (also members per class, lines per unit, units in uses)
- Public fields (optional, quick fix encapsulates them)
- Global variables in the interface (optional)
- Local names that shadow a field or property
  - members inherited from VCL or RTL only where they could be meant, e.g. a `Left` that is only assigned
  - the quick fix uses the project prefixes
- Names without the prefix of the naming convention
  - optional: locals `m`, non-public fields `F`, parameters `A`, constants `c`
  - prefixes from `atlas.json` or `naming` in `.atlas`
  - the quick fix renames declaration and uses, silent for interface implementations
- `if` that only assigns `True` or `False`
- `UpperCase(A) = UpperCase(B)` instead of `SameText`
- Numbers without a name
- Too long lines (optional; over 1023 characters always a warning, over 4095 an error like F2069, #1383)
- Commented-out code (quick fix removes it)
- Money amounts as `Double` instead of `Currency` (optional)
- Long `if` chains over the same string (optional, quick fix `case IndexStr`)
- Public and published methods, constants and properties that no project of the project group uses
  - project-wide via the symbol index
  - silent for packages and libraries, while the index is loading and for RTTI, interfaces and form bindings
- Non-generic `TList`/`TObjectList` read with casts instead of `TList<T>` (optional; the quick fix converts the list to `TList<T>`)
- Likewise `TStack`/`TQueue`/`TObjectStack`/`TObjectQueue` from Contnrs
  - optional
  - the quick fix converts to `TStack<T>` etc., queues with `Enqueue`/`Dequeue`, object stacks with `Create(False)` so ownership stays the same
- Forbidden symbols from `atlas.json` (`forbidden-symbol`, opt-in)
  - routines, types, constants, fields, properties, enum values or identifiers
  - with message, replacement as quick fix, severity and units per entry
  - matched through name resolution (an own method `Writeln` stays silent)
  - edited as a table on the Check rules page
- Redundant type casts such as `TStringList(FLines)` of the same type or `TObject(FStream).Free` (quick fix removes the cast)
- Overriding methods that only call `inherited` (quick fix removes declaration and body)
- A bare `inherited;` in a new method that no ancestor declares (forgotten `override`?, quick fix removes the call)
- A bare `Exit;` at the end of a routine and a bare `Continue;` at the end of a loop body (quick fix removes it; silent in `try` blocks and with conditional directives)
- Long `if … else if` chains comparing the same expression with constants (optional, option `min`; the quick fix converts to `case`)

### Dead code and cycles (#64)

- Circular unit references with the full round trip (`uses-cycle`; pure interface cycles as an error like F2047)
- Routines, constants, variables and types only in the implementation section that are never used (`unused-declaration`)
- Units that only the program names in its uses (`unused-unit`)
- Unused private and public members including public types and global variables
- Keep deliberately unused code with:
  - `deadCode.keepAttributes` (e.g. `[Schnittstelle]`)
  - `deadCode.keepPatterns` (e.g. `Test*`)

### Performance

- `SetLength(A, Length(A) + 1)` in loops (with a known count the quick fix sets the length before the loop)
- String, interface, array and record parameters without `const` that the routine never changes (optional; quick fix adds `const` in declaration and implementation)

## Control and integration

- **Confidence** (high, medium, low) per finding caps the severity
- **Profiles** `standard`, `fast`, `strict`, `security`, `style` or your own in `atlas.json`
- **Inheritance across units (#1326):** the rules
  - see ancestor overloads and properties in other units too
  - tell generic and plain types of the same name apart (`TFoo` and `TFoo<T>`)
  - take type and accessors of a property redeclared without a type from the ancestor
  - read procedure types over several lines (`of object`, `reference to`) completely
  - `Edit` without `Post` is only reported for datasets
- **Suppress** with `// lsp-ignore: rule`, with reports of unused or misspelled suppressions
- **Baseline** for legacy projects: hide known findings, report only new ones
- **Compiler check after saving** and the messages of the "Build" tab
- **Check search paths and defines** of the active project (card on the Atlas welcome page)
- **Linter without the IDE:**
  - `AtlasServer.exe --check` for pre-commit hooks and CI
  - as text, JSON or SARIF for GitHub code scanning
  - optionally only changed files or lines (see [Linter mode](Command-line.md#linter-mode))
  - `--format-check` and `--format-write` check or apply the formatting rules

Every rule with description and before/after example: [docs/Regeln.md](../../../docs/Regeln.md).
