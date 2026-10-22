unit Atlas.Common.Pascal.DirectiveNames;

// Namen der Compiler-Direktiven und der Bezeichner für {$WARN} (#989): Grundlage
// für Hover und Vervollständigung in Direktiven (Lsp.CompilerDirectives, #102)
// und für die Prüfregel conditional-directive-unbalanced, die unbekannte Namen
// meldet (wie W1030). Die Listen enthalten alles, was Delphi 12 und 13 kennen,
// auch Direktiven ohne Hovertext (C++-Ausgabe, PE-Kopf, Linux-Bibliotheken).
//
// Kurzschalter aus einem Buchstaben ({$R+}, {$A8}, {$M 16384,1048576}) gelten
// immer als bekannt, ebenso {$YD}; Delphi kennt fast jeden Buchstaben.

interface

type
  TDirectiveNames = record
  public
    /// <summary>Inhalt der Direktive ohne "{$" bzw. "(*$" und die schließende Klammer, ohne Rand.</summary>
    class function Body(const ADirective: string): string; static;
    /// <summary>Führende Buchstaben und Unterstriche, z. B. der Name der Direktive aus dem Inhalt.</summary>
    class function LeadingName(const AText: string): string; static;
    /// <summary>Alle langen Direktivennamen in Großbuchstaben.</summary>
    class function Directives: TArray<string>; static;
    /// <summary>Kennt Delphi die Direktive AName (ohne Groß-/Kleinschreibung, Kurzschalter eingeschlossen)?</summary>
    class function IsDirective(const AName: string): Boolean; static;
    /// <summary>Alle Bezeichner für {$WARN …} in Großbuchstaben.</summary>
    class function Warnings: TArray<string>; static;
    /// <summary>Ist AName ein Bezeichner für {$WARN …} (ohne Groß-/Kleinschreibung)?</summary>
    class function IsWarning(const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  DirectiveNames: array[0..100] of string = (
    'ALIGN', 'APPTYPE', 'ASSERTIONS', 'BOOLEVAL', 'CODEALIGN', 'CODEPAGE', 'DEBUGINFO', 'DEFINE', 'DEFINITIONINFO',
    'DENYPACKAGEUNIT', 'DESCRIPTION', 'DESIGNONLY', 'DYNAMICBASE', 'ELSE', 'ELSEIF', 'ENDIF', 'ENDREGION',
    'EXCESSPRECISION', 'EXTENDEDCOMPATIBILITY', 'EXTENDEDSYNTAX', 'EXTENSION', 'EXTERNALSYM', 'FINITEFLOAT',
    'HIGHCHARUNICODE', 'HIGHENTROPYVA', 'HINTS', 'HPPEMIT', 'IF', 'IFDEF', 'IFEND', 'IFNDEF', 'IFOPT', 'IMAGEBASE',
    'IMPLICITBUILD', 'IMPORTEDDATA', 'INCLUDE', 'INLINE', 'IOCHECKS', 'LARGEADDRESSAWARE', 'LEGACYIFEND',
    'LIBPREFIX', 'LIBSUFFIX', 'LIBVERSION', 'LINK', 'LOCALSYMBOLS', 'LONGSTRINGS', 'MAXSTACKSIZE', 'MESSAGE',
    'METHODINFO', 'MINENUMSIZE', 'MINSTACKSIZE', 'NODEFINE', 'NOINCLUDE', 'NXCOMPAT', 'OBJEXPORTALL',
    'OBJTYPENAME', 'OLDTYPELAYOUT', 'OPENSTRINGS', 'OPTIMIZATION', 'OVERFLOWCHECKS', 'POINTERMATH', 'POPOPT',
    'PUSHOPT', 'RANGECHECKS', 'REALCOMPATIBILITY', 'REFERENCEINFO', 'REGION', 'RESOURCE', 'RESOURCERESERVE',
    'RTTI', 'RUNONLY', 'SAFEDIVIDE', 'SCOPEDENUMS', 'SETPEFLAGS', 'SETPEOPTFLAGS', 'SETPEOSVERSION',
    'SETPESUBSYSVERSION', 'SETPEUSERVERSION', 'SONAME', 'SOPREFIX', 'SOSUFFIX', 'SOVERSION', 'STACKCHECKS',
    'STACKFRAMES', 'STRINGCHECKS', 'STRONGLINKTYPES', 'TEXTBLOCK', 'TSAWARE', 'TYPEDADDRESS', 'TYPEINFO', 'UNDEF',
    'UNSAFECODE', 'VARPROPSETTER', 'VARSTRINGCHECKS', 'WARN', 'WARNINGS', 'WEAKLINKRTTI', 'WEAKPACKAGEUNIT',
    'WRITEABLECONST', 'YD', 'ZEROBASEDSTRINGS');

  WarningNames: array[0..80] of string = (
    'ASG_TO_TYPED_CONST', 'BAD_GLOBAL_SYMBOL', 'BOUNDS_ERROR', 'CASE_LABEL_RANGE', 'COMBINING_SIGNED_UNSIGNED',
    'COMBINING_SIGNED_UNSIGNED64', 'COMPARING_SIGNED_UNSIGNED', 'COMPARING_SIGNED_UNSIGNED64', 'COMPARISON_FALSE',
    'COMPARISON_TRUE', 'CONSTRUCTING_ABSTRACT', 'CVT_ACHAR_TO_WCHAR', 'CVT_NARROWING_STRING_LOST',
    'CVT_WCHAR_TO_ACHAR', 'CVT_WIDENING_STRING_LOST', 'DUPLICATE_CTOR_DTOR', 'DUPLICATES_IGNORED',
    'EXPLICIT_STRING_CAST', 'EXPLICIT_STRING_CAST_LOSS', 'FILE_OPEN', 'FILE_OPEN_UNITSRC', 'FOR_LOOP_VAR_UNDEF',
    'FOR_LOOP_VAR_VARPAR', 'FOR_VARIABLE', 'GARBAGE', 'HIDDEN_VIRTUAL', 'HIDING_MEMBER', 'HPPEMIT_IGNORED',
    'HRESULT_COMPAT', 'IMAGEBASE_MULTIPLE', 'IMMUTABLE_STRINGS', 'IMPLICIT_CONVERSION_LOSS', 'IMPLICIT_IMPORT',
    'IMPLICIT_INTEGER_CAST_LOSS', 'IMPLICIT_STRING_CAST', 'IMPLICIT_STRING_CAST_LOSS', 'IMPLICIT_VARIANTS',
    'INVALID_DIRECTIVE', 'LOCAL_PINVOKE', 'LOCALE_TO_UNICODE', 'LOST_EXTENDED_PRECISION', 'MESSAGE_DIRECTIVE',
    'NO_CFG_FILE_FOUND', 'NO_RETVAL', 'NON_PORTABLE_TYPECAST', 'OPTION_TRUNCATED', 'PACKAGE_NO_LINK',
    'PACKAGED_THREADVAR', 'PRIVATE_PROPACCESSOR', 'RLINK_WARNING', 'STRING_CONST_TRUNCED', 'SUSPICIOUS_TYPECAST',
    'SYMBOL_DEPRECATED', 'SYMBOL_EXPERIMENTAL', 'SYMBOL_LIBRARY', 'SYMBOL_PLATFORM', 'TYPED_CONST_VARPAR',
    'TYPEINFO_IMPLICITLY_ADDED', 'UNICODE_TO_LOCALE', 'UNIT_DEPRECATED', 'UNIT_EXPERIMENTAL', 'UNIT_INIT_SEQ',
    'UNIT_LIBRARY', 'UNIT_NAME_MISMATCH', 'UNIT_PLATFORM', 'UNKNOWN_CUSTOM_ATTRIBUTE', 'UNSAFE_CAST',
    'UNSAFE_CODE', 'UNSAFE_TYPE', 'UNSUPPORTED_CONSTRUCT', 'USE_BEFORE_DEF', 'WIDECHAR_REDUCED',
    'XML_CREF_NO_RESOLVE', 'XML_EXPECTED_CHARACTER', 'XML_INVALID_NAME', 'XML_INVALID_NAME_START',
    'XML_NO_MATCHING_PARM', 'XML_NO_PARM', 'XML_UNKNOWN_ENTITY', 'XML_WHITESPACE_NOT_ALLOWED', 'ZERO_NIL_COMPAT');

class function TDirectiveNames.Body(const ADirective: string): string;
begin
  Result := Trim(ADirective);
  if StartsStr('{$', Result) then
    Result := Copy(Result, 3, MaxInt)
  else if StartsStr('(*$', Result) then
    Result := Copy(Result, 4, MaxInt);
  if EndsStr('*)', Result) then
    Result := Copy(Result, 1, Length(Result) - 2)
  else if EndsStr('}', Result) then
    Result := Copy(Result, 1, Length(Result) - 1);
  Result := Trim(Result);
end;

class function TDirectiveNames.LeadingName(const AText: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_']) do
    Inc(Index);
  Result := Copy(AText, 1, Index - 1);
end;

class function TDirectiveNames.Directives: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(DirectiveNames));
  for Index := 0 to High(DirectiveNames) do
    Result[Index] := DirectiveNames[Index];
end;

class function TDirectiveNames.IsDirective(const AName: string): Boolean;
begin
  Result := (Length(AName) = 1) and CharInSet(AName[1], ['A'..'Z', 'a'..'z']);
  if not Result then
    Result := MatchText(AName, DirectiveNames);
end;

class function TDirectiveNames.Warnings: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(WarningNames));
  for Index := 0 to High(WarningNames) do
    Result[Index] := WarningNames[Index];
end;

class function TDirectiveNames.IsWarning(const AName: string): Boolean;
begin
  Result := MatchText(AName, WarningNames);
end;

end.
