unit Atlas.Common.Pascal.WarningCodes;

// Zuordnung Meldungsnummer des Compilers → Bezeichner für {$WARN} (#531),
// versioniert nach Delphi-Version (BDS-Nummer wie in #109). Grundlage für
// „Warnung hier abschalten“ (Atlas.Common.Editing.DisableWarning).
//
// Die Tabelle enthält nur Nummern, deren Bezeichner sicher feststehen; jeder
// Bezeichner steht auch in TDirectiveNames.Warnings. Fehlt eine Nummer (oder
// kennt die eingestellte Version den Bezeichner noch nicht), bleibt nur
// {$WARNINGS OFF}, das alle Warnungen betrifft. Hinweise (H…) haben keine
// eigenen Bezeichner: Für sie gilt {$HINTS OFF}.
//
// Ablaufmeldungen (Wert nie benutzt, Variable nie verwendet, Funktion ohne
// Ergebnis …) ermittelt der Compiler erst am Ende der Routine: Ein Schalter
// nur um die Zeile wirkt dort nicht, sie lassen sich nur für die ganze
// Routine abschalten.

interface

type
  TWarningCodeKind = (None, Hint, Warning);

  TWarningCodes = record
  public
    /// <summary>Art der Meldung nach der Nummer: H… Hinweis, W… Warnung, sonst None (Fehler, unbekannt).</summary>
    class function KindOf(const ACode: string): TWarningCodeKind; static;
    /// <summary>Bezeichner für {$WARN} zu ACode (Groß-/Kleinschreibung egal) in der Delphi-Version AVersion
    /// (BDS-Nummer; leer oder ungültig = aktuelle Version); '' ohne eigenen Bezeichner.</summary>
    class function Identifier(const ACode, AVersion: string): string; static;
    /// <summary>BDS-Version, ab der ACode einen Bezeichner hat; '' = in allen unterstützten Versionen, auch
    /// wenn ACode keinen hat.</summary>
    class function Since(const ACode: string): string; static;
    /// <summary>Meldung aus der Ablaufanalyse: wirkt nur, wenn der Schalter die ganze Routine umfasst.</summary>
    class function IsRoutineWide(const ACode: string): Boolean; static;
    /// <summary>Alle Nummern der Tabelle in Großbuchstaben.</summary>
    class function Codes: TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.LanguageFeatures;

type
  TWarningCode = record
    Code: string;
    Identifier: string;
    Since: string;
  end;

