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
    cPlainTextCommand = 'atlas.server.plainText';
    cToLiteralCommand = 'atlas.server.textToLiteral';
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
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TStringLiteralCommandsText = (URIAndPositionExpected, DocumentIsNotOpen, ThereIsNoStringLiteral,
    TheTextIsExpectedAs);

const
  cTexts: array[TStringLiteralCommandsText] of TAtlasText = (
    (De: 'Erwartet werden URI und Position'; En: 'URI and position expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '),
    (De: 'An dieser Stelle steht kein String-Literal'; En: 'There is no string literal at this position'),
    (De: 'Erwartet wird der Text als drittes Argument'; En: 'The text is expected as the third argument'));

{$SCOPEDENUMS OFF}

function DocumentOf(const AStore: IDocumentStore; const AArguments: TJSONArray; ACount: Integer;
  out APosition: TTextPosition): ITextDocument;
begin
  // TJSONNumber erbt von TJSONString: Zahlen sind weder URI noch Text (#415).
  if (AArguments = nil) or (AArguments.Count < ACount) or not (AArguments.Items[0] is TJSONString) or
    (AArguments.Items[0] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TStringLiteralCommandsText.URIAndPositionExpected].Text);
  end;
  if not AStore.TryGet(AArguments.Items[0].Value, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TStringLiteralCommandsText.DocumentIsNotOpen].Text +
      AArguments.Items[0].Value);
  end;
  APosition := TLspPositions.ReadPosition(AArguments.Items[1]);
end;

class function TStringLiteralCommands.ExecutePlainText(const AStore: IDocumentStore;
  const AArguments: TJSONArray): TJSONValue;
var
  mDocument: ITextDocument;
  mPosition: TTextPosition;
  mRange: TTextRange;
  mText: string;
begin
  mDocument := DocumentOf(AStore, AArguments, 2, mPosition);
  if not (TStringLiterals.LiteralAt(mDocument.Text, mPosition, mRange) and
    TStringLiterals.PlainText(TStringLiterals.TextOf(mDocument.Text, mRange), mText)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TStringLiteralCommandsText.ThereIsNoStringLiteral].Text);
  end;
  Result := TJSONString.Create(mText);
end;

class function TStringLiteralCommands.ExecuteToLiteral(const AStore: IDocumentStore;
  const ASettings: TStringLiteralSettings; AMultiline: Boolean; const AArguments: TJSONArray): TJSONValue;
var
  mDocument: ITextDocument;
  mPosition: TTextPosition;
  mLines: TArray<string>;
  mLine, mIndent, mLineEnd: string;
  mIndex: Integer;
begin
  mDocument := DocumentOf(AStore, AArguments, 3, mPosition);
  if not (AArguments.Items[2] is TJSONString) or (AArguments.Items[2] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TStringLiteralCommandsText.TheTextIsExpectedAs].Text);
  end;
  mLines := mDocument.Text.Split([#10]);
  mLine := '';
  if (mPosition.Line >= 0) and (mPosition.Line <= High(mLines)) then
  begin
    mLine := mLines[mPosition.Line];
  end;
  mIndex := 1;
  while (mIndex <= Length(mLine)) and CharInSet(mLine[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  mIndent := Copy(mLine, 1, mIndex - 1);
  mLineEnd := TTextLines.LineBreakOf(mDocument.Text);
  Result := TJSONString.Create(TStringLiterals.ToLiteral(AArguments.Items[2].Value, mIndent, False, AMultiline,
    ASettings, mLineEnd));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.StringLiteralCommands', cTexts);

end.
