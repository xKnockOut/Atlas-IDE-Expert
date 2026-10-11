unit Argus.Core.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TArgusProblemSeverity = (Error, Warning, Information, Hint);
  {$SCOPEDENUMS OFF}

  TArgusProblem = record
  public const
    CompilerSource = 'dcc';
  public
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    Severity: TArgusProblemSeverity;
    /// <summary>Regel-ID bzw. Meldungsnummer (E2003); '' bei Syntaxfehlern.</summary>
    Code: string;
    /// <summary>"Argus" oder "dcc".</summary>
    Source: string;
    Message: string;
    /// <summary>Inaktiver Bereich ({$IFDEF}); kein Problem im eigentlichen Sinn.</summary>
    Unnecessary: Boolean;
    /// <summary>Text geändert, seit die Meldung entstand: blass zeigen.</summary>
    Stale: Boolean;
    function IsCompiler: Boolean;
    /// <summary>Liegt die Stelle (0-basiert) im Bereich? Leere Bereiche zählen als ein Zeichen.</summary>
    function Contains(ALine, ACharacter: Integer): Boolean;
    /// <summary>"Meldung (Code)" bzw. nur die Meldung.</summary>
    function Caption: string;
    class function FromJson(const AItem: TJSONObject): TArgusProblem; static;
    /// <summary>Alle Diagnosen einer LSP-Liste; Nicht-Objekte werden übersprungen.</summary>
    class function ListFromJson(const AItems: TJSONArray): TArray<TArgusProblem>; static;
  end;

implementation

{ TArgusProblem }

function TArgusProblem.IsCompiler: Boolean;
begin
  Result := SameText(Source, CompilerSource);
end;

function TArgusProblem.Contains(ALine, ACharacter: Integer): Boolean;
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

function TArgusProblem.Caption: string;
begin
  if Code = '' then
    Result := Message
  else
    Result := Format('%s (%s)', [Message, Code]);
end;

class function TArgusProblem.FromJson(const AItem: TJSONObject): TArgusProblem;
var
  Tags, CodeValue: TJSONValue;
  Tag: TJSONValue;
begin
  Result := Default(TArgusProblem);
  Result.StartLine := AItem.GetValue<Integer>('range.start.line', 0);
  Result.StartCharacter := AItem.GetValue<Integer>('range.start.character', 0);
  Result.EndLine := AItem.GetValue<Integer>('range.end.line', Result.StartLine);
  Result.EndCharacter := AItem.GetValue<Integer>('range.end.character', Result.StartCharacter);
  case AItem.GetValue<Integer>('severity', 1) of
    2:
      Result.Severity := TArgusProblemSeverity.Warning;
    3:
      Result.Severity := TArgusProblemSeverity.Information;
    4:
      Result.Severity := TArgusProblemSeverity.Hint;
  else
    Result.Severity := TArgusProblemSeverity.Error;
  end;
  CodeValue := AItem.GetValue('code');
  if CodeValue is TJSONString then
    Result.Code := TJSONString(CodeValue).Value
  else if CodeValue is TJSONNumber then
    Result.Code := TJSONNumber(CodeValue).ToString;
  Result.Source := AItem.GetValue<string>('source', '');
  Result.Message := AItem.GetValue<string>('message', '');
  Tags := AItem.GetValue('tags');
  if Tags is TJSONArray then
    for Tag in TJSONArray(Tags) do
      if (Tag is TJSONNumber) and (TJSONNumber(Tag).AsInt = 1) then
        Result.Unnecessary := True;
end;

class function TArgusProblem.ListFromJson(const AItems: TJSONArray): TArray<TArgusProblem>;
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
