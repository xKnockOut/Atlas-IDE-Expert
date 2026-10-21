unit Atlas.Core.Lsp.Contract;

// Werttypen, die der LSP-Client (TLspSession) liefert und die Features darüber verwenden (A-09): Probleme
// (Diagnosen, #398), Symbole der projektweiten Suche und Einträge der Typ- und Aufrufhierarchie (#400).
// Sie liegen im Lsp-Feature, weil die Protokollschicht unten liegt; Atlas.Core.Problems.Contract und
// Atlas.Core.Results.Model führen sie als Alias weiter. Positionen sind 0-basiert in UTF-16-Einheiten.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasProblemSeverity = (Error, Warning, Information, Hint);
  {$SCOPEDENUMS OFF}

  TAtlasProblem = record
  public const
    CompilerSource = 'dcc';
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
    /// <summary>Regel-ID bzw. Meldungsnummer (E2003); '' bei Syntaxfehlern.</summary>
    Code: string;
    /// <summary>"Atlas" oder "dcc".</summary>
    Source: string;
    Message: string;
    /// <summary>Konfidenz eines Regeltreffers aus data.confidence ("high", "medium", "low", #144); sonst ''.</summary>
    Confidence: string;
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
    function IsCompiler: Boolean;
    /// <summary>Hinweis zu einem uses-Eintrag (#621), kein Problem für Liste und Wellenlinie.</summary>
    function IsUses: Boolean;
    /// <summary>Liegt die Stelle (0-basiert) im Bereich? Leere Bereiche zählen als ein Zeichen.</summary>
    function Contains(ALine, ACharacter: Integer): Boolean;
    /// <summary>"Meldung (Code)" bzw. nur die Meldung.</summary>
    function Caption: string;
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
  end;

implementation

{ TAtlasProblem }

function TAtlasProblem.IsCompiler: Boolean;
begin
  Result := SameText(Source, CompilerSource);
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
  Tags, CodeValue, Data, Inactive, UsesData: TJSONValue;
  Tag: TJSONValue;
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

end.
