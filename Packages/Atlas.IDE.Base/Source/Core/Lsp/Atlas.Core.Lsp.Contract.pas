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
    cCompilerSource = 'dcc';
    /// <summary>Herkunft eines vom Build bestätigten Atlas-Befunds (#1024).</summary>
    cConfirmedSource = 'Atlas + dcc';
    /// <summary>Regel der Syntaxfehler des Servers (#1022); lässt sich nicht per Kommentar unterdrücken.</summary>
    cSyntaxCode = 'syntax';
    /// <summary>Sprachmerkmal einer neueren Delphi-Version (#1126); ebenfalls ohne Unterdrückung per Kommentar.
    /// </summary>
    cLanguageFeatureCode = 'language-feature';
    /// <summary>Regel der Unit-Zyklen (#64, #896): Pfad mit anklickbaren Units und „Graph zeigen“ im Hover.</summary>
    cUsesCycleCode = 'uses-cycle';
    /// <summary>Zustände aus data.uses.state (#621).</summary>
    cUsesUnused = 'unused';
    cUsesInitialization = 'initialization';
    cUsesAllowlist = 'allowlist';
    cUsesImplementation = 'implementation';
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

  /// <summary>Betroffener Test aus atlas/affectedTests (#1353).</summary>
  TAtlasAffectedTest = record
    /// <summary>Unit.Fixture.Methode bzw. Unit.Fixture für die ganze Fixture.</summary>
    Name: string;
    /// <summary>Namen für den Testlauf (--run).</summary>
    RunNames: TArray<string>;
    FileName: string;
    Line: Integer;
    /// <summary>Gründe als Text: Änderung → Weg, „(erschlossen)“ bei unsicheren Schritten.</summary>
    Reasons: TArray<string>;
  end;

  /// <summary>Antwort von atlas/affectedTests (#1353).</summary>
  TAtlasAffectedTests = record
    /// <summary>Basis des Vergleichs (Ref bzw. Revision).</summary>
    Base: string;
    Depth: Integer;
    /// <summary>Alle Tests nötig (Grund in AllReason): Projektdatei geändert, Analyse unvollständig.</summary>
    All: Boolean;
    AllReason: string;
    /// <summary>Namen für den Testlauf ohne Doppelte; leer mit All.</summary>
    Run: TArray<string>;
    Tests: TArray<TAtlasAffectedTest>;
    /// <summary>Geänderte Symbole bzw. Units als Text.</summary>
    Changes: TArray<string>;
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
  mValue: TJSONValue;
begin
  Result := Default(TAtlasConfidence);
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mValue := TJSONObject(AItem).GetValue('atlasConfidence');
  if not (mValue is TJSONObject) then
  begin
    Exit;
  end;
  Result.Inferred := TJSONObject(mValue).GetValue<string>('level', '') = 'inferred';
  if Result.Inferred then
  begin
    Result.Reason := TJSONObject(mValue).GetValue<string>('reason', '');
    Result.Explanation := TJSONObject(mValue).GetValue<string>('detail', '');
  end;
end;

{ TAtlasImpact }

