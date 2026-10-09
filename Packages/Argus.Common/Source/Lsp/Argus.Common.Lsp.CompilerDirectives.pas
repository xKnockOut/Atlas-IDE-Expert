unit Argus.Common.Lsp.CompilerDirectives;

// Sprachreferenz für Compiler-Direktiven (#102, Teil 1): Kurztext und
// DocWiki-Link je Direktive, Schalterbuchstaben ({$R+} = RANGECHECKS) und die
// Bezeichner für {$WARN}. Grundlage für Hover und Vervollständigung in
// Direktiven; #187 soll dieselbe Tabelle für Schlüsselwörter nutzen.
//
// Links folgen dem Schema https://docwiki.embarcadero.com/RADStudio/<Release>/en/<Seite>
// mit dem Release-Namen aus TDocWiki (Delphi 12 = Athens, Delphi 13 = Florence).
// Direktiven und {$WARN}-Bezeichner sind in Delphi 12 und 13 gleich; eine
// Unterscheidung je Version kommt dazu, sobald sie auseinanderlaufen.

interface

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree;

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
  Argus.Common.Pascal.Contract,
  Argus.Common.Lsp.DocWiki;

function D(const AName, ALetter, AText, ATopic: string): TDirectiveInfo;
begin
  Result.Name := AName;
  Result.Letter := ALetter;
  Result.Text := AText;
  Result.Topic := ATopic;
end;

var
  Directives: TArray<TDirectiveInfo>;

