unit Atlas.Common.Lsp.CompilerDirectives;

// Sprachreferenz für Compiler-Direktiven (#102, Teil 1): Kurztext und
// DocWiki-Link je Direktive und Schalterbuchstaben ({$R+} = RANGECHECKS); die
// Bezeichner für {$WARN} und alle Direktivennamen stehen in Pascal.DirectiveNames
// (#989). Grundlage für Hover und Vervollständigung in Direktiven; #187 soll dieselbe Tabelle für Schlüsselwörter nutzen.
//
// Links folgen dem Schema https://docwiki.embarcadero.com/RADStudio/<Release>/en/<Seite>
// mit dem Release-Namen aus TDocWiki (Delphi 12 = Athens, Delphi 13 = Florence).
// Direktiven und {$WARN}-Bezeichner sind in Delphi 12 und 13 gleich; eine
// Unterscheidung je Version kommt dazu, sobald sie auseinanderlaufen.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TDirectiveInfo = record
    /// <summary>Langer Name, z. B. RANGECHECKS.</summary>
    Name: string;
    /// <summary>Schalterbuchstabe wie R, sonst ''.</summary>
    Letter: string;
    /// <summary>Kurztext auf Deutsch.</summary>
    Text: string;
    /// <summary>Seite in der DocWiki, z. B. Range_checking.</summary>
    Topic: string;
  end;

  TCompilerDirectives = class
  public const
    BaseUri = 'https://docwiki.embarcadero.com/RADStudio/';
    WarningsTopic = 'Warning_messages_(Delphi)';
  public
    /// <summary>Alle Direktiven der Tabelle.</summary>
    class function All: TArray<TDirectiveInfo>; static;
    /// <summary>Bezeichner für {$WARN …}.</summary>
    class function Warnings: TArray<string>; static;
    /// <summary>Direktive zum langen Namen oder Schalterbuchstaben (ohne Groß-/Kleinschreibung).</summary>
    class function Find(const AName: string; out AInfo: TDirectiveInfo): Boolean; static;
    /// <summary>Link auf die DocWiki-Seite ATopic für die Delphi-Version (BDS-Nummer wie "23.0").</summary>
    class function Url(const ADelphiVersion, ATopic: string): string; static;
    /// <summary>Markdown für den Hover über einer Direktive wie "{$R+}" oder "{$WARN SYMBOL_DEPRECATED OFF}";
    /// False für unbekannte Direktiven.</summary>
    class function Describe(const ADirective, ADelphiVersion: string; out AMarkdown: string): Boolean; static;
    /// <summary>Steht ALineBeforeCursor in einer offenen Direktive? Dann die passenden Vorschläge:
    /// Bezeichner nach "{$WARN ", sonst Direktivennamen. AIsWarning sagt, welche.</summary>
    class function CompletionAt(const ALineBeforeCursor: string; out ANames: TArray<string>;
      out AIsWarning: Boolean): Boolean; static;
    /// <summary>Hover über der Direktive an APosition; False, wenn dort keine bekannte steht.</summary>
    class function HoverAt(ATree: TSyntaxTree; const APosition: TTextPosition; const ADelphiVersion: string;
      out AMarkdown: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Lsp.DocWiki,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCompilerDirectivesText = (AlignmentOfFieldsInRecords, KindOfApplicationCONSOLEOr, CompileAssertCallsInOr,
    EvaluateBooleanExpressionsCompletelyInstead, AlignmentOfTheGeneratedCode, UnitMustNotBeIncluded,
    PackageForDesignTimeIn, AlternativeOfAConditionalCompilation, FurtherConditionOfAnIF,
    EndOfAConditionalCompilation, SwitchCompilerHintsOnOr, WriteALineIntoThe, ConditionalCompilationWithAnExpression,
    CompileIfTheConditionalSymbol, EndOfAnIFCondition, CompileIfTheConditionalSymbol2, CompileIfASwitchIs,
    LoadAddressOfADLL, RebuildThePackageAutomaticallyOn, InsertAFileAtThis, CloseIFOnlyWithIFEND, LinkAnObjectFileL,
    InformationAboutLocalSymbolsFor, StringMeansALongString, OutputAnOwnMessageWhile, GenerateExtendedRTTIForMethods,
    MinimumSizeOfEnumerationTypes, OverflowCheckingForIntegerArithmetic, AllowPointerArithmeticForTyped,
    RangeCheckingForArrayIndexes, GenerateSymbolAndCrossReference, LinkAResourceFileR, SetTheScopeOfExtended,
    PackageForRunTimeOnly, AddressEnumerationValuesOnlyWith, LinkAllTypesWithRTTI, SetLineEndingAndIndentation,
    TheOperatorReturnsTypedPointers, GenerateRTTIForPublishedSections, StrictCheckingOfShortStringVar,
    SwitchASingleWarningOn, SwitchCompilerWarningsOnOr, DescriptionTextOfAPackage, EndOfACollapsibleRegion,
    ExtendedSyntaxFunctionCallAs, InterpretCharacterLiterals80FF, AllowAccessToVariablesFrom,
    ReportInputOutputErrorsAs, TreatStringParametersAsOpen, TreatRealAsThe6, StartOfACollapsibleRegion,
    IncludeTheUnitWeaklyIn, StringIndexesStartAt0, DefineAConditionalSymbol, OptimizeCode,
    PentiumSafeFloatingPointDivision, AlwaysGenerateStackFrames, UndefineAConditionalSymbol,
    MakeTypedConstantsWriteable, Here, SwitchedOn, SwitchedOff, Warning, GenerateDebugInformation);

const
  cTexts: array[TCompilerDirectivesText] of TAtlasText = (
    (De: 'Ausrichtung der Felder in Records und Klassen (1, 2, 4, 8, 16 oder ON/OFF).';
     En: 'Alignment of fields in records and classes (1, 2, 4, 8, 16 or ON/OFF).'),
    (De: 'Art der Anwendung: CONSOLE oder GUI.'; En: 'Kind of application: CONSOLE or GUI.'),
    (De: 'Assert-Aufrufe einkompilieren (+) oder weglassen (-).';
     En: 'Compile Assert calls in (+) or leave them out (-).'),
    (De: 'Boolesche Ausdrücke vollständig auswerten (+) statt Kurzschlussauswertung (-).';
     En: 'Evaluate Boolean expressions completely (+) instead of short-circuit evaluation (-).'),
    (De: 'Ausrichtung des erzeugten Codes in Byte.'; En: 'Alignment of the generated code in bytes.'),
    (De: 'Unit darf nicht in ein Package aufgenommen werden.'; En: 'Unit must not be included in a package.'),
    (De: 'Package nur für die Entwurfszeit in der IDE.'; En: 'Package for design time in the IDE only.'),
    (De: 'Alternative einer bedingten Kompilierung.'; En: 'Alternative of a conditional compilation.'),
    (De: 'Weitere Bedingung einer {$IF}-Kette.'; En: 'Further condition of an {$IF} chain.'),
    (De: 'Ende einer bedingten Kompilierung.'; En: 'End of a conditional compilation.'),
    (De: 'Hinweise des Compilers ein- oder ausschalten.'; En: 'Switch compiler hints on or off.'),
    (De: 'Zeile in die erzeugte C++-Headerdatei schreiben.'; En: 'Write a line into the generated C++ header file.'),
    (De: 'Bedingte Kompilierung mit Ausdruck, z. B. Defined(X) oder CompilerVersion >= 36.';
     En: 'Conditional compilation with an expression, e.g. Defined(X) or CompilerVersion >= 36.'),
    (De: 'Kompilieren, wenn das bedingte Symbol definiert ist.'; En: 'Compile if the conditional symbol is defined.'),
    (De: 'Ende einer {$IF}-Bedingung (älterer Stil, sonst {$ENDIF}).';
     En: 'End of an {$IF} condition (older style, otherwise {$ENDIF}).'),
    (De: 'Kompilieren, wenn das bedingte Symbol nicht definiert ist.';
     En: 'Compile if the conditional symbol is not defined.'),
    (De: 'Kompilieren, wenn ein Schalter gesetzt ist, z. B. {$IFOPT R+}.';
     En: 'Compile if a switch is set, e.g. {$IFOPT R+}.'),
    (De: 'Ladeadresse einer DLL oder Anwendung.'; En: 'Load address of a DLL or application.'),
    (De: 'Package bei Änderungen automatisch neu erzeugen.'; En: 'Rebuild the package automatically on changes.'),
    (De: 'Datei an dieser Stelle einfügen ({$I Datei}).'; En: 'Insert a file at this position ({$I File}).'),
    (De: '{$IF} nur mit {$IFEND} schließen (wie vor Delphi XE4).';
     En: 'Close {$IF} only with {$IFEND} (as before Delphi XE4).'),
    (De: 'Objektdatei einbinden ({$L Datei}).'; En: 'Link an object file ({$L File}).'),
    (De: 'Informationen über lokale Symbole für den Debugger ({$L+}).';
     En: 'Information about local symbols for the debugger ({$L+}).'),
    (De: 'string bedeutet einen langen String statt ShortString.';
     En: 'string means a long string instead of ShortString.'),
    (De: 'Eigene Meldung beim Kompilieren ausgeben (HINT, WARN, ERROR, FATAL).';
     En: 'Output an own message while compiling (HINT, WARN, ERROR, FATAL).'),
    (De: 'Erweiterte RTTI für Methoden erzeugen.'; En: 'Generate extended RTTI for methods.'),
    (De: 'Mindestgröße von Aufzählungstypen in Byte.'; En: 'Minimum size of enumeration types in bytes.'),
    (De: 'Überlaufprüfung bei Ganzzahlarithmetik.'; En: 'Overflow checking for integer arithmetic.'),
    (De: 'Zeigerarithmetik für typisierte Zeiger erlauben.'; En: 'Allow pointer arithmetic for typed pointers.'),
    (De: 'Bereichsprüfung für Array-Indizes, Teilbereiche und Strings.';
     En: 'Range checking for array indexes, subranges and strings.'),
    (De: 'Symbol- und Querverweisinformationen erzeugen.'; En: 'Generate symbol and cross-reference information.'),
    (De: 'Ressourcendatei einbinden ({$R Datei.res}).'; En: 'Link a resource file ({$R File.res}).'),
    (De: 'Umfang der erweiterten RTTI je Sichtbarkeit festlegen.';
     En: 'Set the scope of extended RTTI per visibility.'),
    (De: 'Package nur zur Laufzeit, nicht in der IDE installierbar.';
     En: 'Package for run time only, not installable in the IDE.'),
    (De: 'Aufzählungswerte nur mit Typnamen ansprechen (TFarbe.Rot).';
     En: 'Address enumeration values only with the type name (TColor.Red).'),
    (De: 'Alle Typen mit RTTI in die Anwendung linken.'; En: 'Link all types with RTTI into the application.'),
    (De: 'Zeilenende und Einrückung mehrzeiliger String-Literale festlegen.';
     En: 'Set line ending and indentation of multi-line string literals.'),
    (De: 'Der @-Operator liefert typisierte Zeiger.'; En: 'The @ operator returns typed pointers.'),
    (De: 'RTTI für published-Abschnitte erzeugen.'; En: 'Generate RTTI for published sections.'),
    (De: 'Strenge Prüfung von ShortString-var-Parametern.'; En: 'Strict checking of ShortString var parameters.'),
    (De: 'Einzelne Warnung ein- oder ausschalten oder zum Fehler machen ({$WARN BEZEICHNER OFF}).';
     En: 'Switch a single warning on or off or turn it into an error ({$WARN IDENTIFIER OFF}).'),
    (De: 'Warnungen des Compilers ein- oder ausschalten.'; En: 'Switch compiler warnings on or off.'),
    (De: 'Beschreibungstext eines Packages.'; En: 'Description text of a package.'),
    (De: 'Ende eines einklappbaren Bereichs.'; En: 'End of a collapsible region.'),
    (De: 'Erweiterte Syntax: Funktionsaufruf als Anweisung, Result, PChar-Arithmetik.';
     En: 'Extended syntax: function call as statement, Result, PChar arithmetic.'),
    (De: 'Zeichenliterale #$80..#$FF als Unicode statt als ANSI auslegen.';
     En: 'Interpret character literals #$80..#$FF as Unicode instead of ANSI.'),
    (De: 'Zugriff auf Variablen aus anderen Packages erlauben.';
     En: 'Allow access to variables from other packages.'),
    (De: 'Ein-/Ausgabefehler als Exception melden ({$I+}).'; En: 'Report input/output errors as exceptions ({$I+}).'),
    (De: 'String-Parameter als offene Strings behandeln.'; En: 'Treat string parameters as open strings.'),
    (De: 'Real als 6-Byte-Typ Real48 behandeln.'; En: 'Treat Real as the 6-byte type Real48.'),
    (De: 'Anfang eines einklappbaren Bereichs.'; En: 'Start of a collapsible region.'),
    (De: 'Unit schwach in ein Package aufnehmen.'; En: 'Include the unit weakly in a package.'),
    (De: 'String-Indizes beginnen bei 0.'; En: 'String indexes start at 0.'),
    (De: 'Bedingtes Symbol definieren.'; En: 'Define a conditional symbol.'),
    (De: 'Code optimieren.'; En: 'Optimize code.'),
    (De: 'Pentium-sichere Gleitkommadivision (historisch).';
     En: 'Pentium-safe floating point division (historical).'),
    (De: 'Immer Stackframes erzeugen.'; En: 'Always generate stack frames.'),
    (De: 'Bedingtes Symbol aufheben.'; En: 'Undefine a conditional symbol.'),
    (De: 'Typisierte Konstanten beschreibbar machen.'; En: 'Make typed constants writeable.'),
    (De: #10 + #10 + 'Hier: ';
     En: #10 + #10 + 'Here: '),
    (De: 'eingeschaltet'; En: 'on'),
    (De: 'ausgeschaltet'; En: 'off'),
    (De: 'Warnung `%s`: %s'; En: 'Warning `%s`: %s'),
    (De: 'Debug-Informationen erzeugen.'; En: 'Generate debug information.'));

{$SCOPEDENUMS OFF}

function D(const AName, ALetter, AText, ATopic: string): TDirectiveInfo;
begin
  Result.Name := AName;
  Result.Letter := ALetter;
  Result.Text := AText;
  Result.Topic := ATopic;
end;

var
  /// <summary>Je Sprache einmal beim Laden aufgebaut, damit Anfragen in mehreren Threads nur lesen.</summary>
  Directives: array[TTextLanguage] of TArray<TDirectiveInfo>;

/// <summary>Direktiven A bis L.</summary>
procedure InitDirectivesToL(ALanguage: TTextLanguage);
begin
  Directives[ALanguage] := [
    D('ALIGN', 'A', cTexts[TCompilerDirectivesText.AlignmentOfFieldsInRecords].TextIn(ALanguage),
      'Align_fields_(Delphi)'),
    D('APPTYPE', '', cTexts[TCompilerDirectivesText.KindOfApplicationCONSOLEOr].TextIn(ALanguage),
      'Application_type_(Delphi)'),
    D('ASSERTIONS', 'C', cTexts[TCompilerDirectivesText.CompileAssertCallsInOr].TextIn(ALanguage),
      'Assert_directives_(Delphi)'),
    D('BOOLEVAL', 'B', cTexts[TCompilerDirectivesText.EvaluateBooleanExpressionsCompletelyInstead].TextIn(ALanguage),
      'Boolean_short-circuit_evaluation_(Delphi_compiler_directive)'),
    D('CODEALIGN', '', cTexts[TCompilerDirectivesText.AlignmentOfTheGeneratedCode].TextIn(ALanguage),
      'Code_align_(Delphi)'),
    D('DEBUGINFO', 'D', cTexts[TCompilerDirectivesText.GenerateDebugInformation].TextIn(ALanguage),
      'Debug_information_(Delphi)'),
    D('DEFINE', '', cTexts[TCompilerDirectivesText.DefineAConditionalSymbol].TextIn(ALanguage),
      'DEFINE_directive_(Delphi)'),
    D('DENYPACKAGEUNIT', '', cTexts[TCompilerDirectivesText.UnitMustNotBeIncluded].TextIn(ALanguage),
      'Deny_package_unit_(Delphi)'),
    D('DESCRIPTION', '', cTexts[TCompilerDirectivesText.DescriptionTextOfAPackage].TextIn(ALanguage),
      'Description_(Delphi)'),
    D('DESIGNONLY', '', cTexts[TCompilerDirectivesText.PackageForDesignTimeIn].TextIn(ALanguage),
      'Design-time_only_(Delphi)'),
    D('ELSE', '', cTexts[TCompilerDirectivesText.AlternativeOfAConditionalCompilation].TextIn(ALanguage),
      'ELSE_(Delphi)'),
    D('ELSEIF', '', cTexts[TCompilerDirectivesText.FurtherConditionOfAnIF].TextIn(ALanguage), 'ELSEIF_(Delphi)'),
    D('ENDIF', '', cTexts[TCompilerDirectivesText.EndOfAConditionalCompilation].TextIn(ALanguage),
      'ENDIF_directive_(Delphi)'),
    D('ENDREGION', '', cTexts[TCompilerDirectivesText.EndOfACollapsibleRegion].TextIn(ALanguage), 'Regions'),
    D('EXTENDEDSYNTAX', 'X', cTexts[TCompilerDirectivesText.ExtendedSyntaxFunctionCallAs].TextIn(ALanguage),
      'Extended_syntax_(Delphi)'),
    D('HIGHCHARUNICODE', '', cTexts[TCompilerDirectivesText.InterpretCharacterLiterals80FF].TextIn(ALanguage),
      'HIGHCHARUNICODE_directive_(Delphi)'),
    D('HINTS', '', cTexts[TCompilerDirectivesText.SwitchCompilerHintsOnOr].TextIn(ALanguage), 'Hints_(Delphi)'),
    D('HPPEMIT', '', cTexts[TCompilerDirectivesText.WriteALineIntoThe].TextIn(ALanguage), 'HPPEMIT_directive_(Delphi)'),
    D('IF', '', cTexts[TCompilerDirectivesText.ConditionalCompilationWithAnExpression].TextIn(ALanguage),
      'IF_directive_(Delphi)'),
    D('IFDEF', '', cTexts[TCompilerDirectivesText.CompileIfTheConditionalSymbol].TextIn(ALanguage),
      'IFDEF_directive_(Delphi)'),
    D('IFEND', '', cTexts[TCompilerDirectivesText.EndOfAnIFCondition].TextIn(ALanguage), 'IFEND_directive_(Delphi)'),
    D('IFNDEF', '', cTexts[TCompilerDirectivesText.CompileIfTheConditionalSymbol2].TextIn(ALanguage),
      'IFNDEF_directive_(Delphi)'),
    D('IFOPT', '', cTexts[TCompilerDirectivesText.CompileIfASwitchIs].TextIn(ALanguage), 'IFOPT_directive_(Delphi)'),
    D('IMAGEBASE', '', cTexts[TCompilerDirectivesText.LoadAddressOfADLL].TextIn(ALanguage), 'Image_base_address'),
    D('IMPLICITBUILD', '', cTexts[TCompilerDirectivesText.RebuildThePackageAutomaticallyOn].TextIn(ALanguage),
      'Implicit_Build_(Delphi)'),
    D('IMPORTEDDATA', 'G', cTexts[TCompilerDirectivesText.AllowAccessToVariablesFrom].TextIn(ALanguage),
      'Imported_data_(Delphi)'),
    D('INCLUDE', 'I', cTexts[TCompilerDirectivesText.InsertAFileAtThis].TextIn(ALanguage), 'Include_file_(Delphi)'),
    D('IOCHECKS', 'I', cTexts[TCompilerDirectivesText.ReportInputOutputErrorsAs].TextIn(ALanguage),
      'Input_output_checking_(Delphi)'),
    D('LEGACYIFEND', '', cTexts[TCompilerDirectivesText.CloseIFOnlyWithIFEND].TextIn(ALanguage),
      'Legacy_IFEND_(Delphi)'),
    D('LINK', 'L', cTexts[TCompilerDirectivesText.LinkAnObjectFileL].TextIn(ALanguage), 'Link_object_file_(Delphi)'),
    D('LOCALSYMBOLS', 'L', cTexts[TCompilerDirectivesText.InformationAboutLocalSymbolsFor].TextIn(ALanguage),
      'Local_symbol_information_(Delphi)')];
end;

/// <summary>Direktiven ab LONGSTRINGS.</summary>
procedure InitDirectivesFromL(ALanguage: TTextLanguage);
begin
  Directives[ALanguage] := Directives[ALanguage] + [
    D('LONGSTRINGS', 'H', cTexts[TCompilerDirectivesText.StringMeansALongString].TextIn(ALanguage),
      'Long_strings_(Delphi)'),
    D('MESSAGE', '', cTexts[TCompilerDirectivesText.OutputAnOwnMessageWhile].TextIn(ALanguage),
      'MESSAGE_directive_(Delphi)'),
    D('METHODINFO', '', cTexts[TCompilerDirectivesText.GenerateExtendedRTTIForMethods].TextIn(ALanguage),
      'METHODINFO_directive_(Delphi)'),
    D('MINENUMSIZE', 'Z', cTexts[TCompilerDirectivesText.MinimumSizeOfEnumerationTypes].TextIn(ALanguage),
      'Minimum_enumeration_size_(Delphi)'),
    D('OPENSTRINGS', 'P', cTexts[TCompilerDirectivesText.TreatStringParametersAsOpen].TextIn(ALanguage),
      'Open_String_Parameters_(Delphi)'),
    D('OPTIMIZATION', 'O', cTexts[TCompilerDirectivesText.OptimizeCode].TextIn(ALanguage), 'Optimization_(Delphi)'),
    D('OVERFLOWCHECKS', 'Q', cTexts[TCompilerDirectivesText.OverflowCheckingForIntegerArithmetic].TextIn(ALanguage),
      'Overflow_checking_(Delphi)'),
    D('POINTERMATH', '', cTexts[TCompilerDirectivesText.AllowPointerArithmeticForTyped].TextIn(ALanguage),
      'Pointer_Math_(Delphi)'),
    D('RANGECHECKS', 'R', cTexts[TCompilerDirectivesText.RangeCheckingForArrayIndexes].TextIn(ALanguage),
      'Range_checking'),
    D('REALCOMPATIBILITY', '', cTexts[TCompilerDirectivesText.TreatRealAsThe6].TextIn(ALanguage),
      'Real48_compatibility_(Delphi)'),
    D('REFERENCEINFO', 'Y', cTexts[TCompilerDirectivesText.GenerateSymbolAndCrossReference].TextIn(ALanguage),
      'Symbol_declaration_and_cross-reference_information_(Delphi)'),
    D('REGION', '', cTexts[TCompilerDirectivesText.StartOfACollapsibleRegion].TextIn(ALanguage), 'Regions'),
    D('RESOURCE', 'R', cTexts[TCompilerDirectivesText.LinkAResourceFileR].TextIn(ALanguage), 'Resource_file_(Delphi)'),
    D('RTTI', '', cTexts[TCompilerDirectivesText.SetTheScopeOfExtended].TextIn(ALanguage), 'RTTI_directive_(Delphi)'),
    D('RUNONLY', '', cTexts[TCompilerDirectivesText.PackageForRunTimeOnly].TextIn(ALanguage), 'Run-Time_only_(Delphi)'),
    D('SAFEDIVIDE', 'U', cTexts[TCompilerDirectivesText.PentiumSafeFloatingPointDivision].TextIn(ALanguage),
      'Pentium-safe_FDIV_operations_(Delphi)'),
    D('SCOPEDENUMS', '', cTexts[TCompilerDirectivesText.AddressEnumerationValuesOnlyWith].TextIn(ALanguage),
      'Scoped_Enums_(Delphi)'),
    D('STACKFRAMES', 'W', cTexts[TCompilerDirectivesText.AlwaysGenerateStackFrames].TextIn(ALanguage),
      'Stack_frames_(Delphi)'),
    D('STRONGLINKTYPES', '', cTexts[TCompilerDirectivesText.LinkAllTypesWithRTTI].TextIn(ALanguage),
      'Strong_link_types_(Delphi)'),
    D('TEXTBLOCK', '', cTexts[TCompilerDirectivesText.SetLineEndingAndIndentation].TextIn(ALanguage),
      'Text_block_directive_(Delphi)'),
    D('TYPEDADDRESS', 'T', cTexts[TCompilerDirectivesText.TheOperatorReturnsTypedPointers].TextIn(ALanguage),
      'Type-checked_pointers_(Delphi)'),
    D('TYPEINFO', 'M', cTexts[TCompilerDirectivesText.GenerateRTTIForPublishedSections].TextIn(ALanguage),
      'Run-Time_Type_Information_(Delphi)'),
    D('UNDEF', '', cTexts[TCompilerDirectivesText.UndefineAConditionalSymbol].TextIn(ALanguage),
      'UNDEF_directive_(Delphi)'),
    D('VARSTRINGCHECKS', 'V', cTexts[TCompilerDirectivesText.StrictCheckingOfShortStringVar].TextIn(ALanguage),
      'Var-string_checking_(Delphi)'),
    D('WARN', '', cTexts[TCompilerDirectivesText.SwitchASingleWarningOn].TextIn(ALanguage),
      'Warning_messages_(Delphi)'),
    D('WARNINGS', '', cTexts[TCompilerDirectivesText.SwitchCompilerWarningsOnOr].TextIn(ALanguage),
      'Warnings_(Delphi)'),
    D('WEAKPACKAGEUNIT', '', cTexts[TCompilerDirectivesText.IncludeTheUnitWeaklyIn].TextIn(ALanguage),
      'Weak_packaging'),
    D('WRITEABLECONST', 'J', cTexts[TCompilerDirectivesText.MakeTypedConstantsWriteable].TextIn(ALanguage),
      'Writeable_typed_constants_(Delphi)'),
    D('ZEROBASEDSTRINGS', '', cTexts[TCompilerDirectivesText.StringIndexesStartAt0].TextIn(ALanguage),
      'Zero-based_strings_(Delphi)')];
end;

procedure InitDirectives;
var
  mLanguage: TTextLanguage;
begin
  for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
  begin
    InitDirectivesToL(mLanguage);
    InitDirectivesFromL(mLanguage);
  end;
end;

{ TCompilerDirectives }

class function TCompilerDirectives.All: TArray<TDirectiveInfo>;
begin
  Result := Copy(Directives[TAtlasLocale.Language]);
end;

class function TCompilerDirectives.Warnings: TArray<string>;
begin
  Result := TDirectiveNames.Warnings;
end;

class function TCompilerDirectives.Find(const AName: string; out AInfo: TDirectiveInfo): Boolean;
var
  Info: TDirectiveInfo;
begin
  for Info in Directives[TAtlasLocale.Language] do
  begin
    if SameText(Info.Name, AName) or ((Length(AName) = 1) and SameText(Info.Letter, AName)) then
    begin
      AInfo := Info;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompilerDirectives.Url(const ADelphiVersion, ATopic: string): string;
begin
  Result := BaseUri + TDocWiki.ReleaseName(ADelphiVersion) + '/en/' + ATopic;
end;

function DescribeInfo(const AInfo: TDirectiveInfo; const AVersion, AState: string): string;
begin
  Result := '**{$' + AInfo.Name + '}**';
  if AInfo.Letter <> '' then
  begin
    Result := Result + ' (**{$' + AInfo.Letter + '}**)';
  end;
  Result := Result + #10#10 + AInfo.Text;
  if AState <> '' then
  begin
    Result := Result + cTexts[TCompilerDirectivesText.Here].Text + AState;
  end;
  Result := Result + #10#10 + '[DocWiki](' + TCompilerDirectives.Url(AVersion, AInfo.Topic) + ')';
end;

/// <summary>Beschreibung eines Kurzschalters wie R+ ('' wenn keiner).</summary>
function DescribeSwitch(const APart, AVersion: string): string;
var
  mInfo: TDirectiveInfo;
begin
  Result := '';
  if not ((Length(APart) = 2) and CharInSet(APart[2], ['+', '-'])) then
  begin
    Exit;
  end;
  for mInfo in Directives[TAtlasLocale.Language] do
  begin
    // I, L und R sind mit Dateinamen andere Direktiven; mit +/- sind es die Schalter.
    if SameText(mInfo.Letter, APart[1]) and not MatchText(mInfo.Name, ['INCLUDE', 'LINK', 'RESOURCE']) then
    begin
      Exit(DescribeInfo(mInfo, AVersion, IfThen(APart[2] = '+', cTexts[TCompilerDirectivesText.SwitchedOn].Text,
        cTexts[TCompilerDirectivesText.SwitchedOff].Text)));
    end;
  end;
end;

/// <summary>Kurzschalter, auch mehrere: {$R+,Q-}.</summary>
function DescribeSwitches(const AText, AVersion: string): string;
var
  mPart, mOne: string;
begin
  Result := '';
  for mPart in AText.Split([',']) do
  begin
    mOne := DescribeSwitch(Trim(mPart), AVersion);
    if (mOne <> '') and (Result <> '') then
    begin
      Result := Result + #10#10'---'#10#10;
    end;
    Result := Result + mOne;
  end;
end;

/// <summary>{$WARN BEZEICHNER OFF}: die Direktive und, wenn bekannt, die Warnung.</summary>
function DescribeWarn(const AInfo: TDirectiveInfo; const ARest, AVersion: string): string;
var
  mWarning: string;
begin
  mWarning := TDirectiveNames.LeadingName(ARest);
  Result := DescribeInfo(AInfo, AVersion, '');
  if TDirectiveNames.IsWarning(mWarning) then
  begin
    Result := Result + #10#10 + cTexts[TCompilerDirectivesText.Warning].Fmt([UpperCase(mWarning),
      Trim(Copy(ARest, Length(mWarning) + 1, MaxInt))]);
  end;
