unit Atlas.Common.Lsp.KeywordReference;

// Hover über Schlüsselwörtern und Direktiven (#187): Kurztext und DocWiki-Link
// für seltene Sprachelemente wie absolute, reintroduce, strict private,
// class var, message, implements, stored, default, dispid, inline, overload.
// Ergänzt die Tabelle der Compiler-Direktiven (#102) und nutzt deren
// Linkschema (TCompilerDirectives.Url, Release-Name je Delphi-Version, #27).
//
// Zweiwortige Elemente (strict private, class var, is not, not in) werden
// über die Nachbartoken erkannt. Elemente ab Delphi 13 (Bedingungsausdruck
// if … then … else, is not, not in) tragen die Mindestversion; in Projekten
// mit älterer Version nennt der Hover, dass das Element dort fehlt.
// Alltägliche Wörter wie begin, if oder var stehen auf CommonWords und
// bekommen keinen Hover.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  TKeywordInfo = record
    /// <summary>Schlüsselwort in Kleinbuchstaben, zweiwortig mit Leerzeichen ("strict private").</summary>
    Name: string;
    /// <summary>Art für die Überschrift, z. B. "Direktive" oder "reserviertes Wort".</summary>
    Kind: string;
    /// <summary>Kurztext auf Deutsch.</summary>
    Text: string;
    /// <summary>Seite in der DocWiki, ggf. mit Anker.</summary>
    Topic: string;
    /// <summary>Mindestversion als BDS-Nummer ("37.0" = Delphi 13), '' = schon immer.</summary>
    MinVersion: string;
  end;

  TKeywordReference = class
  public const
    /// <summary>Wörter, die so alltäglich sind, dass ein Hover nur stört.</summary>
    cCommonWords: array[0..43] of string = (
      'and', 'array', 'as', 'begin', 'case', 'class', 'const', 'div', 'do', 'downto', 'else', 'end',
      'except', 'finally', 'for', 'function', 'if', 'implementation', 'in', 'interface', 'is', 'mod',
      'nil', 'not', 'of', 'or', 'procedure', 'program', 'raise', 'record', 'repeat', 'set', 'string',
      'then', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'xor', 'private');
  public
    /// <summary>Alle Einträge der Tabelle.</summary>
    class function All: TArray<TKeywordInfo>; static;
    /// <summary>Eintrag zu AName (ohne Groß-/Kleinschreibung).</summary>
    class function Find(const AName: string; out AInfo: TKeywordInfo): Boolean; static;
    /// <summary>Markdown für AInfo mit Link für ADelphiVersion und ggf. Versionshinweis.</summary>
    class function Describe(const AInfo: TKeywordInfo; const ADelphiVersion: string): string; static;
    /// <summary>Hover über dem Schlüsselwort an APosition; False, wenn dort keines aus der Tabelle steht.</summary>
    class function HoverAt(const AText: string; const APosition: TTextPosition; const ADelphiVersion: string;
      out AMarkdown: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TKeywordReferenceText = (DeliberatelyHidesAVirtualMethod, AllowsSeveralRoutinesOfThe, OverridesAVirtualOrDynamic,
    MethodCanBeOverriddenIn, LikeVirtualButMoreCompact, MethodWithoutImplementationDescendantsMust,
    MethodMustNotBeOverridden, ClassMethodWithoutSelfNot, MessageHandlerTheMethodIs, AsksTheCompilerToInsert,
    ForwardDeclarationOfARoutine, RoutineFromADLLOr, RoutineInAssemblerObsoleteOnly, VariableParameterListForExternal,
    RoutineDoesNotReturnE, TheDLLIsLoadedOnly, CallingConventionOfCParameters, CallingConventionOfTheWindows,
    CallingConventionForCOMExceptions, OlderCallingConventionParametersFrom, CallingConventionOfThePlatform,
    NumberOfAMemberIn, UseProducesAWarningOptionally, OnlyAvailableOnCertainPlatforms, NotStableYetUseProduces,
    VisibleOnlyInsideTheClass, VisibleOnlyInTheClass, VisibleInTheClassIts, VisibleEverywhere,
    VisibleEverywhereWithRTTIFor, ObsoleteLikePublicWithAutomation, ClassFieldOneValueFor, TheClassMustNotBe,
    ClassHelperOrRecordHelper, DispatchInterfaceForAutomationCall, StoreFieldsWithoutAlignmentGaps,
    PropertyWithReadAndWrite, DelegatesTheImplementationOfAn, WhetherTheValueOfThe, DefaultValueOfAProperty,
    RemovesAnInheritedDefaultValue, IndexThatSeveralPropertiesPass, VariableLiesAtTheSame, GlobalVariableWithItsOwn,
    TranslatableStringThatIsStored, OutputParameterTheInputValue, MakesTheMembersOfAn, JumpToALabel,
    DeclaresLabelsForGoto, CallsTheMethodOfThe, BlockWithInlineAssembler, RoutinesThatADLLOffers, FileTypeFileOfFor,
    CodeThatRunsWhenThe, CodeThatRunsWhenThe2, MethodThatCreatesAndInitializes, MethodThatFreesAnInstance,
    ShiftBitsToTheLeft, ShiftBitsToTheRight, OverloadedOperatorOfARecord, NotAvailableInThisProject,
    DefaultCallingConventionOfDelphi, HeaderOfADLLProject, DispatchPropertyReadOnly, DispatchPropertyWriteOnly,
    Visibility, ObsoleteObjectTypeTurboPascal, Expression, ConditionalExpressionXIfA, NegatedTypeTestXIs,
    NegatedSetTestXNot, Directive, ReservedWord);

const
  cTexts: array[TKeywordReferenceText] of TAtlasText = (
    (De: 'Verdeckt eine virtuelle Methode des Vorfahren bewusst, ohne sie zu überschreiben; unterdrückt die Warnung ' +
      'W1010.';
     En: 'Deliberately hides a virtual method of the ancestor without overriding it; suppresses the warning W1010.'),
    (De: 'Erlaubt mehrere Routinen gleichen Namens mit unterschiedlichen Parametern.';
     En: 'Allows several routines of the same name with different parameters.'),
    (De: 'Überschreibt eine virtuelle oder dynamische Methode des Vorfahren.';
     En: 'Overrides a virtual or dynamic method of the ancestor.'),
    (De: 'Methode kann in Nachfahren überschrieben werden (Aufruf über die VMT).';
     En: 'Method can be overridden in descendants (call via the VMT).'),
    (De: 'Wie virtual, aber platzsparender und langsamer (Aufruf über die DMT).';
     En: 'Like virtual, but more compact and slower (call via the DMT).'),
    (De: 'Methode ohne Implementierung; Nachfahren müssen sie überschreiben.';
     En: 'Method without implementation; descendants must override it.'),
    (De: 'Methode darf nicht weiter überschrieben, Klasse nicht abgeleitet werden.';
     En: 'Method must not be overridden further, class must not be derived.'),
    (De: 'Klassenmethode ohne Self; nicht virtuell.'; En: 'Class method without Self; not virtual.'),
    (De: 'Message-Handler: Methode wird für die angegebene Windows-Nachricht aufgerufen.';
     En: 'Message handler: the method is called for the given Windows message.'),
    (De: 'Bittet den Compiler, die Routine an der Aufrufstelle einzusetzen.';
     En: 'Asks the compiler to insert the routine at the call site.'),
    (De: 'Vorwärtsdeklaration einer Routine, deren Rumpf später folgt.';
     En: 'Forward declaration of a routine whose body follows later.'),
    (De: 'Routine aus einer DLL oder Objektdatei.'; En: 'Routine from a DLL or object file.'),
    (De: 'Routine in Assembler (veraltet, nur zur Kompatibilität).';
     En: 'Routine in assembler (obsolete, only for compatibility).'),
    (De: 'Variable Parameterliste für externe C-Routinen.'; En: 'Variable parameter list for external C routines.'),
    (De: 'Routine kehrt nicht zurück (z. B. nach raise).'; En: 'Routine does not return (e.g. after raise).'),
    (De: 'DLL wird erst beim ersten Aufruf geladen.'; En: 'The DLL is loaded only at the first call.'),
    (De: 'Aufrufkonvention von C: Parameter von rechts nach links, Aufrufer räumt den Stack.';
     En: 'Calling convention of C: parameters from right to left, the caller cleans up the stack.'),
    (De: 'Aufrufkonvention der Windows-API.'; En: 'Calling convention of the Windows API.'),
    (De: 'Aufrufkonvention für COM: Ausnahmen werden zu HResult.';
     En: 'Calling convention for COM: exceptions become HResult.'),
    (De: 'Ältere Aufrufkonvention: Parameter von links nach rechts.';
     En: 'Older calling convention: parameters from left to right.'),
    (De: 'Aufrufkonvention der Plattform-API (stdcall unter Windows).';
     En: 'Calling convention of the platform API (stdcall on Windows).'),
    (De: 'Nummer eines Mitglieds in einer Dispatch-Schnittstelle (Automation).';
     En: 'Number of a member in a dispatch interface (Automation).'),
    (De: 'Verwendung erzeugt eine Warnung; optional mit Hinweistext.';
     En: 'Use produces a warning; optionally with a hint text.'),
    (De: 'Nur auf bestimmten Plattformen verfügbar; Verwendung erzeugt eine Warnung.';
     En: 'Only available on certain platforms; use produces a warning.'),
    (De: 'Noch nicht stabil; Verwendung erzeugt eine Warnung.'; En: 'Not stable yet; use produces a warning.'),
    (De: 'Nur innerhalb der Klasse sichtbar, auch nicht für andere Klassen derselben Unit.';
     En: 'Visible only inside the class, not even for other classes of the same unit.'),
    (De: 'Nur in der Klasse und ihren Nachfahren sichtbar, nicht für andere Klassen derselben Unit.';
     En: 'Visible only in the class and its descendants, not for other classes of the same unit.'),
    (De: 'Sichtbar in der Klasse, ihren Nachfahren und der eigenen Unit.';
     En: 'Visible in the class, its descendants and its own unit.'),
    (De: 'Überall sichtbar.'; En: 'Visible everywhere.'),
    (De: 'Überall sichtbar, mit RTTI für den Objektinspektor und das Streaming (.dfm).';
     En: 'Visible everywhere, with RTTI for the Object Inspector and streaming (.dfm).'),
    (De: 'Veraltet: wie public, mit Automation-Typinformationen.';
     En: 'Obsolete: like public, with Automation type information.'),
    (De: 'Klassenfeld: ein Wert für alle Instanzen der Klasse.';
     En: 'Class field: one value for all instances of the class.'),
    (De: 'Von der Klasse darf nicht abgeleitet werden.'; En: 'The class must not be derived from.'),
    (De: 'Class Helper bzw. Record Helper: erweitert einen Typ um Methoden.';
     En: 'Class helper or record helper: extends a type with methods.'),
    (De: 'Dispatch-Schnittstelle für Automation (Aufruf über IDispatch).';
     En: 'Dispatch interface for Automation (call via IDispatch).'),
    (De: 'Felder ohne Ausrichtungslücken ablegen.'; En: 'Store fields without alignment gaps.'),
    (De: 'Eigenschaft mit Lese- und Schreibzugriff über Felder oder Methoden.';
     En: 'Property with read and write access via fields or methods.'),
    (De: 'Delegiert die Implementierung einer Schnittstelle an eine Property.';
     En: 'Delegates the implementation of an interface to a property.'),
    (De: 'Ob der Wert der Property in der .dfm gespeichert wird (Boolean oder Funktion).';
     En: 'Whether the value of the property is stored in the .dfm (Boolean or function).'),
    (De: 'Standardwert einer Property (wird dann nicht gespeichert) bzw. Standard-Array-Property.';
     En: 'Default value of a property (then not stored) or default array property.'),
    (De: 'Hebt einen geerbten Standardwert einer Property auf.';
     En: 'Removes an inherited default value of a property.'),
    (De: 'Index, den mehrere Properties an dieselbe Zugriffsmethode übergeben.';
     En: 'Index that several properties pass to the same accessor.'),
    (De: 'Variable liegt an derselben Adresse wie eine andere Variable.';
     En: 'Variable lies at the same address as another variable.'),
    (De: 'Globale Variable mit eigenem Wert je Thread.'; En: 'Global variable with its own value per thread.'),
    (De: 'Übersetzbarer String, der als Ressource abgelegt wird.';
     En: 'Translatable string that is stored as a resource.'),
    (De: 'Ausgabeparameter: Der Eingangswert wird verworfen.'; En: 'Output parameter: the input value is discarded.'),
    (De: 'Macht die Mitglieder eines Objekts ohne Präfix zugänglich; erschwert das Lesen.';
     En: 'Makes the members of an object accessible without prefix; makes reading harder.'),
    (De: 'Sprung zu einer Marke (label).'; En: 'Jump to a label.'),
    (De: 'Deklariert Sprungmarken für goto.'; En: 'Declares labels for goto.'),
    (De: 'Ruft die gleichnamige Methode des Vorfahren auf.';
     En: 'Calls the method of the same name of the ancestor.'),
    (De: 'Block mit Inline-Assembler.'; En: 'Block with inline assembler.'),
    (De: 'Routinen, die eine DLL nach außen anbietet.'; En: 'Routines that a DLL offers to the outside.'),
    (De: 'Dateityp (file of …) für typisierte und untypisierte Dateien.';
     En: 'File type (file of …) for typed and untyped files.'),
    (De: 'Code, der beim Laden der Unit ausgeführt wird.'; En: 'Code that runs when the unit is loaded.'),
    (De: 'Code, der beim Entladen der Unit ausgeführt wird.'; En: 'Code that runs when the unit is unloaded.'),
    (De: 'Methode, die eine Instanz anlegt und initialisiert.';
     En: 'Method that creates and initializes an instance.'),
    (De: 'Methode, die eine Instanz freigibt; Destroy wird über Free aufgerufen.';
     En: 'Method that frees an instance; Destroy is called via Free.'),
    (De: 'Bits nach links schieben.'; En: 'Shift bits to the left.'),
    (De: 'Bits nach rechts schieben.'; En: 'Shift bits to the right.'),
    (De: 'Überladener Operator eines Records (class operator).';
     En: 'Overloaded operator of a record (class operator).'),
    (De: ' In diesem Projekt (BDS %s) nicht verfügbar.'; En: ' Not available in this project (BDS %s).'),
    (De: 'Standard-Aufrufkonvention von Delphi (Parameter in Registern).';
     En: 'Default calling convention of Delphi (parameters in registers).'),
    (De: 'Kopf eines DLL-Projekts; als Hinweisdirektive: nur in dieser Bibliothek.';
     En: 'Header of a DLL project; as hint directive: only in this library.'),
    (De: 'Dispatch-Property nur lesbar.'; En: 'Dispatch property read-only.'),
    (De: 'Dispatch-Property nur schreibbar.'; En: 'Dispatch property write-only.'),
    (De: 'Sichtbarkeit'; En: 'visibility'),
    (De: 'Veralteter Objekttyp (Turbo Pascal); heute class bzw. record verwenden.';
     En: 'Obsolete object type (Turbo Pascal); use class or record today.'),
    (De: 'Ausdruck'; En: 'expression'),
    (De: 'Bedingungsausdruck: X := if A then B else C.'; En: 'Conditional expression: X := if A then B else C.'),
    (De: 'Negierter Typtest: X is not TFoo.'; En: 'Negated type test: X is not TFoo.'),
    (De: 'Negierter Mengentest: X not in [A, B].'; En: 'Negated set test: X not in [A, B].'),
    (De: 'Direktive'; En: 'directive'),
    (De: 'reserviertes Wort'; En: 'reserved word'));

{$SCOPEDENUMS OFF}

const
  cDelphi13 = '37.0';
  cMethods = 'Methods_(Delphi)';
  cProperties = 'Properties_(Delphi)';
  cClasses = 'Classes_and_Objects_(Delphi)';
  cRoutines = 'Procedures_and_Functions_(Delphi)';
  cHints = 'Declarations_and_Statements_(Delphi)#Hinting_Directives';
  cExpressions = 'Expressions_(Delphi)';

function K(const AName, AKind, AText, ATopic, AMinVersion: string): TKeywordInfo; overload;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Topic := ATopic;
  Result.MinVersion := AMinVersion;
end;

// Wie oben ohne Mindestversion (AMinVersion = '').
function K(const AName, AKind, AText, ATopic: string): TKeywordInfo; overload;
begin
  Result := K(AName, AKind, AText, ATopic, '');
end;

var
  /// <summary>Je Sprache einmal beim Laden aufgebaut, damit Anfragen in mehreren Threads nur lesen.</summary>
  Keywords: array[TTextLanguage] of TArray<TKeywordInfo>;


/// <summary>Methodendirektiven.</summary>
function MethodKeywords(ALanguage: TTextLanguage): TArray<TKeywordInfo>;
begin
  Result := [
    K('reintroduce', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DeliberatelyHidesAVirtualMethod].TextIn(ALanguage), cMethods),
    K('overload', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.AllowsSeveralRoutinesOfThe].TextIn(ALanguage),
      cRoutines + '#Overloading_Procedures_and_Functions'),
    K('override', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.OverridesAVirtualOrDynamic].TextIn(ALanguage), cMethods),
    K('virtual', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MethodCanBeOverriddenIn].TextIn(ALanguage), cMethods),
    K('dynamic', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.LikeVirtualButMoreCompact].TextIn(ALanguage), cMethods),
    K('abstract', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MethodWithoutImplementationDescendantsMust].TextIn(ALanguage), cMethods),
    K('final', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MethodMustNotBeOverridden].TextIn(ALanguage), cMethods),
    K('static', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ClassMethodWithoutSelfNot].TextIn(ALanguage), cMethods),
    K('message', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MessageHandlerTheMethodIs].TextIn(ALanguage),
      cMethods + '#Message_Methods')];