procedure InitDirectives;
begin
  Directives := [
    D('ALIGN', 'A', 'Ausrichtung der Felder in Records und Klassen (1, 2, 4, 8, 16 oder ON/OFF).', 'Align_fields_(Delphi)'),
    D('APPTYPE', '', 'Art der Anwendung: CONSOLE oder GUI.', 'Application_type_(Delphi)'),
    D('ASSERTIONS', 'C', 'Assert-Aufrufe einkompilieren (+) oder weglassen (-).', 'Assert_directives_(Delphi)'),
    D('BOOLEVAL', 'B', 'Boolesche Ausdrücke vollständig auswerten (+) statt Kurzschlussauswertung (-).',
      'Boolean_short-circuit_evaluation_(Delphi_compiler_directive)'),
    D('CODEALIGN', '', 'Ausrichtung des erzeugten Codes in Byte.', 'Code_align_(Delphi)'),
    D('DEBUGINFO', 'D', 'Debug-Informationen erzeugen.', 'Debug_information_(Delphi)'),
    D('DEFINE', '', 'Bedingtes Symbol definieren.', 'DEFINE_directive_(Delphi)'),
    D('DENYPACKAGEUNIT', '', 'Unit darf nicht in ein Package aufgenommen werden.', 'Deny_package_unit_(Delphi)'),
    D('DESCRIPTION', '', 'Beschreibungstext eines Packages.', 'Description_(Delphi)'),
    D('DESIGNONLY', '', 'Package nur für die Entwurfszeit in der IDE.', 'Design-time_only_(Delphi)'),
    D('ELSE', '', 'Alternative einer bedingten Kompilierung.', 'ELSE_(Delphi)'),
    D('ELSEIF', '', 'Weitere Bedingung einer {$IF}-Kette.', 'ELSEIF_(Delphi)'),
    D('ENDIF', '', 'Ende einer bedingten Kompilierung.', 'ENDIF_directive_(Delphi)'),
    D('ENDREGION', '', 'Ende eines einklappbaren Bereichs.', 'Regions'),
    D('EXTENDEDSYNTAX', 'X', 'Erweiterte Syntax: Funktionsaufruf als Anweisung, Result, PChar-Arithmetik.',
      'Extended_syntax_(Delphi)'),
    D('HIGHCHARUNICODE', '', 'Zeichenliterale #$80..#$FF als Unicode statt als ANSI auslegen.',
      'HIGHCHARUNICODE_directive_(Delphi)'),
    D('HINTS', '', 'Hinweise des Compilers ein- oder ausschalten.', 'Hints_(Delphi)'),
    D('HPPEMIT', '', 'Zeile in die erzeugte C++-Headerdatei schreiben.', 'HPPEMIT_directive_(Delphi)'),
    D('IF', '', 'Bedingte Kompilierung mit Ausdruck, z. B. Defined(X) oder CompilerVersion >= 36.',
      'IF_directive_(Delphi)'),
    D('IFDEF', '', 'Kompilieren, wenn das bedingte Symbol definiert ist.', 'IFDEF_directive_(Delphi)'),
    D('IFEND', '', 'Ende einer {$IF}-Bedingung (älterer Stil, sonst {$ENDIF}).', 'IFEND_directive_(Delphi)'),
    D('IFNDEF', '', 'Kompilieren, wenn das bedingte Symbol nicht definiert ist.', 'IFNDEF_directive_(Delphi)'),
    D('IFOPT', '', 'Kompilieren, wenn ein Schalter gesetzt ist, z. B. {$IFOPT R+}.', 'IFOPT_directive_(Delphi)'),
    D('IMAGEBASE', '', 'Ladeadresse einer DLL oder Anwendung.', 'Image_base_address'),
    D('IMPLICITBUILD', '', 'Package bei Änderungen automatisch neu erzeugen.', 'Implicit_Build_(Delphi)'),
    D('IMPORTEDDATA', 'G', 'Zugriff auf Variablen aus anderen Packages erlauben.', 'Imported_data_(Delphi)'),
    D('INCLUDE', 'I', 'Datei an dieser Stelle einfügen ({$I Datei}).', 'Include_file_(Delphi)'),
    D('IOCHECKS', 'I', 'Ein-/Ausgabefehler als Exception melden ({$I+}).', 'Input_output_checking_(Delphi)'),
    D('LEGACYIFEND', '', '{$IF} nur mit {$IFEND} schließen (wie vor Delphi XE4).', 'Legacy_IFEND_(Delphi)'),
    D('LINK', 'L', 'Objektdatei einbinden ({$L Datei}).', 'Link_object_file_(Delphi)'),
    D('LOCALSYMBOLS', 'L', 'Informationen über lokale Symbole für den Debugger ({$L+}).',
      'Local_symbol_information_(Delphi)'),
    D('LONGSTRINGS', 'H', 'string bedeutet einen langen String statt ShortString.', 'Long_strings_(Delphi)'),
    D('MESSAGE', '', 'Eigene Meldung beim Kompilieren ausgeben (HINT, WARN, ERROR, FATAL).',
      'MESSAGE_directive_(Delphi)'),
    D('METHODINFO', '', 'Erweiterte RTTI für Methoden erzeugen.', 'METHODINFO_directive_(Delphi)'),
    D('MINENUMSIZE', 'Z', 'Mindestgröße von Aufzählungstypen in Byte.', 'Minimum_enumeration_size_(Delphi)'),
    D('OPENSTRINGS', 'P', 'String-Parameter als offene Strings behandeln.', 'Open_String_Parameters_(Delphi)'),
    D('OPTIMIZATION', 'O', 'Code optimieren.', 'Optimization_(Delphi)'),
    D('OVERFLOWCHECKS', 'Q', 'Überlaufprüfung bei Ganzzahlarithmetik.', 'Overflow_checking_(Delphi)'),
    D('POINTERMATH', '', 'Zeigerarithmetik für typisierte Zeiger erlauben.', 'Pointer_Math_(Delphi)'),
    D('RANGECHECKS', 'R', 'Bereichsprüfung für Array-Indizes, Teilbereiche und Strings.', 'Range_checking'),
    D('REALCOMPATIBILITY', '', 'Real als 6-Byte-Typ Real48 behandeln.', 'Real48_compatibility_(Delphi)'),
    D('REFERENCEINFO', 'Y', 'Symbol- und Querverweisinformationen erzeugen.',
      'Symbol_declaration_and_cross-reference_information_(Delphi)'),
    D('REGION', '', 'Anfang eines einklappbaren Bereichs.', 'Regions'),
    D('RESOURCE', 'R', 'Ressourcendatei einbinden ({$R Datei.res}).', 'Resource_file_(Delphi)'),
    D('RTTI', '', 'Umfang der erweiterten RTTI je Sichtbarkeit festlegen.', 'RTTI_directive_(Delphi)'),
    D('RUNONLY', '', 'Package nur zur Laufzeit, nicht in der IDE installierbar.', 'Run-Time_only_(Delphi)'),
    D('SAFEDIVIDE', 'U', 'Pentium-sichere Gleitkommadivision (historisch).', 'Pentium-safe_FDIV_operations_(Delphi)'),
    D('SCOPEDENUMS', '', 'Aufzählungswerte nur mit Typnamen ansprechen (TFarbe.Rot).', 'Scoped_Enums_(Delphi)'),
    D('STACKFRAMES', 'W', 'Immer Stackframes erzeugen.', 'Stack_frames_(Delphi)'),
    D('STRONGLINKTYPES', '', 'Alle Typen mit RTTI in die Anwendung linken.', 'Strong_link_types_(Delphi)'),
    D('TEXTBLOCK', '', 'Zeilenende und Einrückung mehrzeiliger String-Literale festlegen.',
      'Text_block_directive_(Delphi)'),
    D('TYPEDADDRESS', 'T', 'Der @-Operator liefert typisierte Zeiger.', 'Type-checked_pointers_(Delphi)'),
    D('TYPEINFO', 'M', 'RTTI für published-Abschnitte erzeugen.', 'Run-Time_Type_Information_(Delphi)'),
    D('UNDEF', '', 'Bedingtes Symbol aufheben.', 'UNDEF_directive_(Delphi)'),
    D('VARSTRINGCHECKS', 'V', 'Strenge Prüfung von ShortString-var-Parametern.', 'Var-string_checking_(Delphi)'),
    D('WARN', '', 'Einzelne Warnung ein- oder ausschalten oder zum Fehler machen ({$WARN BEZEICHNER OFF}).',
      'Warning_messages_(Delphi)'),
    D('WARNINGS', '', 'Warnungen des Compilers ein- oder ausschalten.', 'Warnings_(Delphi)'),
    D('WEAKPACKAGEUNIT', '', 'Unit schwach in ein Package aufnehmen.', 'Weak_packaging'),
    D('WRITEABLECONST', 'J', 'Typisierte Konstanten beschreibbar machen.', 'Writeable_typed_constants_(Delphi)'),
    D('ZEROBASEDSTRINGS', '', 'String-Indizes beginnen bei 0.', 'Zero-based_strings_(Delphi)')];
