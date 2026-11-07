unit Atlas.Common.Lsp.FormFiles;

// Formulardateien im LSP (#44): Gliederung (documentSymbol) und Faltbereiche
// aus dem Baum einer Text-DFM bzw. -FMX. Objekte erscheinen als
// "Name: TKlasse", Ereignisse als Unterpunkte "OnClick = Button1Click".

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Dfm.Contract;

type
  TLspFormFiles = class
  public const
    /// <summary>Code der Hinweis-Diagnose für binäre Formulare (#122).</summary>
    cBinaryCode = 'binary-form';
    /// <summary>Befehl: binäre Formulare in Text umwandeln; Argument die URI, ohne Argument alle im Projekt.</summary>
    cConvertCommand = 'atlas.server.convertBinaryForms';
  public
    /// <summary>DocumentSymbol[] der Formulardatei. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildSymbols(ADocument: TDfmDocument): TJSONArray; static;
    /// <summary>FoldingRange[] für Objekte und mehrzeilige Werte. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildFoldingRanges(ADocument: TDfmDocument): TJSONArray; static;
    /// <summary>Diagnostic[] aus den Lesefehlern. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildDiagnostics(ADocument: TDfmDocument): TJSONArray; static;
    /// <summary>Genau ein Hinweis "binär gespeichert" statt Lesefehlern. Der Aufrufer übernimmt das Objekt.</summary>
    class function BinaryDiagnostics: TJSONArray; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFormFilesText = (FormIsStoredAsBinary);

const
  cTexts: array[TFormFilesText] of TAtlasText = (
    (De: 'Formular ist binär gespeichert; in Text umwandeln?'; En: 'Form is stored as binary; convert to text?'));

{$SCOPEDENUMS OFF}

function ObjectToJson(AObject: TDfmObject): TJSONObject;
var
  mChildren: TJSONArray;
  mChild: TDfmObject;
  mItem: TDfmProperty;
  mEvent: TJSONObject;
  mName: string;
begin
  Result := TJSONObject.Create;
  if AObject.Kind = TDfmObjectKind.Item then
  begin
    mName := 'item';
  end
  else if AObject.Name = '' then
  begin
    mName := AObject.TypeName;
  end
  else
  begin
    mName := AObject.Name + ': ' + AObject.TypeName;
  end;
  Result.AddPair('name', mName);
  if AObject.Kind = TDfmObjectKind.Inherited_ then
  begin
    Result.AddPair('detail', 'inherited');
  end
  else if AObject.Kind = TDfmObjectKind.Inline_ then
  begin
    Result.AddPair('detail', 'inline');
  end;
  Result.AddPair('kind', TJSONNumber.Create(TLspSymbolKind.cObject_));
  Result.AddPair('range', TLspPositions.RangeToJson(AObject.Range));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(AObject.NameRange));
  mChildren := TJSONArray.Create;
  for mItem in AObject.Properties do
  begin
    if mItem.IsEvent then
    begin
      mEvent := TJSONObject.Create;
      mEvent.AddPair('name', mItem.Name + ' = ' + mItem.Value);
      mEvent.AddPair('kind', TJSONNumber.Create(TLspSymbolKind.cEvent));
      mEvent.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(mItem.NameRange.StartPos,
        mItem.ValueRange.EndPos)));
      mEvent.AddPair('selectionRange', TLspPositions.RangeToJson(mItem.NameRange));
      mChildren.AddElement(mEvent);
    end;
  end;
  for mChild in AObject.Children do
  begin
    mChildren.AddElement(ObjectToJson(mChild));
  end;
  Result.AddPair('children', mChildren);
end;

procedure AddFolding(AObject: TDfmObject; AItems: TJSONArray);
var
  mItem: TDfmProperty;
  mChild: TDfmObject;
  mRange: TJSONObject;
begin
  if AObject.Range.EndPos.Line > AObject.Range.StartPos.Line then
  begin
    mRange := TJSONObject.Create;
    mRange.AddPair('startLine', TJSONNumber.Create(AObject.Range.StartPos.Line));
    mRange.AddPair('endLine', TJSONNumber.Create(AObject.Range.EndPos.Line));
    AItems.AddElement(mRange);
  end;
  // Mehrzeilige Werte wie Binärdaten und Stringlisten.
  for mItem in AObject.Properties do
  begin
    if mItem.ValueRange.EndPos.Line > mItem.ValueRange.StartPos.Line then
    begin
      mRange := TJSONObject.Create;
      mRange.AddPair('startLine', TJSONNumber.Create(mItem.NameRange.StartPos.Line));
      mRange.AddPair('endLine', TJSONNumber.Create(mItem.ValueRange.EndPos.Line));
      AItems.AddElement(mRange);
    end;
  end;
  for mChild in AObject.Children do
  begin
    AddFolding(mChild, AItems);
  end;
end;

{ TLspFormFiles }

class function TLspFormFiles.BuildSymbols(ADocument: TDfmDocument): TJSONArray;
begin
  Result := TJSONArray.Create;
  if ADocument.Root <> nil then
  begin
    Result.AddElement(ObjectToJson(ADocument.Root));
  end;
end;

class function TLspFormFiles.BuildFoldingRanges(ADocument: TDfmDocument): TJSONArray;
begin
  Result := TJSONArray.Create;
  if ADocument.Root <> nil then
  begin
    AddFolding(ADocument.Root, Result);
  end;
end;

class function TLspFormFiles.BinaryDiagnostics: TJSONArray;
var
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  mItem := TJSONObject.Create;
  mItem.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(0, 0, 0, 4)));
  mItem.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cHint));
  mItem.AddPair('source', 'Atlas');
  mItem.AddPair('code', cBinaryCode);
  mItem.AddPair('message', cTexts[TFormFilesText.FormIsStoredAsBinary].Text);
  Result.AddElement(mItem);
end;

class function TLspFormFiles.BuildDiagnostics(ADocument: TDfmDocument): TJSONArray;
var
  mError: TDfmError;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mError in ADocument.Errors do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(mError.Position, mError.Position)));
    mItem.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cError));
    mItem.AddPair('source', 'Atlas');
    mItem.AddPair('message', mError.Message);
    Result.AddElement(mItem);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.FormFiles', cTexts);

end.