end;

/// <summary>Routinen und Aufrufkonventionen.</summary>
function RoutineKeywords(ALanguage: TTextLanguage): TArray<TKeywordInfo>;
begin
  Result := [
    K('inline', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.AsksTheCompilerToInsert].TextIn(ALanguage),
      'Calling_Procedures_and_Functions_(Delphi)#Using_the_inline_Directive'),
    K('forward', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ForwardDeclarationOfARoutine].TextIn(ALanguage),
      cRoutines + '#Forward_and_Interface_Declarations'),
    K('external', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.RoutineFromADLLOr].TextIn(ALanguage),
      cRoutines + '#External_Declarations'),
    K('assembler', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.RoutineInAssemblerObsoleteOnly].TextIn(ALanguage),
      'Inline_Assembly_Code'),
    K('varargs', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VariableParameterListForExternal].TextIn(ALanguage), cRoutines + '#Varargs'),
    K('noreturn', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.RoutineDoesNotReturnE].TextIn(ALanguage), cRoutines),
    K('delayed', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.TheDLLIsLoadedOnly].TextIn(ALanguage),
      'Libraries_and_Packages_(Delphi)'),
    K('cdecl', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CallingConventionOfCParameters].TextIn(ALanguage),
      cRoutines + '#Calling_Conventions'),
    K('stdcall', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CallingConventionOfTheWindows].TextIn(ALanguage), cRoutines +
      '#Calling_Conventions'),
    K('safecall', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CallingConventionForCOMExceptions].TextIn(ALanguage),
      cRoutines + '#Calling_Conventions'),
    K('register', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DefaultCallingConventionOfDelphi].TextIn(ALanguage),
      cRoutines + '#Calling_Conventions'),
    K('pascal', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.OlderCallingConventionParametersFrom].TextIn(ALanguage),
      cRoutines + '#Calling_Conventions'),
    K('winapi', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CallingConventionOfThePlatform].TextIn(ALanguage),
      cRoutines + '#Calling_Conventions'),
    K('dispid', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.NumberOfAMemberIn].TextIn(ALanguage),
      'Automation_Objects_(Delphi)')];
