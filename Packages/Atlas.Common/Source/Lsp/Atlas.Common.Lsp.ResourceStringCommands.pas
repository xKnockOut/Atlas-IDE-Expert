unit Atlas.Common.Lsp.ResourceStringCommands;

// Befehl zu „Als resourcestring auslagern“ (#473) für workspace/executeCommand:
//   atlas.server.addResourceString [datei, name, wert]: trägt "name = wert;"
//     in den resourcestring-Abschnitt im interface-Teil der Datei ein (legt ihn
//     vor implementation an, wenn er fehlt). Die Vervollständigung schickt den
//     Befehl, wenn completion.resourceStringUnit eine andere Unit festlegt;
//     Bezeichner und uses-Eintrag setzt sie selbst. Gibt es den Namen dort
//     schon mit demselben Text, ändert sich nichts.
// Geschrieben wird über den Aufrufer (in der IDE über workspace/applyEdit in
// den Puffer, #397).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  TResourceStringRead = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Schreibt AEdit in AFileName; ANewText ist der Text danach (für das Schreiben ohne Editor).</summary>
  TResourceStringWrite = reference to procedure(const AFileName, ANewText: string; const AEdit: TTextEdit);

  TResourceStringCommands = class
  public const
    AddCommand = 'atlas.server.addResourceString';
  public
    /// <summary>Änderung für "AName = AValue;" im interface-Teil von AText. False ohne Änderung (gleicher Eintrag
    /// schon da); Ausnahme EJsonRpcError, wenn es AName mit anderem Text gibt oder implementation fehlt.</summary>
    class function AddEdit(const AText, AName, AValue: string; out AEdit: TTextEdit): Boolean; static;
    /// <summary>AEdit auf AText angewandt (Zeilen mit #10, #13 bleibt erhalten).</summary>
    class function Applied(const AText: string; const AEdit: TTextEdit): string; static;
    class function ExecuteAdd(const ARead: TResourceStringRead; const AWrite: TResourceStringWrite;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.ResourceStrings;

class function TResourceStringCommands.AddEdit(const AText, AName, AValue: string; out AEdit: TTextEdit): Boolean;
var
  Entry: TResourceEntry;
  LineBreak: string;
  Tokens: TArray<TPascalToken>;
begin
  AEdit := Default(TTextEdit);
  Tokens := TPascalLexer.Tokenize(AText);
  for Entry in TResourceStrings.Entries(AText, Tokens) do
    if SameText(Entry.Name, AName) then
    begin
      if Entry.Value = AValue then
        Exit(False);
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
        Format('%s gibt es dort schon mit anderem Text', [AName]));
    end;
  LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10;
  if not TResourceStrings.Insertion(AText, Tokens, True, -1, Format('%s = %s;', [AName, AValue]), LineBreak,
    AEdit) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Die Unit hat keinen implementation-Teil');
  Result := True;
end;

class function TResourceStringCommands.Applied(const AText: string; const AEdit: TTextEdit): string;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Index: Integer;
  begin
    Line := 0;
    Index := 1;
    while (Line < APosition.Line) and (Index <= Length(AText)) do
    begin
      if AText[Index] = #10 then
        Inc(Line);
      Inc(Index);
    end;
    Result := Index - 1 + APosition.Character;
  end;

var
  Start, Stop: Integer;
begin
  Start := OffsetOf(AEdit.Range.StartPos);
  Stop := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start) + AEdit.NewText + Copy(AText, Stop + 1, MaxInt);
end;

class function TResourceStringCommands.ExecuteAdd(const ARead: TResourceStringRead;
  const AWrite: TResourceStringWrite; const AArguments: TJSONArray): TJSONValue;
var
  FileName, Name, Value, Text: string;
  Edit: TTextEdit;
begin
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONString) or not (AArguments.Items[2] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden Datei, Name und Wert');
  FileName := AArguments.Items[0].Value;
  Name := AArguments.Items[1].Value;
  Value := AArguments.Items[2].Value;
  if not IsValidIdent(Name) or (Value = '') then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Ungültiger Name oder leerer Wert');
  if not ARead(FileName, Text) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Datei nicht lesbar: ' + ExtractFileName(FileName));
  if AddEdit(Text, Name, Value, Edit) then
  begin
    AWrite(FileName, Applied(Text, Edit), Edit);
    Exit(TJSONBool.Create(True));
  end;
  Result := TJSONBool.Create(False);
end;

end.
