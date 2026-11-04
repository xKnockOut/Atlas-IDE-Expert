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
  Atlas.Common.Lsp.DocWiki;

function D(const AName, ALetter, AText, ATopic: string): TDirectiveInfo;
begin
  Result.Name := AName;
  Result.Letter := ALetter;
  Result.Text := AText;
  Result.Topic := ATopic;
end;

var
  Directives: TArray<TDirectiveInfo>;

/// <summary>Direktiven A bis L.</summary>
procedure InitDirectivesToL;
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
      'Local_symbol_information_(Delphi)')];
end;

/// <summary>Direktiven ab LONGSTRINGS.</summary>
procedure InitDirectivesFromL;
begin
  Directives := Directives + [
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

procedure InitDirectives;
begin
  InitDirectivesToL;
  InitDirectivesFromL;
end;

{ TCompilerDirectives }

class function TCompilerDirectives.All: TArray<TDirectiveInfo>;
begin
  Result := Copy(Directives);
end;

class function TCompilerDirectives.Warnings: TArray<string>;
begin
  Result := TDirectiveNames.Warnings;
end;

class function TCompilerDirectives.Find(const AName: string; out AInfo: TDirectiveInfo): Boolean;
var
  Info: TDirectiveInfo;
begin
  for Info in Directives do
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
    Result := Result + #10#10 + 'Hier: ' + AState;
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
  for mInfo in Directives do
  begin
    // I, L und R sind mit Dateinamen andere Direktiven; mit +/- sind es die Schalter.
    if SameText(mInfo.Letter, APart[1]) and not MatchText(mInfo.Name, ['INCLUDE', 'LINK', 'RESOURCE']) then
    begin
      Exit(DescribeInfo(mInfo, AVersion, IfThen(APart[2] = '+', 'eingeschaltet', 'ausgeschaltet')));
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
    Result := Result + #10#10 + Format('Warnung `%s`: %s', [UpperCase(mWarning),
      Trim(Copy(ARest, Length(mWarning) + 1, MaxInt))]);
  end;
end;

/// <summary>Zustand nach dem Namen: ON/+ eingeschaltet, OFF/- ausgeschaltet, sonst ''.</summary>
function StateOf(const ARest: string): string;
begin
  if MatchText(ARest, ['ON', '+']) then
  begin
    Result := 'eingeschaltet';
  end
  else if MatchText(ARest, ['OFF', '-']) then
  begin
    Result := 'ausgeschaltet';
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
  for Info in Directives do
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
  InitDirectives;

end.