end;

/// <summary>Hinweisdirektiven, Sichtbarkeit und Klassen.</summary>
function ClassKeywords(ALanguage: TTextLanguage): TArray<TKeywordInfo>;
begin
  Result := [
    K('deprecated', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.UseProducesAWarningOptionally].TextIn(ALanguage), cHints),
    K('platform', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.OnlyAvailableOnCertainPlatforms].TextIn(ALanguage), cHints),
    K('experimental', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.NotStableYetUseProduces].TextIn(ALanguage), cHints),
    K('library', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.HeaderOfADLLProject].TextIn(ALanguage), cHints),
    // Sichtbarkeit und Klassen
    K('strict private', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VisibleOnlyInsideTheClass].TextIn(ALanguage), cClasses +
      '#Strict_Visibility_Specifiers'),
    K('strict protected', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VisibleOnlyInTheClass].TextIn(ALanguage), cClasses +
      '#Strict_Visibility_Specifiers'),
    K('protected', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VisibleInTheClassIts].TextIn(ALanguage), cClasses),
    K('public', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VisibleEverywhere].TextIn(ALanguage),
      cClasses),
    K('published', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VisibleEverywhereWithRTTIFor].TextIn(ALanguage),
      cClasses + '#Published_Members'),
    K('automated', cTexts[TKeywordReferenceText.Visibility].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ObsoleteLikePublicWithAutomation].TextIn(ALanguage), cClasses),
    K('class var', 'Deklaration', cTexts[TKeywordReferenceText.ClassFieldOneValueFor].TextIn(ALanguage),
      'Fields_(Delphi)#Class_Fields'),
    K('sealed', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.TheClassMustNotBe].TextIn(ALanguage),
      cClasses),
    K('helper', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ClassHelperOrRecordHelper].TextIn(ALanguage),
      'Class_and_Record_Helpers_(Delphi)'),
    K('dispinterface', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DispatchInterfaceForAutomationCall].TextIn(ALanguage),
      'Automation_Objects_(Delphi)#Dispatch_Interface_Types'),
    K('object', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ObsoleteObjectTypeTurboPascal].TextIn(ALanguage),
      'Classes_and_Objects_(Delphi)#Object_Types'),
    K('packed', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.StoreFieldsWithoutAlignmentGaps].TextIn(ALanguage),
      'Structured_Types_(Delphi)#Alignment_of_Structured_Types')];
