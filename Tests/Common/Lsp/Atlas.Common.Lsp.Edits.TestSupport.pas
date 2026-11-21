unit Atlas.Common.Lsp.Edits.TestSupport;

// Gemeinsame Hilfen der Tests zu Refactorings über das Protokoll: Textänderungen aus einer Antwort lesen und auf
// einen Text anwenden.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract;

/// <summary>Änderungen aus dem Feld "edits" von ADocument (TextDocumentEdit).</summary>
function EditsOf(ADocument: TJSONObject): TArray<TTextEdit>;
/// <summary>AText mit den Änderungen aus ADocument.</summary>
function ApplyDocument(const AText: string; ADocument: TJSONObject): string;
/// <summary>AText mit allen Änderungen der Antwort AAnswer (edit.documentChanges) an der Datei AFileName.</summary>
function ApplyWorkspaceEdit(AAnswer: TJSONObject; const AFileName, AText: string): string;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.TextChanges;

function EditsOf(ADocument: TJSONObject): TArray<TTextEdit>;
var
  mItem: TJSONValue;
  mRange: TJSONObject;
begin
  Result := nil;
  for mItem in ADocument.GetValue('edits') as TJSONArray do
  begin
    mRange := TJSONObject(mItem).GetValue('range') as TJSONObject;
    Result := Result + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
      TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mItem).GetValue('newText').Value)];
  end;
end;

function ApplyDocument(const AText: string; ADocument: TJSONObject): string;
begin
  Result := TTextChanges.Apply(AText, EditsOf(ADocument));
end;

function ApplyWorkspaceEdit(AAnswer: TJSONObject; const AFileName, AText: string): string;
var
  mItem: TJSONValue;
  mDocument: TJSONObject;
  mUri: string;
begin
  Result := AText;
  for mItem in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    mDocument := TJSONObject(mItem);
    if mDocument.GetValue('textDocument') = nil then
    begin
      Continue;
    end;
    mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if SameText(TDocumentUris.ToPath(mUri), AFileName) then
    begin
      Result := TTextChanges.Apply(Result, EditsOf(mDocument));
    end;
  end;
end;

end.