end;

const
  WarningNames: array[0..73] of string = (
    'ASG_TO_TYPED_CONST', 'BAD_GLOBAL_SYMBOL', 'BOUNDS_ERROR', 'CASE_LABEL_RANGE', 'COMBINING_SIGNED_UNSIGNED',
    'COMPARING_SIGNED_UNSIGNED', 'COMPARISON_FALSE', 'COMPARISON_TRUE', 'CONSTRUCTING_ABSTRACT',
    'CVT_ACHAR_TO_WCHAR', 'CVT_NARROWING_STRING_LOST', 'CVT_WCHAR_TO_ACHAR', 'CVT_WIDENING_STRING_LOST',
    'DUPLICATE_CTOR_DTOR', 'DUPLICATES_IGNORED', 'EXPLICIT_STRING_CAST', 'EXPLICIT_STRING_CAST_LOSS',
    'FILE_OPEN', 'FILE_OPEN_UNITSRC', 'FOR_LOOP_VAR_UNDEF', 'FOR_LOOP_VAR_VARPAR', 'FOR_VARIABLE', 'GARBAGE',
    'HIDDEN_VIRTUAL', 'HIDING_MEMBER', 'HPPEMIT_IGNORED', 'HRESULT_COMPAT', 'IMAGEBASE_MULTIPLE',
    'IMMUTABLE_STRINGS', 'IMPLICIT_IMPORT', 'IMPLICIT_STRING_CAST', 'IMPLICIT_STRING_CAST_LOSS',
    'IMPLICIT_VARIANTS', 'INVALID_DIRECTIVE', 'LOCAL_PINVOKE', 'LOCALE_TO_UNICODE', 'MESSAGE_DIRECTIVE',
    'NO_CFG_FILE_FOUND', 'NO_RETVAL', 'NON_PORTABLE_TYPECAST', 'OPTION_TRUNCATED', 'PACKAGE_NO_LINK',
    'PACKAGED_THREADVAR', 'PRIVATE_PROPACCESSOR', 'RLINK_WARNING', 'STRING_CONST_TRUNCED', 'SUSPICIOUS_TYPECAST',
    'SYMBOL_DEPRECATED', 'SYMBOL_EXPERIMENTAL', 'SYMBOL_LIBRARY', 'SYMBOL_PLATFORM', 'TYPED_CONST_VARPAR',
    'TYPEINFO_IMPLICITLY_ADDED', 'UNICODE_TO_LOCALE', 'UNIT_DEPRECATED', 'UNIT_EXPERIMENTAL', 'UNIT_INIT_SEQ',
    'UNIT_LIBRARY', 'UNIT_NAME_MISMATCH', 'UNIT_PLATFORM', 'UNSAFE_CAST', 'UNSAFE_CODE', 'UNSAFE_TYPE',
    'UNSUPPORTED_CONSTRUCT', 'USE_BEFORE_DEF', 'WIDECHAR_REDUCED', 'XML_CREF_NO_RESOLVE', 'XML_EXPECTED_CHARACTER',
    'XML_INVALID_NAME', 'XML_INVALID_NAME_START', 'XML_NO_MATCHING_PARM', 'XML_NO_PARM', 'XML_UNKNOWN_ENTITY',
    'XML_WHITESPACE_NOT_ALLOWED');