end;

/// <summary>Properties.</summary>
function PropertyKeywords(ALanguage: TTextLanguage): TArray<TKeywordInfo>;
begin
  Result := [
    K('property', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.PropertyWithReadAndWrite].TextIn(ALanguage), cProperties),
    K('implements', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DelegatesTheImplementationOfAn].TextIn(ALanguage),
      'Using_Implements_for_Delegation'),
    K('stored', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.WhetherTheValueOfThe].TextIn(ALanguage),
      cProperties + '#Storage_Specifiers'),
    K('default', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DefaultValueOfAProperty].TextIn(ALanguage),
      cProperties + '#Storage_Specifiers'),
    K('nodefault', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.RemovesAnInheritedDefaultValue].TextIn(ALanguage),
      cProperties + '#Storage_Specifiers'),
    K('index', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.IndexThatSeveralPropertiesPass].TextIn(ALanguage),
      cProperties + '#Index_Specifiers'),
    K('readonly', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DispatchPropertyReadOnly].TextIn(ALanguage),
      'Automation_Objects_(Delphi)'),
    K('writeonly', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DispatchPropertyWriteOnly].TextIn(ALanguage),
      'Automation_Objects_(Delphi)')];
end;

/// <summary>Variablen, Anweisungen und Delphi 13.</summary>
function StatementKeywords(ALanguage: TTextLanguage): TArray<TKeywordInfo>;
begin
  Result := [
    K('absolute', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.VariableLiesAtTheSame].TextIn(ALanguage),
      'Variables_(Delphi)#Absolute_Addresses'),
    K('threadvar', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.GlobalVariableWithItsOwn].TextIn(ALanguage),
      'Variables_(Delphi)#Thread-local_Variables'),
    K('resourcestring', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.TranslatableStringThatIsStored].TextIn(ALanguage),
      'Resource_Strings_(Delphi)'),
    K('out', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.OutputParameterTheInputValue].TextIn(ALanguage),
      'Parameters_(Delphi)#Out_Parameters'),
    K('with', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MakesTheMembersOfAn].TextIn(ALanguage),
      'Declarations_and_Statements_(Delphi)#With_Statements'),
    K('goto', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.JumpToALabel].TextIn(ALanguage),
      'Declarations_and_Statements_(Delphi)#Goto_Statements'),
    K('label', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.DeclaresLabelsForGoto].TextIn(ALanguage),
      'Declarations_and_Statements_(Delphi)#Goto_Statements'),
    K('inherited', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CallsTheMethodOfThe].TextIn(ALanguage), cMethods + '#Inherited'),
    K('asm', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.BlockWithInlineAssembler].TextIn(ALanguage), 'Inline_Assembly_Code'),
    K('exports', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.RoutinesThatADLLOffers].TextIn(ALanguage),
      'Writing_Dynamically_Loaded_Libraries'),
    K('file', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.FileTypeFileOfFor].TextIn(ALanguage),
      'File_Types_(Delphi)'),
    K('initialization', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CodeThatRunsWhenThe].TextIn(ALanguage),
      'Programs_and_Units_(Delphi)#The_Initialization_Section'),
    K('finalization', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.CodeThatRunsWhenThe2].TextIn(ALanguage),
      'Programs_and_Units_(Delphi)#The_Finalization_Section'),
    K('constructor', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MethodThatCreatesAndInitializes].TextIn(ALanguage), cMethods +
      '#Constructors'),
    K('destructor', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.MethodThatFreesAnInstance].TextIn(ALanguage),
      cMethods + '#Destructors'),
    K('shl', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ShiftBitsToTheLeft].TextIn(ALanguage),
      cExpressions + '#Bitwise_Operators'),
    K('shr', cTexts[TKeywordReferenceText.ReservedWord].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ShiftBitsToTheRight].TextIn(ALanguage),
      cExpressions + '#Bitwise_Operators'),
    K('operator', cTexts[TKeywordReferenceText.Directive].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.OverloadedOperatorOfARecord].TextIn(ALanguage),
      'Operator_Overloading_(Delphi)'),
    // Delphi 13
    K('if expression', cTexts[TKeywordReferenceText.Expression].TextIn(ALanguage),
      cTexts[TKeywordReferenceText.ConditionalExpressionXIfA].TextIn(ALanguage), cExpressions, cDelphi13),
    K('is not', 'Operator', cTexts[TKeywordReferenceText.NegatedTypeTestXIs].TextIn(ALanguage), cExpressions, cDelphi13),
    K('not in', 'Operator', cTexts[TKeywordReferenceText.NegatedSetTestXNot].TextIn(ALanguage), cExpressions, cDelphi13)];
