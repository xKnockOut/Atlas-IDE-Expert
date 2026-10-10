unit Argus.Core.Build.Messages;

// Compilermeldungen der IDE (#528), ohne Open Tools API: Modell, Zerlegung
// von "E2003 Undeklarierter Bezeichner …" in Code und Text, Schweregrad aus
// der Art der IDE (msgError, msgWarning …) bzw. ersatzweise aus dem Code, und
// die Parameter der Benachrichtigung argus/compilerMessages an den Server.
// Der Code ist der Schlüssel, nicht der (deutsche oder englische) Text.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON;

type
  TArgusCompilerSeverity = (Info, Hint, Warning, Error, Fatal);

  TArgusCompilerMessage = record
    FileName: string;
    /// <summary>1-basiert wie in der IDE; 0 ohne.</summary>
    Line: Integer;
    Column: Integer;
    Severity: TArgusCompilerSeverity;
    Code: string;
    Text: string;
  end;

  TArgusCompilerMessages = class
  public
    /// <summary>Meldung aus den Feldern einer Zeile des Meldungsfensters.</summary>
    class function FromIde(const AKind, AMessage, AFileName: string; ALine, AColumn: Integer): TArgusCompilerMessage;
      static;
    class function SeverityText(ASeverity: TArgusCompilerSeverity): string; static;
    /// <summary>Parameter für argus/compilerMessages; Info-Meldungen bleiben weg.</summary>
    class function ToJson(const AMessages: TArray<TArgusCompilerMessage>; const AProject, APlatform: string;
      ASucceeded: Boolean): TJSONObject; static;
  end;

implementation

uses
  System.RegularExpressions;

class function TArgusCompilerMessages.FromIde(const AKind, AMessage, AFileName: string; ALine,
  AColumn: Integer): TArgusCompilerMessage;
var
  Match: TMatch;
  Kind: string;
begin
  Result := Default(TArgusCompilerMessage);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Text := Trim(AMessage);
  Match := TRegEx.Match(Result.Text, '^([EWHFC]\d{4})\s*:?\s*(.*)$', [roSingleLine]);
  if Match.Success then
  begin
    Result.Code := Match.Groups[1].Value;
    Result.Text := Match.Groups[2].Value;
  end;
  Kind := LowerCase(AKind);
  if Kind.Contains('fatal') then
    Result.Severity := TArgusCompilerSeverity.Fatal
  else if Kind.Contains('error') then
    Result.Severity := TArgusCompilerSeverity.Error
  else if Kind.Contains('warn') then
    Result.Severity := TArgusCompilerSeverity.Warning
  else if Kind.Contains('hint') then
    Result.Severity := TArgusCompilerSeverity.Hint
  else if Result.Code <> '' then
    // Unbekannte Art: nach dem Code.
    case Result.Code[1] of
      'E': Result.Severity := TArgusCompilerSeverity.Error;
      'W': Result.Severity := TArgusCompilerSeverity.Warning;
      'H': Result.Severity := TArgusCompilerSeverity.Hint;
      'F': Result.Severity := TArgusCompilerSeverity.Fatal;
    else
      Result.Severity := TArgusCompilerSeverity.Info;
    end
  else
    Result.Severity := TArgusCompilerSeverity.Info;
end;

class function TArgusCompilerMessages.SeverityText(ASeverity: TArgusCompilerSeverity): string;
const
  Texts: array[TArgusCompilerSeverity] of string = ('info', 'hint', 'warning', 'error', 'fatal');
begin
  Result := Texts[ASeverity];
end;

class function TArgusCompilerMessages.ToJson(const AMessages: TArray<TArgusCompilerMessage>; const AProject,
  APlatform: string; ASucceeded: Boolean): TJSONObject;
var
  Items: TJSONArray;
  Message: TArgusCompilerMessage;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AProject);
  Result.AddPair('platform', APlatform);
  Result.AddPair('success', TJSONBool.Create(ASucceeded));
  Items := TJSONArray.Create;
  Result.AddPair('messages', Items);
  for Message in AMessages do
  begin
    if Message.Severity = TArgusCompilerSeverity.Info then
      Continue;
    Item := TJSONObject.Create;
    Item.AddPair('file', Message.FileName);
    Item.AddPair('line', TJSONNumber.Create(Message.Line));
    Item.AddPair('column', TJSONNumber.Create(Message.Column));
    Item.AddPair('severity', SeverityText(Message.Severity));
    Item.AddPair('code', Message.Code);
    Item.AddPair('text', Message.Text);
    Items.AddElement(Item);
  end;
end;

end.