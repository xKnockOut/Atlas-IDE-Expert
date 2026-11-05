# Hover over keywords and directives

*Deutsche Fassung: [Schluesselwoerter.md](../Schluesselwoerter.md)*

The hover explains rare language elements with a short text and links the DocWiki matching the Delphi version of the project (#187). The table is maintained in `Atlas.Common.Lsp.KeywordReference`. A test checks that every reserved word of the lexer has an entry or is on the list of everyday words. The short texts in the hover are German so far; they move to the text tables (#1458) with the remaining server texts.

The hover only appears if no symbol of the same name is known at that position.

| Element | Kind | Short text |
|---|---|---|
| `reintroduce` | directive | Deliberately hides a virtual method of the ancestor without overriding it; suppresses warning W1010. |
| `overload` | directive | Allows several routines of the same name with different parameters. |
| `override` | directive | Overrides a virtual or dynamic method of the ancestor. |
| `virtual` | directive | The method can be overridden in descendants (called through the VMT). |
| `dynamic` | directive | Like virtual, but smaller and slower (called through the DMT). |
| `abstract` | directive | Method without implementation; descendants must override it. |
| `final` | directive | The method may not be overridden any further, the class may not be derived from. |
| `static` | directive | Class method without Self; not virtual. |
| `message` | directive | Message handler: the method is called for the given Windows message. |
| `inline` | reserved word | Asks the compiler to insert the routine at the call site. |
| `forward` | directive | Forward declaration of a routine whose body follows later. |
| `external` | directive | Routine from a DLL or object file. |
| `assembler` | directive | Routine in assembler (obsolete, only for compatibility). |
| `varargs` | directive | Variable parameter list for external C routines. |
| `noreturn` | directive | The routine does not return (e.g. after raise). |
| `delayed` | directive | The DLL is only loaded at the first call. |
| `cdecl` | directive | C calling convention: parameters from right to left, the caller cleans up the stack. |
| `stdcall` | directive | Calling convention of the Windows API. |
| `safecall` | directive | Calling convention for COM: exceptions become HResult. |
| `register` | directive | Default calling convention of Delphi (parameters in registers). |
| `pascal` | directive | Older calling convention: parameters from left to right. |
| `winapi` | directive | Calling convention of the platform API (stdcall on Windows). |
| `dispid` | directive | Number of a member in a dispatch interface (automation). |
| `deprecated` | directive | Use produces a warning; optionally with a hint text. |
| `platform` | directive | Only available on certain platforms; use produces a warning. |
| `experimental` | directive | Not stable yet; use produces a warning. |
| `library` | reserved word | Header of a DLL project; as a hint directive: only in this library. |
| `strict private` | visibility | Visible only inside the class, not even to other classes of the same unit. |
| `strict protected` | visibility | Visible only in the class and its descendants, not to other classes of the same unit. |
| `protected` | visibility | Visible in the class, its descendants and its own unit. |
| `public` | visibility | Visible everywhere. |
| `published` | visibility | Visible everywhere, with RTTI for the Object Inspector and streaming (.dfm). |
| `automated` | visibility | Obsolete: like public, with automation type information. |
| `class var` | declaration | Class field: one value for all instances of the class. |
| `sealed` | directive | The class may not be derived from. |
| `helper` | directive | Class helper or record helper: adds methods to a type. |
| `dispinterface` | reserved word | Dispatch interface for automation (called through IDispatch). |
| `object` | reserved word | Obsolete object type (Turbo Pascal); use class or record today. |
| `packed` | reserved word | Store fields without alignment gaps. |
| `property` | reserved word | Property with read and write access through fields or methods. |
| `implements` | directive | Delegates the implementation of an interface to a property. |
| `stored` | directive | Whether the value of the property is stored in the .dfm (Boolean or function). |
| `default` | directive | Default value of a property (then not stored) or default array property. |
| `nodefault` | directive | Cancels an inherited default value of a property. |
| `index` | directive | Index that several properties pass to the same access method. |
| `readonly` | directive | Dispatch property, read only. |
| `writeonly` | directive | Dispatch property, write only. |
| `absolute` | directive | The variable lives at the same address as another variable. |
| `threadvar` | reserved word | Global variable with its own value per thread. |
| `resourcestring` | reserved word | Translatable string stored as a resource. |
| `out` | directive | Output parameter: the incoming value is discarded. |
| `with` | reserved word | Makes the members of an object accessible without a prefix; makes code harder to read. |
| `goto` | reserved word | Jump to a label. |
| `label` | reserved word | Declares jump labels for goto. |
| `inherited` | reserved word | Calls the method of the same name in the ancestor. |
| `asm` | reserved word | Block with inline assembler. |
| `exports` | reserved word | Routines a DLL offers to the outside. |
| `file` | reserved word | File type (file of …) for typed and untyped files. |
| `initialization` | reserved word | Code run when the unit is loaded. |
| `finalization` | reserved word | Code run when the unit is unloaded. |
| `constructor` | reserved word | Method that creates and initialises an instance. |
| `destructor` | reserved word | Method that frees an instance; Destroy is called through Free. |
| `shl` | reserved word | Shift bits to the left. |
| `shr` | reserved word | Shift bits to the right. |
| `operator` | directive | Overloaded operator of a record (class operator). |
| `if … then … else` | expression | Conditional expression: X := if A then B else C. (from Delphi 13) |
| `is not` | operator | Negated type test: X is not TFoo. (from Delphi 13) |
| `not in` | operator | Negated set test: X not in [A, B]. (from Delphi 13) |

No hover, because everyday: `and`, `array`, `as`, `begin`, `case`, `class`, `const`, `div`, `do`, `downto`, `else`, `end`, `except`, `finally`, `for`, `function`, `if`, `implementation`, `in`, `interface`, `is`, `mod`, `nil`, `not`, `of`, `or`, `procedure`, `program`, `raise`, `record`, `repeat`, `set`, `string`, `then`, `to`, `try`, `type`, `unit`, `until`, `uses`, `var`, `while`, `xor`, `private`.