end;

procedure InitKeywords;
var
  mLanguage: TTextLanguage;
begin
  for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
  begin
    Keywords[mLanguage] := MethodKeywords(mLanguage) + RoutineKeywords(mLanguage) + ClassKeywords(mLanguage) +
      PropertyKeywords(mLanguage) + StatementKeywords(mLanguage);
  end;
end;

{ TKeywordReference }

class function TKeywordReference.All: TArray<TKeywordInfo>;
begin
  Result := Keywords[TAtlasLocale.Language];
end;

class function TKeywordReference.Find(const AName: string; out AInfo: TKeywordInfo): Boolean;
var
  mInfo: TKeywordInfo;
begin
  for mInfo in Keywords[TAtlasLocale.Language] do
  begin
    if SameText(mInfo.Name, AName) then
    begin
      AInfo := mInfo;
      Exit(True);
    end;
  end;
  Result := False;
end;

function VersionLabel(const AVersion: string): string;
begin
  if AVersion = cDelphi13 then
  begin
    Result := 'Delphi 13';
  end
  else
  begin
    Result := 'BDS ' + AVersion;
  end;
end;

class function TKeywordReference.Describe(const AInfo: TKeywordInfo; const ADelphiVersion: string): string;
var
  mTitle: string;
begin
  if AInfo.Name = 'if expression' then
  begin
    mTitle := 'if … then … else';
  end
  else
  begin
    mTitle := AInfo.Name;
  end;
  Result := '**' + mTitle + '** (' + AInfo.Kind + ')' + #10#10 + AInfo.Text;
  if AInfo.MinVersion <> '' then
  begin
    Result := Result + #10#10 + 'Ab ' + VersionLabel(AInfo.MinVersion) + '.';
    if (TLanguageFeatures.ParseVersion(ADelphiVersion) > 0) and
      (TLanguageFeatures.ParseVersion(ADelphiVersion) < TLanguageFeatures.ParseVersion(AInfo.MinVersion)) then
    begin
      Result := Result + cTexts[TKeywordReferenceText.NotAvailableInThisProject].Fmt([ADelphiVersion]);
    end;
  end;
  Result := Result + #10#10 + '[DocWiki](' + TCompilerDirectives.Url(ADelphiVersion, AInfo.Topic) + ')';
