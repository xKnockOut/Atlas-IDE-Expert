unit Atlas.Core.Lsp.Contract;

// Werttypen, die der LSP-Client (TLspSession) liefert und die Features darüber verwenden (A-09): Probleme
// (Diagnosen, #398), Symbole der projektweiten Suche und Einträge der Typ- und Aufrufhierarchie (#400),
// Treffersicherheit einer Fundstelle (#1119), Ergebnis der Auswirkungsanalyse (#1120) und Bezeichner für
// Werte beim Debuggen (#508).
// Sie liegen im Lsp-Feature, weil die Protokollschicht unten liegt; Atlas.Core.Problems.Contract und
// Atlas.Core.Results.Model führen sie als Alias weiter. Positionen sind 0-basiert in UTF-16-Einheiten.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasProblemSeverity = (Error, Warning, Information, Hint);
  {$SCOPEDENUMS OFF}

  /// <summary>Weitere Stelle zu einer Meldung aus relatedInformation (#896), z. B. der uses-Eintrag einer Unit
  /// auf dem Pfad eines Unit-Zyklus: URI, Stelle (0-basiert) und Beschriftung.</summary>
  TAtlasProblemRelated = record
    Uri: string;
    Line: Integer;
    Character: Integer;
    Message: string;
  end;

  TAtlasProblem = record
  public const
    CompilerSource = 'dcc';
    /// <summary>Herkunft eines vom Build bestätigten Atlas-Befunds (#1024).</summary>
    ConfirmedSource = 'Atlas + dcc';
    /// <summary>Regel der Syntaxfehler des Servers (#1022); lässt sich nicht per Kommentar unterdrücken.</summary>
    SyntaxCode = 'syntax';
    /// <summary>Sprachmerkmal einer neueren Delphi-Version (#1126); ebenfalls ohne Unterdrückung per Kommentar.
    /// </summary>
    LanguageFeatureCode = 'language-feature';
    /// <summary>Regel der Unit-Zyklen (#64, #896): Pfad mit anklickbaren Units und „Graph zeigen“ im Hover.</summary>
    UsesCycleCode = 'uses-cycle';
    /// <summary>Zustände aus data.uses.state (#621).</summary>
    UsesUnused = 'unused';
    UsesInitialization = 'initialization';
    UsesAllowlist = 'allowlist';
    UsesImplementation = 'implementation';
  public
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    Severity: TAtlasProblemSeverity;
    /// <summary>Regel-ID bzw. Meldungsnummer (E2003); "syntax" bei Syntaxfehlern des Servers (#1022).</summary>
    Code: string;
    /// <summary>"Atlas" oder "dcc".</summary>
    Source: string;
    Message: string;
    /// <summary>Konfidenz eines Regeltreffers aus data.confidence ("high", "medium", "low", #144); sonst ''.</summary>
    Confidence: string;
    /// <summary>Kategorie und Gruppe der Regel aus dem Katalog (data.category, data.group, #909), z. B. "bug" und
    /// "find-bugs"; '' bei Compilermeldungen und Syntaxfehlern ohne Katalog.</summary>
    Category: string;
    Group: string;
    /// <summary>Titel der Schnellkorrektur (data.fix, #909); '' ohne.</summary>
    FixTitle: string;
    /// <summary>Zusatz für den Befund-Hover aus data.details, z. B. der durchsuchte Bereich projektweiter Regeln
    /// („Durchsucht: 214 Dateien und 37 Formulare der Projektgruppe“, #1102); '' ohne.</summary>
    Details: string;
    /// <summary>Inaktiver Bereich ({$IFDEF}); kein Problem im eigentlichen Sinn.</summary>
    Unnecessary: Boolean;
    /// <summary>Verwendung eines veralteten Symbols (Tag Deprecated, #38): durchgestrichen statt unterstrichen.
    /// </summary>
    Deprecated: Boolean;
    /// <summary>Zu einem inaktiven Bereich aus data.inactive (#615): Bedingung des Zweigs ("WIN64"),
    /// Zielplattform und Konfiguration des Servers; '' wenn unbekannt.</summary>
    InactiveCondition: string;
    InactivePlatform: string;
    InactiveConfig: string;
    /// <summary>uses-Eintrag aus data.uses (#621): Unit und Zustand (UsesUnused, UsesInitialization,
    /// UsesAllowlist, UsesImplementation); beides '' bei anderen Meldungen.</summary>
    UsesUnit: string;
    UsesState: string;
    /// <summary>Ungenutzte uses-Einträge der Datei, für „Alle ungenutzten entfernen“ im Hover; setzt der
    /// Controller, 0 sonst.</summary>
    UsesUnusedCount: Integer;
    /// <summary>Text geändert, seit die Meldung entstand: blass zeigen.</summary>
    Stale: Boolean;
    /// <summary>Compilermeldungen, denen die Regel entspricht (data.compilerCodes, #1024); nil ohne.</summary>
    CompilerCodes: TArray<string>;
    /// <summary>Der letzte Build meldet an derselben Zeile einen dieser Codes (#1024): „vom Compiler bestätigt“.
    /// Setzt der Problemspeicher; ConfirmedCode ist der Code des Compilers.</summary>
    Confirmed: Boolean;
    ConfirmedCode: string;
    /// <summary>Weitere Stellen aus relatedInformation (#896); im Befund-Hover anklickbar. nil ohne.</summary>
    Related: TArray<TAtlasProblemRelated>;
    function IsCompiler: Boolean;
    /// <summary>Text der Spalte „Compiler“ (#1024): bestätigter Code, Code einer Compilermeldung bzw. die Codes
    /// der Regel ("E2034, E2035"); '' ohne.</summary>
    function CompilerCodeText: string;
    /// <summary>AMessage ohne die Verweise „(wie E2034)“ bzw. „(wie E2034, E2035)“ (problems.showCompilerCode
    /// aus, #1024).</summary>
    class function WithoutCompilerCode(const AMessage: string): string; static;
    /// <summary>Hinweis zu einem uses-Eintrag (#621), kein Problem für Liste und Wellenlinie.</summary>
    function IsUses: Boolean;
    /// <summary>Liegt die Stelle (0-basiert) im Bereich? Leere Bereiche zählen als ein Zeichen.</summary>
    function Contains(ALine, ACharacter: Integer): Boolean;
    /// <summary>"Meldung (Code)" bzw. nur die Meldung.</summary>
    function Caption: string;
    /// <summary>Lässt sich der Befund per // lsp-ignore unterdrücken? Nicht bei Syntaxfehlern (#1022).</summary>
    function CanSuppress: Boolean;
    /// <summary>Hinweis zu einem inaktiven Bereich (#615): AConditionFormat mit der Bedingung (%s), dahinter
    /// ATargetFormat mit Plattform und Konfiguration (%s, %s; "?" für Unbekanntes), wenn eins bekannt ist.
    /// Ohne Bedingung AFallback.</summary>
    function InactiveHint(const AConditionFormat, ATargetFormat, AFallback: string): string;
    class function FromJson(const AItem: TJSONObject): TAtlasProblem; static;
    /// <summary>Alle Diagnosen einer LSP-Liste; Nicht-Objekte werden übersprungen.</summary>
    class function ListFromJson(const AItems: TJSONArray): TArray<TAtlasProblem>; static;
  end;

  TAtlasSymbol = record
    Name: string;
    /// <summary>Enthaltende Klasse oder Unit (containerName).</summary>
    Container: string;
    /// <summary>LSP SymbolKind.</summary>
    Kind: Integer;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  /// <summary>Treffersicherheit einer Fundstelle (#1119) aus atlasConfidence des Servers.</summary>
  TAtlasConfidence = record
    /// <summary>Erschlossen statt sicher: vor dem Umbenennen prüfen.</summary>
    Inferred: Boolean;
    /// <summary>Grund wie im LSP: "interface", "virtual", "ambiguous", "unresolved", "inactiveBranch", "text";
    /// '' bei sicheren Treffern.</summary>
    Reason: string;
    /// <summary>Erklärung des Servers für den Hinweis, etwa „Aufruf über ISpeicherbar.Speichern …“.</summary>
    Explanation: string;
    /// <summary>Aus dem Feld atlasConfidence von AItem; ohne das Feld sicher (ältere Server).</summary>
    class function FromJson(const AItem: TJSONValue): TAtlasConfidence; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Richtung einer Hierarchie: Aufrufer, Aufgerufene, Vorfahren, Nachfahren.</summary>
  TAtlasHierarchyDirection = (Incoming, Outgoing, Supertypes, Subtypes);
{$SCOPEDENUMS OFF}

  TAtlasHierarchyItem = record
    Name: string;
    Detail: string;
    /// <summary>LSP SymbolKind.</summary>
    Kind: Integer;
    FileName: string;
    /// <summary>Anfang des Namens (selectionRange), 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Der Eintrag als JSON, so wie ihn der Server für Folgeanfragen zurückhaben will.</summary>
    Raw: string;
    /// <summary>Eingehende Aufrufe (#1119): sicher oder erschlossen.</summary>
    Confidence: TAtlasConfidence;
    /// <summary>Aufruf über ein Interface bzw. eine virtuelle Methode (#1122): "interface", "virtual" oder ''
    /// (atlasDispatch des Servers).</summary>
    Dispatch: string;
    /// <summary>Umsetzungen, die der Aufruf erreichen kann; 0 ohne Dispatch.</summary>
    Implementations: Integer;
  end;

  /// <summary>Formularbindung einer betroffenen Stelle (#1120): Ereignis-Handler oder Komponentenname.</summary>
  TAtlasImpactForm = record
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Zeile der Formulardatei, z. B. "OnClick = Button1Click".</summary>
    Text: string;
  end;

  /// <summary>Betroffene Stelle der Auswirkungsanalyse (#1120).</summary>
  TAtlasImpactPlace = record
    /// <summary>Die Stelle als Routine, Deklaration oder Unit; Confidence aus atlasConfidence.</summary>
    Item: TAtlasHierarchyItem;
    /// <summary>1 = direkt, ab 2 indirekt.</summary>
    Level: Integer;
    /// <summary>"call", "reference", "override", "baseMethod", "interfaceMethod", "implementation".</summary>
    Edge: string;
    /// <summary>Index der verursachenden Stelle in TAtlasImpact.Places; -1 = das Symbol.</summary>
    Cause: Integer;
    /// <summary>Erste Verwendung der Ursache in der Stelle (Ziel des Doppelklicks); ohne: die Stelle selbst.</summary>
    UseLine: Integer;
    UseCharacter: Integer;
    /// <summary>Zahl der Verwendungen der Ursache in der Stelle.</summary>
    UseCount: Integer;
    Forms: TArray<TAtlasImpactForm>;
    /// <summary>Unit-Ebene (initialization): nicht weiter verfolgt.</summary>
    Terminal: Boolean;
    /// <summary>Name des Tests (Unit.Fixture.Methode), wenn die Stelle einer ist; sonst ''.</summary>
    Test: string;
  end;

  TAtlasImpactTest = record
    /// <summary>Unit.Fixture.Methode.</summary>
    Name: string;
    /// <summary>Namen für den Testlauf (--run), bei [TestCase] je Fall.</summary>
    RunNames: TArray<string>;
    FileName: string;
    Line: Integer;
    Level: Integer;
  end;

  /// <summary>Antwort von atlas/impact (#1120).</summary>
  TAtlasImpact = record
    Symbol: TAtlasHierarchyItem;
    SymbolForms: TArray<TAtlasImpactForm>;
    Depth: Integer;
    Places: TArray<TAtlasImpactPlace>;
    Tests: TArray<TAtlasImpactTest>;
    /// <summary>Erreichte Grenzen: Tiefe, Anzahl, Zeit.</summary>
    DepthReached: Boolean;
    CountReached: Boolean;
    TimeReached: Boolean;
    /// <summary>Stellen der letzten Ebene, die nicht weiter verfolgt wurden.</summary>
    Unexpanded: Integer;
    MaxPlaces: Integer;
    TimeoutMs: Integer;
    /// <summary>Indizes der Stellen, deren Ursache ACause ist, in Reihenfolge.</summary>
    function Children(ACause: Integer): TArray<Integer>;
    /// <summary>Zahl der Stellen auf Ebene ALevel bzw. ab Ebene ALevel.</summary>
    function LevelCount(ALevel: Integer): Integer;
    function CountFrom(ALevel: Integer): Integer;
    /// <summary>Alle Namen für den Testlauf ohne Doppelte.</summary>
    function RunNames: TArray<string>;
    /// <summary>Gibt es ein Ergebnis (Symbol gefunden)?</summary>
    function Found: Boolean;
  end;

  /// <summary>Bezeichner aus textDocument/inlineValue (#508); Zeile und Spalte 0-basiert.</summary>
  TAtlasInlineValueRef = record
    Line: Integer;
    Character: Integer;
    Name: string;
    /// <summary>Deklarierter Typ ('' = unbekannt), für die Darstellung.</summary>
    TypeName: string;
    class function Create(ALine, ACharacter: Integer; const AName, ATypeName: string): TAtlasInlineValueRef; static;
  end;

  TAtlasInlineValueRefs = TArray<TAtlasInlineValueRef>;

