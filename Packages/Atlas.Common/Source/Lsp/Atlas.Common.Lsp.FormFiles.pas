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
    BinaryCode = 'binary-form';
    /// <summary>Befehl: binäre Formulare in Text umwandeln; Argument die URI, ohne Argument alle im Projekt.</summary>
    ConvertCommand = 'atlas.server.convertBinaryForms';
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
  Atlas.Common.Documents.Contract;

function ObjectToJson(AObject: TDfmObject): TJSONObject;
var
  Children: TJSONArray;
  Child: TDfmObject;
  Item: TDfmProperty;
  Event: TJSONObject;
  Name: string;
begin
  Result := TJSONObject.Create;
  if AObject.Kind = TDfmObjectKind.Item then
    Name := 'item'
  else if AObject.Name = '' then
    Name := AObject.TypeName
  else
    Name := AObject.Name + ': ' + AObject.TypeName;
  Result.AddPair('name', Name);
  if AObject.Kind = TDfmObjectKind.Inherited_ then
    Result.AddPair('detail', 'inherited')
  else if AObject.Kind = TDfmObjectKind.Inline_ then
    Result.AddPair('detail', 'inline');
  Result.AddPair('kind', TJSONNumber.Create(TLspSymbolKind.Object_));
  Result.AddPair('range', TLspPositions.RangeToJson(AObject.Range));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(AObject.NameRange));
  Children := TJSONArray.Create;
  for Item in AObject.Properties do
    if Item.IsEvent then
    begin
      Event := TJSONObject.Create;
      Event.AddPair('name', Item.Name + ' = ' + Item.Value);
      Event.AddPair('kind', TJSONNumber.Create(TLspSymbolKind.Event));
      Event.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Item.NameRange.StartPos, Item.ValueRange.EndPos)));
      Event.AddPair('selectionRange', TLspPositions.RangeToJson(Item.NameRange));
      Children.AddElement(Event);
    end;
  for Child in AObject.Children do
    Children.AddElement(ObjectToJson(Child));
  Result.AddPair('children', Children);
end;

procedure AddFolding(AObject: TDfmObject; AItems: TJSONArray);
var
  Item: TDfmProperty;
  Child: TDfmObject;
  Range: TJSONObject;
begin
  if AObject.Range.EndPos.Line > AObject.Range.StartPos.Line then
  begin
    Range := TJSONObject.Create;
    Range.AddPair('startLine', TJSONNumber.Create(AObject.Range.StartPos.Line));
    Range.AddPair('endLine', TJSONNumber.Create(AObject.Range.EndPos.Line));
    AItems.AddElement(Range);
  end;
  // Mehrzeilige Werte wie Binärdaten und Stringlisten.
  for Item in AObject.Properties do
    if Item.ValueRange.EndPos.Line > Item.ValueRange.StartPos.Line then
    begin
      Range := TJSONObject.Create;
      Range.AddPair('startLine', TJSONNumber.Create(Item.NameRange.StartPos.Line));
      Range.AddPair('endLine', TJSONNumber.Create(Item.ValueRange.EndPos.Line));
      AItems.AddElement(Range);
    end;
  for Child in AObject.Children do
    AddFolding(Child, AItems);
end;

{ TLspFormFiles }

class function TLspFormFiles.BuildSymbols(ADocument: TDfmDocument): TJSONArray;
begin
  Result := TJSONArray.Create;
  if ADocument.Root <> nil then
    Result.AddElement(ObjectToJson(ADocument.Root));
end;

class function TLspFormFiles.BuildFoldingRanges(ADocument: TDfmDocument): TJSONArray;
begin
  Result := TJSONArray.Create;
  if ADocument.Root <> nil then
    AddFolding(ADocument.Root, Result);
end;

class function TLspFormFiles.BinaryDiagnostics: TJSONArray;
var
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  Item := TJSONObject.Create;
  Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(0, 0, 0, 4)));
  Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Hint));
  Item.AddPair('source', 'Atlas');
  Item.AddPair('code', BinaryCode);
  Item.AddPair('message', 'Formular ist binär gespeichert; in Text umwandeln?');
  Result.AddElement(Item);
end;

class function TLspFormFiles.BuildDiagnostics(ADocument: TDfmDocument): TJSONArray;
var
  Error: TDfmError;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Error in ADocument.Errors do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Error.Position, Error.Position)));
    Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Error));
    Item.AddPair('source', 'Atlas');
    Item.AddPair('message', Error.Message);
    Result.AddElement(Item);
  end;
end;

end.