end;

function Contains(const ATokenStart, ATokenEnd, APosition: TTextPosition): Boolean;
begin
  Result := ((ATokenStart.Line < APosition.Line) or ((ATokenStart.Line = APosition.Line) and
    (ATokenStart.Character <= APosition.Character))) and ((ATokenEnd.Line > APosition.Line) or
    ((ATokenEnd.Line = APosition.Line) and (ATokenEnd.Character >= APosition.Character)));
end;

/// <summary>Nächstes bzw. vorheriges Token ohne Kommentare; -1 ohne.</summary>
function Neighbour(const ATokens: TArray<TPascalToken>; AIndex, AStep: Integer): Integer;
begin
  Result := AIndex + AStep;
  while (Result >= 0) and (Result <= High(ATokens)) and
    (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(Result, AStep);
  end;
  if (Result < 0) or (Result > High(ATokens)) then
  begin
    Result := -1;
  end;
end;

function WordOf(const ATokens: TArray<TPascalToken>; AIndex: Integer): string;
begin
  if (AIndex < 0) or not (ATokens[AIndex].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) then
  begin
    Result := '';
  end
  else
  begin
    Result := LowerCase(ATokens[AIndex].Text);
  end;
end;

/// <summary>Index des Schlüsselworts bzw. Bezeichners an APosition; -1 ohne.</summary>
function WordAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
      Contains(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos, APosition) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

const
  // Zweiwortige Elemente, in dieser Reihenfolge geprüft (is not vor not in).
  cPairFirst: array[0..4] of string = ('strict', 'strict', 'class', 'is', 'not');
  cPairSecond: array[0..4] of string = ('private', 'protected', 'var', 'not', 'in');

/// <summary>Zweiwortiges Element aus AWord und seinem Vorgänger bzw. Nachfolger; '' ohne.</summary>
function PairName(const APrevWord, AWord, ANextWord: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cPairFirst) to High(cPairFirst) do
  begin
    if ((AWord = cPairFirst[mIndex]) and (ANextWord = cPairSecond[mIndex])) or
      ((APrevWord = cPairFirst[mIndex]) and (AWord = cPairSecond[mIndex])) then
    begin
      Exit(cPairFirst[mIndex] + ' ' + cPairSecond[mIndex]);
    end;
  end;
  Result := '';
end;

/// <summary>Name des Eintrags zum Token AHit; '' bei alltäglichen Wörtern.</summary>
function EntryName(const ATokens: TArray<TPascalToken>; AHit: Integer): string;
var
  mWord: string;
  mPrev: Integer;
begin
  mWord := WordOf(ATokens, AHit);
  mPrev := Neighbour(ATokens, AHit, -1);
  Result := PairName(WordOf(ATokens, mPrev), mWord, WordOf(ATokens, Neighbour(ATokens, AHit, 1)));
  if Result <> '' then
  begin
    Exit;
  end;
  // Hinter :=, (, , usw. ist if ein Ausdruck, keine Anweisung.
  if (mWord = 'if') and (mPrev >= 0) and (ATokens[mPrev].Kind = TPascalTokenKind.Symbol) and
    (ATokens[mPrev].Text <> ';') then
  begin
    Result := 'if expression';
  end
  else if not MatchText(mWord, TKeywordReference.cCommonWords) then
  begin
    Result := mWord;
  end;
end;

class function TKeywordReference.HoverAt(const AText: string; const APosition: TTextPosition;
  const ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mHit: Integer;
  mInfo: TKeywordInfo;
begin
  AMarkdown := '';
  mTokens := TPascalLexer.Tokenize(AText);
  mHit := WordAt(mTokens, APosition);
  Result := (mHit >= 0) and Find(EntryName(mTokens, mHit), mInfo);
  if Result then
  begin
    AMarkdown := Describe(mInfo, ADelphiVersion);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.KeywordReference', cTexts);
  InitKeywords;

end.