implementation

{ TAtlasConfidence }

class function TAtlasConfidence.FromJson(const AItem: TJSONValue): TAtlasConfidence;
var
  Value: TJSONValue;
begin
  Result := Default(TAtlasConfidence);
  if not (AItem is TJSONObject) then
    Exit;
  Value := TJSONObject(AItem).GetValue('atlasConfidence');
  if not (Value is TJSONObject) then
    Exit;
  Result.Inferred := TJSONObject(Value).GetValue<string>('level', '') = 'inferred';
  if Result.Inferred then
  begin
    Result.Reason := TJSONObject(Value).GetValue<string>('reason', '');
    Result.Explanation := TJSONObject(Value).GetValue<string>('detail', '');
  end;
end;

{ TAtlasImpact }

function TAtlasImpact.Children(ACause: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(Places) do
    if Places[Index].Cause = ACause then
      Result := Result + [Index];
end;

function TAtlasImpact.LevelCount(ALevel: Integer): Integer;
var
  Place: TAtlasImpactPlace;
begin
  Result := 0;
  for Place in Places do
    if Place.Level = ALevel then
      Inc(Result);
end;

function TAtlasImpact.CountFrom(ALevel: Integer): Integer;
var
  Place: TAtlasImpactPlace;
begin
  Result := 0;
  for Place in Places do
    if Place.Level >= ALevel then
      Inc(Result);
end;

function TAtlasImpact.RunNames: TArray<string>;
var
  Test: TAtlasImpactTest;
  Name, Seen: string;
begin
  Result := nil;
  Seen := '|';
  for Test in Tests do
    for Name in Test.RunNames do
      if Pos('|' + UpperCase(Name) + '|', Seen) = 0 then
      begin
        Seen := Seen + UpperCase(Name) + '|';
        Result := Result + [Name];
      end;
end;

function TAtlasImpact.Found: Boolean;
begin
  Result := Symbol.Name <> '';
end;

{ TAtlasProblem }

function TAtlasProblem.IsCompiler: Boolean;
begin
  Result := SameText(Source, CompilerSource);
end;

class function TAtlasProblem.WithoutCompilerCode(const AMessage: string): string;
const
  Opening = ' (wie ';
var
  Start, Stop, Index: Integer;
  Inner: string;
  Codes: Boolean;
begin
  Result := AMessage;
  Start := Pos(Opening, Result);
  while Start > 0 do
  begin
    Stop := Pos(')', Copy(Result, Start, MaxInt)) + Start - 1;
    if Stop < Start then
      Break;
    Inner := Copy(Result, Start + Length(Opening), Stop - Start - Length(Opening));
    // Nur Codes wie E2034, W1000–W1007 und Trenner; anderer Text in Klammern bleibt.
    Codes := Inner <> '';
    for Index := 1 to Length(Inner) do
      if not CharInSet(Inner[Index], ['A'..'Z', '0'..'9', ',', ' ']) and (Inner[Index] <> #$2013) then
        Codes := False;
    if Codes then
    begin
      Delete(Result, Start, Stop - Start + 1);
      Start := Pos(Opening, Result);
    end
    else
    begin
      Index := Pos(Opening, Copy(Result, Stop + 1, MaxInt));
      if Index = 0 then
        Break;
      Start := Stop + Index;
    end;
  end;
end;

function TAtlasProblem.CompilerCodeText: string;
begin
  if Confirmed then
    Result := ConfirmedCode
  else if IsCompiler then
    Result := Code
  else
    Result := string.Join(', ', CompilerCodes);
end;

function TAtlasProblem.IsUses: Boolean;
begin
  Result := UsesState <> '';
end;

function TAtlasProblem.Contains(ALine, ACharacter: Integer): Boolean;
var
  Last: Integer;
begin
  if (ALine < StartLine) or (ALine > EndLine) then
    Exit(False);
  Last := EndCharacter;
  if (StartLine = EndLine) and (EndCharacter <= StartCharacter) then
    Last := StartCharacter + 1;
  Result := ((ALine > StartLine) or (ACharacter >= StartCharacter)) and ((ALine < EndLine) or (ACharacter <= Last));
end;

function TAtlasProblem.Caption: string;
begin
  if Code = '' then
    Result := Message
  else
    Result := Format('%s (%s)', [Message, Code]);
end;

function TAtlasProblem.CanSuppress: Boolean;
begin
  Result := (Code <> '') and not SameText(Code, SyntaxCode) and not SameText(Code, LanguageFeatureCode);
end;

function TAtlasProblem.InactiveHint(const AConditionFormat, ATargetFormat, AFallback: string): string;
var
  Platform, Config: string;
begin
  if InactiveCondition = '' then
    Exit(AFallback);
  Result := Format(AConditionFormat, [InactiveCondition]);
  if (InactivePlatform = '') and (InactiveConfig = '') then
    Exit;
  Platform := InactivePlatform;
  Config := InactiveConfig;
  if Platform = '' then
    Platform := '?';
  if Config = '' then
    Config := '?';
  Result := Result + Format(ATargetFormat, [Platform, Config]);
end;

class function TAtlasProblem.FromJson(const AItem: TJSONObject): TAtlasProblem;
var
  Tags, CodeValue, Data, Inactive, UsesData, Codes, RelatedItems: TJSONValue;
  Tag, Item: TJSONValue;
  Related: TAtlasProblemRelated;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := AItem.GetValue<Integer>('range.start.line', 0);
  Result.StartCharacter := AItem.GetValue<Integer>('range.start.character', 0);
  Result.EndLine := AItem.GetValue<Integer>('range.end.line', Result.StartLine);
  Result.EndCharacter := AItem.GetValue<Integer>('range.end.character', Result.StartCharacter);
  case AItem.GetValue<Integer>('severity', 1) of
    2:
      Result.Severity := TAtlasProblemSeverity.Warning;
    3:
      Result.Severity := TAtlasProblemSeverity.Information;
    4:
      Result.Severity := TAtlasProblemSeverity.Hint;
  else
    Result.Severity := TAtlasProblemSeverity.Error;
  end;
  CodeValue := AItem.GetValue('code');
  if CodeValue is TJSONString then
    Result.Code := TJSONString(CodeValue).Value
  else if CodeValue is TJSONNumber then
    Result.Code := TJSONNumber(CodeValue).ToString;
  Result.Source := AItem.GetValue<string>('source', '');
  Result.Message := AItem.GetValue<string>('message', '');
  Data := AItem.GetValue('data');
  if Data is TJSONObject then
  begin
    Result.Confidence := TJSONObject(Data).GetValue<string>('confidence', '');
    Result.Category := TJSONObject(Data).GetValue<string>('category', '');
    Result.Group := TJSONObject(Data).GetValue<string>('group', '');
    Result.FixTitle := TJSONObject(Data).GetValue<string>('fix', '');
    Codes := TJSONObject(Data).GetValue('compilerCodes');
    if Codes is TJSONArray then
      for Item in TJSONArray(Codes) do
        if Item is TJSONString then
          Result.CompilerCodes := Result.CompilerCodes + [TJSONString(Item).Value];
    Result.Details := TJSONObject(Data).GetValue<string>('details', '');
    Inactive := TJSONObject(Data).GetValue('inactive');
    if Inactive is TJSONObject then
    begin
      Result.InactiveCondition := TJSONObject(Inactive).GetValue<string>('condition', '');
      Result.InactivePlatform := TJSONObject(Inactive).GetValue<string>('platform', '');
      Result.InactiveConfig := TJSONObject(Inactive).GetValue<string>('config', '');
    end;
    UsesData := TJSONObject(Data).GetValue('uses');
    if UsesData is TJSONObject then
    begin
      Result.UsesUnit := TJSONObject(UsesData).GetValue<string>('unit', '');
      Result.UsesState := TJSONObject(UsesData).GetValue<string>('state', '');
    end;
  end;
  RelatedItems := AItem.GetValue('relatedInformation');
  if RelatedItems is TJSONArray then
    for Item in TJSONArray(RelatedItems) do
      if Item is TJSONObject then
      begin
        Related.Uri := TJSONObject(Item).GetValue<string>('location.uri', '');
        Related.Line := TJSONObject(Item).GetValue<Integer>('location.range.start.line', 0);
        Related.Character := TJSONObject(Item).GetValue<Integer>('location.range.start.character', 0);
        Related.Message := TJSONObject(Item).GetValue<string>('message', '');
        if Related.Uri <> '' then
          Result.Related := Result.Related + [Related];
      end;
  Tags := AItem.GetValue('tags');
  if Tags is TJSONArray then
    for Tag in TJSONArray(Tags) do
      if Tag is TJSONNumber then
        case TJSONNumber(Tag).AsInt of
          1:
            Result.Unnecessary := True;
          2:
            Result.Deprecated := True;
        end;
end;

class function TAtlasProblem.ListFromJson(const AItems: TJSONArray): TArray<TAtlasProblem>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if AItems = nil then
    Exit;
  for Item in AItems do
    if Item is TJSONObject then
      Result := Result + [FromJson(TJSONObject(Item))];
end;

{ TAtlasInlineValueRef }

class function TAtlasInlineValueRef.Create(ALine, ACharacter: Integer; const AName,
  ATypeName: string): TAtlasInlineValueRef;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Name := AName;
  Result.TypeName := ATypeName;
end;

end.
