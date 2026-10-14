unit Atlas.Core.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.

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
    /// <summary>Zu einem inaktiven Bereich aus data.inactive (#615): Bedingung des Zweigs ("WIN64"),
    /// Zielplattform und Konfiguration des Servers; '' wenn unbekannt.</summary>
    InactiveCondition: string;
    InactivePlatform: string;
    InactiveConfig: string;
    /// <summary>Text geändert, seit die Meldung entstand: blass zeigen.</summary>
    Stale: Boolean;
    function IsCompiler: Boolean;
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

implementation

{ TAtlasProblem }

function TAtlasProblem.IsCompiler: Boolean;
begin
  Result := SameText(Source, CompilerSource);
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
  Tags, CodeValue, Data, Inactive: TJSONValue;
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
  end;
  Tags := AItem.GetValue('tags');
  if Tags is TJSONArray then
    for Tag in TJSONArray(Tags) do
      if (Tag is TJSONNumber) and (TJSONNumber(Tag).AsInt = 1) then
        Result.Unnecessary := True;
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