function TAtlasImpact.Children(ACause: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(Places) do
  begin
    if Places[mIndex].Cause = ACause then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function TAtlasImpact.LevelCount(ALevel: Integer): Integer;
var
  mPlace: TAtlasImpactPlace;
begin
  Result := 0;
  for mPlace in Places do
  begin
    if mPlace.Level = ALevel then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasImpact.CountFrom(ALevel: Integer): Integer;
var
  mPlace: TAtlasImpactPlace;
begin
  Result := 0;
  for mPlace in Places do
  begin
    if mPlace.Level >= ALevel then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasImpact.RunNames: TArray<string>;
var
  mTest: TAtlasImpactTest;
  mName, mSeen: string;
begin
  Result := nil;
  mSeen := '|';
  for mTest in Tests do
  begin
    for mName in mTest.RunNames do
    begin
      if Pos('|' + UpperCase(mName) + '|', mSeen) = 0 then
      begin
        mSeen := mSeen + UpperCase(mName) + '|';
        Result := Result + [mName];
      end;
    end;
  end;
end;

function TAtlasImpact.Found: Boolean;
begin
  Result := Symbol.Name <> '';
end;

{ TAtlasProblem }

function TAtlasProblem.IsCompiler: Boolean;
begin
  Result := SameText(Source, cCompilerSource);
end;

class function TAtlasProblem.WithoutCompilerCode(const AMessage: string): string;
const
  cOpening = ' (wie ';
var
  mStart, mStop, mIndex: Integer;
  mInner: string;
  mCodes: Boolean;
begin
  Result := AMessage;
  mStart := Pos(cOpening, Result);
  while mStart > 0 do
  begin
    mStop := Pos(')', Copy(Result, mStart, MaxInt)) + mStart - 1;
    if mStop < mStart then
    begin
      Break;
    end;
    mInner := Copy(Result, mStart + Length(cOpening), mStop - mStart - Length(cOpening));
    // Nur Codes wie E2034, W1000–W1007 und Trenner; anderer Text in Klammern bleibt.
    mCodes := mInner <> '';
    for mIndex := 1 to Length(mInner) do
    begin
      if not CharInSet(mInner[mIndex], ['A'..'Z', '0'..'9', ',', ' ']) and (mInner[mIndex] <> #$2013) then
      begin
        mCodes := False;
      end;
    end;
    if mCodes then
    begin
      Delete(Result, mStart, mStop - mStart + 1);
      mStart := Pos(cOpening, Result);
    end
    else
    begin
      mIndex := Pos(cOpening, Copy(Result, mStop + 1, MaxInt));
      if mIndex = 0 then
      begin
        Break;
      end;
      mStart := mStop + mIndex;
    end;
  end;
end;

function TAtlasProblem.CompilerCodeText: string;
begin
  if Confirmed then
  begin
    Result := ConfirmedCode;
  end
  else if IsCompiler then
  begin
    Result := Code;
  end
  else
  begin
    Result := string.Join(', ', CompilerCodes);
  end;
end;

function TAtlasProblem.IsUses: Boolean;
begin
  Result := UsesState <> '';
end;

function TAtlasProblem.Contains(ALine, ACharacter: Integer): Boolean;
var
  mLast: Integer;
begin
  if (ALine < StartLine) or (ALine > EndLine) then
  begin
    Exit(False);
  end;
  mLast := EndCharacter;
  if (StartLine = EndLine) and (EndCharacter <= StartCharacter) then
  begin
    mLast := StartCharacter + 1;
  end;
  Result := ((ALine > StartLine) or (ACharacter >= StartCharacter)) and ((ALine < EndLine) or (ACharacter <= mLast));
end;

function TAtlasProblem.Caption: string;
begin
  if Code = '' then
  begin
    Result := Message;
  end
  else
  begin
    Result := Format('%s (%s)', [Message, Code]);
  end;
end;

function TAtlasProblem.CanSuppress: Boolean;
begin
  Result := (Code <> '') and not SameText(Code, cSyntaxCode) and not SameText(Code, cLanguageFeatureCode);
end;

function TAtlasProblem.InactiveHint(const AConditionFormat, ATargetFormat, AFallback: string): string;
var
  mPlatform, mConfig: string;
begin
  if InactiveCondition = '' then
  begin
    Exit(AFallback);
  end;
  Result := Format(AConditionFormat, [InactiveCondition]);
  if (InactivePlatform = '') and (InactiveConfig = '') then
  begin
    Exit;
  end;
  mPlatform := InactivePlatform;
  mConfig := InactiveConfig;
  if mPlatform = '' then
  begin
    mPlatform := '?';
  end;
  if mConfig = '' then
  begin
    mConfig := '?';
  end;
  Result := Result + Format(ATargetFormat, [mPlatform, mConfig]);
end;

/// <summary>LSP-Schweregrad (1 Fehler … 4 Hinweis); Unbekanntes gilt als Fehler.</summary>
function ProblemSeverityOf(AValue: Integer): TAtlasProblemSeverity;
begin
  case AValue of
    2:
      Result := TAtlasProblemSeverity.Warning;
    3:
      Result := TAtlasProblemSeverity.Information;
    4:
      Result := TAtlasProblemSeverity.Hint;
  else
    Result := TAtlasProblemSeverity.Error;
  end;
end;

/// <summary>Code eines Befunds als Text oder Zahl, '' ohne.</summary>
function ProblemCodeOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONString then
  begin
    Result := TJSONString(AValue).Value;
  end
  else if AValue is TJSONNumber then
  begin
    Result := TJSONNumber(AValue).ToString;
  end;
end;

/// <summary>Die Zeichenketten eines JSON-Arrays; anderes wird übergangen.</summary>
function ProblemStringsOf(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONString then
    begin
      Result := Result + [TJSONString(mItem).Value];
    end;
  end;
end;

/// <summary>Liest data.inactive und data.uses eines Befunds.</summary>
procedure ReadProblemContext(var AProblem: TAtlasProblem; AData: TJSONObject);
var
  mInactive, mUsesData: TJSONValue;
begin
  mInactive := AData.GetValue('inactive');
  if mInactive is TJSONObject then
  begin
    AProblem.InactiveCondition := TJSONObject(mInactive).GetValue<string>('condition', '');
    AProblem.InactivePlatform := TJSONObject(mInactive).GetValue<string>('platform', '');
    AProblem.InactiveConfig := TJSONObject(mInactive).GetValue<string>('config', '');
  end;
  mUsesData := AData.GetValue('uses');
  if mUsesData is TJSONObject then
  begin
    AProblem.UsesUnit := TJSONObject(mUsesData).GetValue<string>('unit', '');
    AProblem.UsesState := TJSONObject(mUsesData).GetValue<string>('state', '');
  end;
end;

/// <summary>Liest das Feld data eines Befunds (Angaben von Atlas).</summary>
procedure ReadProblemData(var AProblem: TAtlasProblem; AData: TJSONValue);
var
  mData: TJSONObject;
begin
  if not (AData is TJSONObject) then
  begin
    Exit;
  end;
  mData := TJSONObject(AData);
  AProblem.Confidence := mData.GetValue<string>('confidence', '');
  AProblem.Category := mData.GetValue<string>('category', '');
  AProblem.Group := mData.GetValue<string>('group', '');
  AProblem.FixTitle := mData.GetValue<string>('fix', '');
  AProblem.CompilerCodes := ProblemStringsOf(mData.GetValue('compilerCodes'));
  AProblem.Details := mData.GetValue<string>('details', '');
  ReadProblemContext(AProblem, mData);
end;

/// <summary>Verweise aus relatedInformation; Einträge ohne URI fallen weg.</summary>
function ProblemRelatedOf(AItems: TJSONValue): TArray<TAtlasProblemRelated>;
var
  mItem: TJSONValue;
  mRelated: TAtlasProblemRelated;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mRelated.Uri := TJSONObject(mItem).GetValue<string>('location.uri', '');
    mRelated.Line := TJSONObject(mItem).GetValue<Integer>('location.range.start.line', 0);
    mRelated.Character := TJSONObject(mItem).GetValue<Integer>('location.range.start.character', 0);
    mRelated.Message := TJSONObject(mItem).GetValue<string>('message', '');
    if mRelated.Uri <> '' then
    begin
      Result := Result + [mRelated];
    end;
  end;
end;

/// <summary>Liest tags (1 unnötig, 2 veraltet).</summary>
procedure ReadProblemTags(var AProblem: TAtlasProblem; ATags: TJSONValue);
var
  mTag: TJSONValue;
begin
  if not (ATags is TJSONArray) then
  begin
    Exit;
  end;
  for mTag in TJSONArray(ATags) do
  begin
    if mTag is TJSONNumber then
      case TJSONNumber(mTag).AsInt of
        1:
          AProblem.Unnecessary := True;
        2:
          AProblem.Deprecated := True;
      end;
  end;
end;

class function TAtlasProblem.FromJson(const AItem: TJSONObject): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := AItem.GetValue<Integer>('range.start.line', 0);
  Result.StartCharacter := AItem.GetValue<Integer>('range.start.character', 0);
  Result.EndLine := AItem.GetValue<Integer>('range.end.line', Result.StartLine);
  Result.EndCharacter := AItem.GetValue<Integer>('range.end.character', Result.StartCharacter);
  Result.Severity := ProblemSeverityOf(AItem.GetValue<Integer>('severity', 1));
  Result.Code := ProblemCodeOf(AItem.GetValue('code'));
  Result.Source := AItem.GetValue<string>('source', '');
  Result.Message := AItem.GetValue<string>('message', '');
  ReadProblemData(Result, AItem.GetValue('data'));
  Result.Related := ProblemRelatedOf(AItem.GetValue('relatedInformation'));
  ReadProblemTags(Result, AItem.GetValue('tags'));
end;

class function TAtlasProblem.ListFromJson(const AItems: TJSONArray): TArray<TAtlasProblem>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [FromJson(TJSONObject(mItem))];
    end;
  end;
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