{ TCompilerDirectives }

class function TCompilerDirectives.All: TArray<TDirectiveInfo>;
begin
  Result := Copy(Directives);
end;

class function TCompilerDirectives.Warnings: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(WarningNames));
  for Index := 0 to High(WarningNames) do
    Result[Index] := WarningNames[Index];
end;

class function TCompilerDirectives.Find(const AName: string; out AInfo: TDirectiveInfo): Boolean;
var
  Info: TDirectiveInfo;
begin
  for Info in Directives do
    if SameText(Info.Name, AName) or ((Length(AName) = 1) and SameText(Info.Letter, AName)) then
    begin
      AInfo := Info;
      Exit(True);
    end;
  Result := False;
end;

class function TCompilerDirectives.Url(const ADelphiVersion, ATopic: string): string;
begin
  Result := BaseUri + TDocWiki.ReleaseName(ADelphiVersion) + '/en/' + ATopic;
end;

/// <summary>Inhalt der Direktive ohne "{$" bzw. "(*$" und die schließende Klammer.</summary>
function Body(const ADirective: string): string;
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

/// <summary>Führende Buchstaben (Name der Direktive).</summary>
function LeadingName(const AText: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_']) do
    Inc(Index);
  Result := Copy(AText, 1, Index - 1);
end;

function DescribeInfo(const AInfo: TDirectiveInfo; const AVersion, AState: string): string;
begin
  Result := '**{$' + AInfo.Name + '}**';
  if AInfo.Letter <> '' then
    Result := Result + ' (**{$' + AInfo.Letter + '}**)';
  Result := Result + #10#10 + AInfo.Text;
  if AState <> '' then
    Result := Result + #10#10 + 'Hier: ' + AState;
  Result := Result + #10#10 + '[DocWiki](' + TCompilerDirectives.Url(AVersion, AInfo.Topic) + ')';
end;

class function TCompilerDirectives.Describe(const ADirective, ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  Text, Name, Rest, Part, Value: string;
  Info: TDirectiveInfo;
  Parts: TArray<string>;
  Start, Index: Integer;
begin
  AMarkdown := '';
  Text := Body(ADirective);
  Name := LeadingName(Text);
  Rest := Trim(Copy(Text, Length(Name) + 1, MaxInt));
  if Name = '' then
    Exit(False);
  // Kurzschalter, auch mehrere: {$R+,Q-}
  if (Length(Name) = 1) and (Rest <> '') and CharInSet(Rest[1], ['+', '-']) then
  begin
    Parts := nil;
    Start := 1;
    for Index := 1 to Length(Text) + 1 do
      if (Index > Length(Text)) or (Text[Index] = ',') then
      begin
        Parts := Parts + [Trim(Copy(Text, Start, Index - Start))];
        Start := Index + 1;
      end;
    for Part in Parts do
      if (Length(Part) = 2) and CharInSet(Part[2], ['+', '-']) then
      begin
        // I, L und R sind mit Dateinamen andere Direktiven; mit +/- sind es die Schalter.
        Value := IfThen(Part[2] = '+', 'eingeschaltet', 'ausgeschaltet');
        for Info in Directives do
          if SameText(Info.Letter, Part[1]) and not MatchText(Info.Name, ['INCLUDE', 'LINK', 'RESOURCE']) then
          begin
            if AMarkdown <> '' then
              AMarkdown := AMarkdown + #10#10'---'#10#10;
            AMarkdown := AMarkdown + DescribeInfo(Info, ADelphiVersion, Value);
            Break;
          end;
      end;
    Exit(AMarkdown <> '');
  end;
  // {$I Datei}, {$L Datei}, {$R Datei}: Dateidirektiven
  if (Length(Name) = 1) and MatchText(Name, ['I', 'L', 'R']) then
  begin
    case UpCase(Name[1]) of
      'I': Name := 'INCLUDE';
      'L': Name := 'LINK';
    else
      Name := 'RESOURCE';
    end;
  end;
  if not Find(Name, Info) then
    Exit(False);
  if SameText(Info.Name, 'WARN') then
  begin
    Value := LeadingName(Rest);
    AMarkdown := DescribeInfo(Info, ADelphiVersion, '');
    if MatchText(Value, WarningNames) then
      AMarkdown := AMarkdown + #10#10 + Format('Warnung `%s`: %s', [UpperCase(Value),
        Trim(Copy(Rest, Length(Value) + 1, MaxInt))]);
    Exit(True);
  end;
  if MatchText(Rest, ['ON', '+']) then
    Value := 'eingeschaltet'
  else if MatchText(Rest, ['OFF', '-']) then
    Value := 'ausgeschaltet'
  else
    Value := '';
  AMarkdown := DescribeInfo(Info, ADelphiVersion, Value);
  Result := True;
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
    Open := PosEx('{$', ALineBeforeCursor, Open + 1);
  if (Open = 0) or (PosEx('}', ALineBeforeCursor, Open) > 0) then
    Exit(False);
  Inner := Copy(ALineBeforeCursor, Open + 2, MaxInt);
  if StartsText('WARN ', Inner) then
  begin
    // Nur der Bezeichner direkt nach WARN, nicht ON/OFF dahinter.
    if Pos(' ', Trim(Copy(Inner, 6, MaxInt))) > 0 then
      Exit(False);
    AIsWarning := True;
    ANames := Warnings;
    Exit(True);
  end;
  // Nur solange der Name getippt wird.
  if LeadingName(Inner) <> Inner then
    Exit(False);
  for Info in Directives do
    ANames := ANames + [Info.Name];
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
    Exit(False);
  for Token in ATree.Tokens do
  begin
    AfterStart := (Token.StartPos.Line < APosition.Line) or ((Token.StartPos.Line = APosition.Line) and
      (Token.StartPos.Character <= APosition.Character));
    BeforeEnd := (Token.EndPos.Line > APosition.Line) or ((Token.EndPos.Line = APosition.Line) and
      (Token.EndPos.Character > APosition.Character));
    if AfterStart and BeforeEnd then
      Exit((Token.Kind = TPascalTokenKind.Directive) and Describe(Token.Text, ADelphiVersion, AMarkdown));
  end;
  Result := False;
end;

initialization
  InitDirectives;

end.
