unit Atlas.Common.Lsp.SmartPaste;

// Einfügen mit uses-Ergänzung (#515) über das Protokoll: Befehl
// atlas.server.pasteUses.
//   - [uri, range]: Was fehlt im eingefügten Bereich? Antwort {"units":
//     [eindeutige Units], "choices": [{"name": Bezeichner, "units": [...]}],
//     "interface": true, wenn die Einfügestelle im interface-Teil liegt}.
//   - [uri, range, [Units]]: Edit dazu, {"edit": WorkspaceEdit oder null,
//     "added": [eingetragene], "toImplementation": [wegen Kreisverweis ins
//     implementation-uses verlegte]}.
// Das Plugin schickt vorher den Puffer; die Logik liegt in
// Atlas.Common.Editing.SmartPaste.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SmartPaste;

type
  TLspSmartPaste = class
  public const
    Command = 'atlas.server.pasteUses';
  public
    /// <summary>Antwort auf AArguments für die Datei AUri mit Text AText und Baum ATree. Der Aufrufer übernimmt
    /// das Objekt; ungültige Argumente ergeben EArgumentException.</summary>
    class function Execute(const AArguments: TJSONArray; const AUri, AText: string; ATree: TSyntaxTree;
      const AUses: TUsesContext; const AInterfaceUses: TInterfaceUsesFunc): TJSONObject; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.Positions;

function NamesJson(const ANames: TArray<string>): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in ANames do
    Result.Add(Name);
end;

class function TLspSmartPaste.Execute(const AArguments: TJSONArray; const AUri, AText: string; ATree: TSyntaxTree;
  const AUses: TUsesContext; const AInterfaceUses: TInterfaceUsesFunc): TJSONObject;
var
  Tokens: TArray<TPascalToken>;
  Range: TTextRange;
  Names: TArray<TSmartPasteName>;
  Item: TSmartPasteName;
  Choices, List: TJSONArray;
  Choice, Changes, WorkspaceEdit, Change: TJSONObject;
  Units, Added, Moved: TArray<string>;
  Value: TJSONValue;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONObject) then
    raise EArgumentException.Create('Argumente "uri" und "range" fehlen');
  Range := TLspPositions.ReadRange(AArguments.Items[1]);
  Tokens := TPascalLexer.Tokenize(AText);
  Result := TJSONObject.Create;
  if (AArguments.Count < 3) or not (AArguments.Items[2] is TJSONArray) then
  begin
    Names := TSmartPaste.Missing(Tokens, ATree, Range, AUses.Declaring, AUses.Namespaces);
    Result.AddPair('units', NamesJson(TSmartPaste.Certain(Names)));
    Choices := TJSONArray.Create;
    for Item in Names do
      if Length(Item.Units) > 1 then
      begin
        Choice := TJSONObject.Create;
        Choice.AddPair('name', Item.Name);
        Choice.AddPair('units', NamesJson(Item.Units));
        Choices.AddElement(Choice);
      end;
    Result.AddPair('choices', Choices);
    Result.AddPair('interface', TJSONBool.Create(TSmartPaste.InInterface(Tokens, Range.StartPos)));
    Exit;
  end;
  Units := nil;
  for Value in TJSONArray(AArguments.Items[2]) do
    if Value is TJSONString then
      Units := Units + [Value.Value];
  if TSmartPaste.UsesEdits(Tokens, Range.StartPos, Units, AInterfaceUses, AUses.Namespaces,
    TTextLines.LineBreakOf(AText), Edits, Added, Moved) then
  begin
    List := TJSONArray.Create;
    for Edit in Edits do
    begin
      Change := TJSONObject.Create;
      Change.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
      Change.AddPair('newText', Edit.NewText);
      List.AddElement(Change);
    end;
    Changes := TJSONObject.Create;
    Changes.AddPair(AUri, List);
    WorkspaceEdit := TJSONObject.Create;
    WorkspaceEdit.AddPair('changes', Changes);
    Result.AddPair('edit', WorkspaceEdit);
  end
  else
    Result.AddPair('edit', TJSONNull.Create);
  Result.AddPair('added', NamesJson(Added));
  Result.AddPair('toImplementation', NamesJson(Moved));
end;

end.