const
  // Since: BDS-Nummer der ersten Version mit dem Bezeichner; '' = schon vor Delphi 2009 (BDS 6.0).
  Table: array[0..76] of TWarningCode = (
    (Code: 'W1000'; Identifier: 'SYMBOL_DEPRECATED'; Since: ''),
    (Code: 'W1001'; Identifier: 'SYMBOL_LIBRARY'; Since: ''),
    (Code: 'W1002'; Identifier: 'SYMBOL_PLATFORM'; Since: ''),
    (Code: 'W1003'; Identifier: 'SYMBOL_EXPERIMENTAL'; Since: ''),
    (Code: 'W1004'; Identifier: 'UNIT_LIBRARY'; Since: ''),
    (Code: 'W1005'; Identifier: 'UNIT_PLATFORM'; Since: ''),
    (Code: 'W1006'; Identifier: 'UNIT_DEPRECATED'; Since: ''),
    (Code: 'W1007'; Identifier: 'UNIT_EXPERIMENTAL'; Since: ''),
    (Code: 'W1008'; Identifier: 'HRESULT_COMPAT'; Since: ''),
    (Code: 'W1009'; Identifier: 'HIDING_MEMBER'; Since: ''),
    (Code: 'W1010'; Identifier: 'HIDDEN_VIRTUAL'; Since: ''),
    (Code: 'W1011'; Identifier: 'GARBAGE'; Since: ''),
    (Code: 'W1012'; Identifier: 'BOUNDS_ERROR'; Since: ''),
    (Code: 'W1013'; Identifier: 'ZERO_NIL_COMPAT'; Since: ''),
    (Code: 'W1014'; Identifier: 'STRING_CONST_TRUNCED'; Since: ''),
    (Code: 'W1015'; Identifier: 'FOR_LOOP_VAR_VARPAR'; Since: ''),
    (Code: 'W1016'; Identifier: 'TYPED_CONST_VARPAR'; Since: ''),
    (Code: 'W1017'; Identifier: 'ASG_TO_TYPED_CONST'; Since: ''),
    (Code: 'W1018'; Identifier: 'CASE_LABEL_RANGE'; Since: ''),
    (Code: 'W1019'; Identifier: 'FOR_VARIABLE'; Since: ''),
    (Code: 'W1020'; Identifier: 'CONSTRUCTING_ABSTRACT'; Since: ''),
    (Code: 'W1021'; Identifier: 'COMPARISON_FALSE'; Since: ''),
    (Code: 'W1022'; Identifier: 'COMPARISON_TRUE'; Since: ''),
    (Code: 'W1023'; Identifier: 'COMPARING_SIGNED_UNSIGNED'; Since: ''),
    (Code: 'W1024'; Identifier: 'COMBINING_SIGNED_UNSIGNED'; Since: ''),
    (Code: 'W1025'; Identifier: 'UNSUPPORTED_CONSTRUCT'; Since: ''),
    (Code: 'W1026'; Identifier: 'FILE_OPEN'; Since: ''),
    (Code: 'W1027'; Identifier: 'FILE_OPEN_UNITSRC'; Since: ''),
    (Code: 'W1028'; Identifier: 'BAD_GLOBAL_SYMBOL'; Since: ''),
    (Code: 'W1029'; Identifier: 'DUPLICATE_CTOR_DTOR'; Since: ''),
    (Code: 'W1030'; Identifier: 'INVALID_DIRECTIVE'; Since: ''),
    (Code: 'W1031'; Identifier: 'PACKAGE_NO_LINK'; Since: ''),
    (Code: 'W1032'; Identifier: 'PACKAGED_THREADVAR'; Since: ''),
    (Code: 'W1033'; Identifier: 'IMPLICIT_IMPORT'; Since: ''),
    (Code: 'W1034'; Identifier: 'HPPEMIT_IGNORED'; Since: ''),
    (Code: 'W1035'; Identifier: 'NO_RETVAL'; Since: ''),
    (Code: 'W1036'; Identifier: 'USE_BEFORE_DEF'; Since: ''),
    (Code: 'W1037'; Identifier: 'FOR_LOOP_VAR_UNDEF'; Since: ''),
    (Code: 'W1038'; Identifier: 'UNIT_NAME_MISMATCH'; Since: ''),
    (Code: 'W1039'; Identifier: 'NO_CFG_FILE_FOUND'; Since: ''),
    (Code: 'W1040'; Identifier: 'IMPLICIT_VARIANTS'; Since: ''),
    (Code: 'W1041'; Identifier: 'UNICODE_TO_LOCALE'; Since: ''),
    (Code: 'W1042'; Identifier: 'LOCALE_TO_UNICODE'; Since: ''),
    (Code: 'W1043'; Identifier: 'IMAGEBASE_MULTIPLE'; Since: ''),
    (Code: 'W1044'; Identifier: 'SUSPICIOUS_TYPECAST'; Since: ''),
    (Code: 'W1045'; Identifier: 'PRIVATE_PROPACCESSOR'; Since: ''),
    (Code: 'W1046'; Identifier: 'UNSAFE_TYPE'; Since: ''),
    (Code: 'W1047'; Identifier: 'UNSAFE_CODE'; Since: ''),
    (Code: 'W1048'; Identifier: 'UNSAFE_CAST'; Since: ''),
    (Code: 'W1049'; Identifier: 'OPTION_TRUNCATED'; Since: ''),
    (Code: 'W1050'; Identifier: 'WIDECHAR_REDUCED'; Since: ''),
    (Code: 'W1051'; Identifier: 'DUPLICATES_IGNORED'; Since: ''),
    (Code: 'W1052'; Identifier: 'UNIT_INIT_SEQ'; Since: ''),
    (Code: 'W1053'; Identifier: 'LOCAL_PINVOKE'; Since: ''),
    (Code: 'W1054'; Identifier: 'MESSAGE_DIRECTIVE'; Since: ''),
    (Code: 'W1055'; Identifier: 'TYPEINFO_IMPLICITLY_ADDED'; Since: ''),
    (Code: 'W1056'; Identifier: 'RLINK_WARNING'; Since: ''),
    // Unicode-Strings: Delphi 2009.
    (Code: 'W1057'; Identifier: 'IMPLICIT_STRING_CAST'; Since: '6.0'),
    (Code: 'W1058'; Identifier: 'IMPLICIT_STRING_CAST_LOSS'; Since: '6.0'),
    (Code: 'W1059'; Identifier: 'EXPLICIT_STRING_CAST'; Since: '6.0'),
    (Code: 'W1060'; Identifier: 'EXPLICIT_STRING_CAST_LOSS'; Since: '6.0'),
    (Code: 'W1061'; Identifier: 'CVT_WCHAR_TO_ACHAR'; Since: '6.0'),
    (Code: 'W1062'; Identifier: 'CVT_NARROWING_STRING_LOST'; Since: '6.0'),
    (Code: 'W1063'; Identifier: 'CVT_ACHAR_TO_WCHAR'; Since: '6.0'),
    (Code: 'W1064'; Identifier: 'CVT_WIDENING_STRING_LOST'; Since: '6.0'),
    // Win64 (XE2), unveränderliche Strings (XE3).
    (Code: 'W1066'; Identifier: 'LOST_EXTENDED_PRECISION'; Since: '9.0'),
    (Code: 'W1068'; Identifier: 'IMMUTABLE_STRINGS'; Since: '10.0'),
    // Verlustbehaftete implizite Umwandlungen; vorsichtig erst ab Delphi 11, davor {$WARNINGS OFF}.
    (Code: 'W1071'; Identifier: 'IMPLICIT_INTEGER_CAST_LOSS'; Since: '22.0'),
    (Code: 'W1072'; Identifier: 'IMPLICIT_CONVERSION_LOSS'; Since: '22.0'),
    // XML-Dokumentationskommentare.
    (Code: 'W1201'; Identifier: 'XML_WHITESPACE_NOT_ALLOWED'; Since: ''),
    (Code: 'W1202'; Identifier: 'XML_UNKNOWN_ENTITY'; Since: ''),
    (Code: 'W1203'; Identifier: 'XML_INVALID_NAME_START'; Since: ''),
    (Code: 'W1204'; Identifier: 'XML_INVALID_NAME'; Since: ''),
    (Code: 'W1205'; Identifier: 'XML_EXPECTED_CHARACTER'; Since: ''),
    (Code: 'W1206'; Identifier: 'XML_CREF_NO_RESOLVE'; Since: ''),
    (Code: 'W1207'; Identifier: 'XML_NO_PARM'; Since: ''),
    (Code: 'W1208'; Identifier: 'XML_NO_MATCHING_PARM'; Since: ''));

  // Ablaufanalyse am Ende der Routine: Wert nie benutzt (H2077), Schleife läuft nie (H2135), Variable nie
  // verwendet (H2164), Funktion ohne Ergebnis (W1035), Variable vielleicht nicht initialisiert (W1036),
  // Schleifenvariable danach undefiniert (W1037).
  RoutineWideCodes: array[0..5] of string = ('H2077', 'H2135', 'H2164', 'W1035', 'W1036', 'W1037');