end;

/// <summary>Zustand nach dem Namen: ON/+ eingeschaltet, OFF/- ausgeschaltet, sonst ''.</summary>
function StateOf(const ARest: string): string;
begin
  if MatchText(ARest, ['ON', '+']) then
  begin
    Result := cTexts[TCompilerDirectivesText.SwitchedOn].Text;
  end
  else if MatchText(ARest, ['OFF', '-']) then
  begin
    Result := cTexts[TCompilerDirectivesText.SwitchedOff].Text;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>{$I Datei}, {$L Datei}, {$R Datei}: Dateidirektiven; andere Namen bleiben.</summary>
function FileDirectiveName(const AName: string): string;
begin
  Result := AName;
  if Length(AName) <> 1 then
  begin
    Exit;
  end;
  case UpCase(AName[1]) of
    'I': Result := 'INCLUDE';
    'L': Result := 'LINK';
    'R': Result := 'RESOURCE';
  else
    // Übrige Buchstaben: Name bleibt.
  end;
end;

class function TCompilerDirectives.Describe(const ADirective, ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  mText, mName, mRest: string;
  mInfo: TDirectiveInfo;
begin
  AMarkdown := '';
  mText := TDirectiveNames.Body(ADirective);
  mName := TDirectiveNames.LeadingName(mText);
  mRest := Trim(Copy(mText, Length(mName) + 1, MaxInt));
  if mName = '' then
  begin
    Exit(False);
  end;
  if (Length(mName) = 1) and (mRest <> '') and CharInSet(mRest[1], ['+', '-']) then
  begin
    AMarkdown := DescribeSwitches(mText, ADelphiVersion);
    Exit(AMarkdown <> '');
  end;
  Result := Find(FileDirectiveName(mName), mInfo);
  if not Result then
  begin
    Exit;
  end;
  if SameText(mInfo.Name, 'WARN') then
  begin
    AMarkdown := DescribeWarn(mInfo, mRest, ADelphiVersion);
  end
  else
  begin
    AMarkdown := DescribeInfo(mInfo, ADelphiVersion, StateOf(mRest));
  end;
end;

class function TCompilerDirectives.CompletionAt(const ALineBeforeCursor: string; out ANames: TArray<string>;
  out AIsWarning: Boolean): Boolean;
var
  Open: Integer;
  Inner: string;
  Info: TDirectiveInfo;
begin
  ANames := nil;
  AIsWarning := False;
  Open := 0;
  // Letzte offene Direktive in der Zeile vor dem Cursor.
  while PosEx('{$', ALineBeforeCursor, Open + 1) > 0 do
  begin
    Open := PosEx('{$', ALineBeforeCursor, Open + 1);
  end;
  if (Open = 0) or (PosEx('}', ALineBeforeCursor, Open) > 0) then
  begin
    Exit(False);
  end;
  Inner := Copy(ALineBeforeCursor, Open + 2, MaxInt);
  if StartsText('WARN ', Inner) then
  begin
    // Nur der Bezeichner direkt nach WARN, nicht ON/OFF dahinter.
    if Pos(' ', Trim(Copy(Inner, 6, MaxInt))) > 0 then
    begin
      Exit(False);
    end;
    AIsWarning := True;
    ANames := Warnings;
    Exit(True);
  end;
  // Nur solange der Name getippt wird.
  if TDirectiveNames.LeadingName(Inner) <> Inner then
  begin
    Exit(False);
  end;
  for Info in Directives[TAtlasLocale.Language] do
  begin
    ANames := ANames + [Info.Name];
  end;
  Result := True;
end;

class function TCompilerDirectives.HoverAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  const ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  Token: TPascalToken;
  AfterStart, BeforeEnd: Boolean;
begin
  AMarkdown := '';
  if ATree = nil then
  begin
    Exit(False);
  end;
  for Token in ATree.Tokens do
  begin
    AfterStart := (Token.StartPos.Line < APosition.Line) or ((Token.StartPos.Line = APosition.Line) and
      (Token.StartPos.Character <= APosition.Character));
    BeforeEnd := (Token.EndPos.Line > APosition.Line) or ((Token.EndPos.Line = APosition.Line) and
      (Token.EndPos.Character > APosition.Character));
    if AfterStart and BeforeEnd then
    begin
      Exit((Token.Kind = TPascalTokenKind.Directive) and Describe(Token.Text, ADelphiVersion, AMarkdown));
    end;
  end;
  Result := False;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.CompilerDirectives', cTexts);
  InitDirectives;

end.
