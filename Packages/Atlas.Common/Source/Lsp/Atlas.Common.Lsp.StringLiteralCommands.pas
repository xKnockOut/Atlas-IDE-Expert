unit Atlas.Common.Lsp.StringLiteralCommands;

// Befehle zu Klartext und String-Literal (#312) für workspace/executeCommand:
//   atlas.server.plainText [uri, position]: Text des Literals an der
//     Position ohne Hochkommas, "+", sLineBreak und #13#10; der Client legt
//     ihn in die Zwischenablage.
//   atlas.server.textToLiteral [uri, position, text]: text als Literal mit
//     der Einrückung der Zeile an der Position; der Client fügt es ein.
// Die Logik liegt in Atlas.Common.Editing.StringLiterals.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

type
  TStringLiteralCommands = class
  public const
    PlainTextCommand = 'atlas.server.plainText';
    ToLiteralCommand = 'atlas.server.textToLiteral';
  public
    class function ExecutePlainText(const AStore: IDocumentStore; const AArguments: TJSONArray): TJSONValue; static;
    class function ExecuteToLiteral(const AStore: IDocumentStore; const ASettings: TStringLiteralSettings;
      AMultiline: Boolean; const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Text.Lines;

function DocumentOf(const AStore: IDocumentStore; const AArguments: TJSONArray; ACount: Integer;
  out APosition: TTextPosition): ITextDocument;
begin
  // TJSONNumber erbt von TJSONString: Zahlen sind weder URI noch Text (#415).
  if (AArguments = nil) or (AArguments.Count < ACount) or not (AArguments.Items[0] is TJSONString) or
    (AArguments.Items[0] is TJSONNumber) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI und Position');
  if not AStore.TryGet(AArguments.Items[0].Value, Result) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' +
      AArguments.Items[0].Value);
  APosition := TLspPositions.ReadPosition(AArguments.Items[1]);
end;

class function TStringLiteralCommands.ExecutePlainText(const AStore: IDocumentStore;
  const AArguments: TJSONArray): TJSONValue;
var
  Document: ITextDocument;
  Position: TTextPosition;
  Range: TTextRange;
  Text: string;
begin
  Document := DocumentOf(AStore, AArguments, 2, Position);
  if not (TStringLiterals.LiteralAt(Document.Text, Position, Range) and
    TStringLiterals.PlainText(TStringLiterals.TextOf(Document.Text, Range), Text)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'An dieser Stelle steht kein String-Literal');
  Result := TJSONString.Create(Text);
end;

class function TStringLiteralCommands.ExecuteToLiteral(const AStore: IDocumentStore;
  const ASettings: TStringLiteralSettings; AMultiline: Boolean; const AArguments: TJSONArray): TJSONValue;
var
  Document: ITextDocument;
  Position: TTextPosition;
  Lines: TArray<string>;
  Line, Indent, LineEnd: string;
  Index: Integer;
begin
  Document := DocumentOf(AStore, AArguments, 3, Position);
  if not (AArguments.Items[2] is TJSONString) or (AArguments.Items[2] is TJSONNumber) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet wird der Text als drittes Argument');
  Lines := Document.Text.Split([#10]);
  Line := '';
  if (Position.Line >= 0) and (Position.Line <= High(Lines)) then
    Line := Lines[Position.Line];
  Index := 1;
  while (Index <= Length(Line)) and CharInSet(Line[Index], [' ', #9]) do
    Inc(Index);
  Indent := Copy(Line, 1, Index - 1);
  LineEnd := TTextLines.LineBreakOf(Document.Text);
  Result := TJSONString.Create(TStringLiterals.ToLiteral(AArguments.Items[2].Value, Indent, False, AMultiline,
    ASettings.LineBreak, ASettings.MaxLineLength, LineEnd));
end;

end.