function IndexOf(const ACode: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Table) do
    if SameText(Table[Index].Code, Trim(ACode)) then
      Exit(Index);
  Result := -1;
end;

function IsNumbered(const ACode: string; ALetter: Char): Boolean;
var
  Index: Integer;
begin
  Result := (Length(ACode) = 5) and (UpCase(ACode[1]) = ALetter);
  if Result then
    for Index := 2 to 5 do
      if not CharInSet(ACode[Index], ['0'..'9']) then
        Exit(False);
end;

class function TWarningCodes.KindOf(const ACode: string): TWarningCodeKind;
begin
  Result := TWarningCodeKind.None;
  if IsNumbered(Trim(ACode), 'H') then
    Result := TWarningCodeKind.Hint
  else if IsNumbered(Trim(ACode), 'W') then
    Result := TWarningCodeKind.Warning;
end;

class function TWarningCodes.Identifier(const ACode, AVersion: string): string;
var
  Index, Version: Integer;
begin
  Result := '';
  Index := IndexOf(ACode);
  if Index < 0 then
    Exit;
  Version := TLanguageFeatures.ParseVersion(AVersion);
  // Ohne gültige Version gilt die aktuelle: Dort kennt Delphi alle Bezeichner der Tabelle.
  if (Table[Index].Since <> '') and (Version >= 0) and
    (Version < TLanguageFeatures.ParseVersion(Table[Index].Since)) then
    Exit;
  Result := Table[Index].Identifier;
end;

class function TWarningCodes.Since(const ACode: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := IndexOf(ACode);
  if Index >= 0 then
    Result := Table[Index].Since;
end;

class function TWarningCodes.IsRoutineWide(const ACode: string): Boolean;
begin
  Result := MatchText(Trim(ACode), RoutineWideCodes);
end;

class function TWarningCodes.Codes: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Table));
  for Index := 0 to High(Table) do
    Result[Index] := Table[Index].Code;
end;

end.
