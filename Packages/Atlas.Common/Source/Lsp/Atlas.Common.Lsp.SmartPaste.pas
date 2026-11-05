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
  Atlas.Common.Editing.Contract,
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
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSmartPasteText = (ArgumentsUriAndRangeMissing);

const
  cTexts: array[TSmartPasteText] of TAtlasText = (
    (De: 'Argumente "uri" und "range" fehlen'; En: 'Arguments "uri" and "range" missing'));

{$SCOPEDENUMS OFF}

function NamesJson(const ANames: TArray<string>): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in ANames do
  begin
    Result.Add(Name);
  end;
end;

/// <summary>Was fehlt im eingefügten Bereich ARange? Eindeutige Units, mehrdeutige Namen und ob die Einfügestelle
/// im interface-Teil liegt.</summary>
procedure AddMissing(AResult: TJSONObject; const ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const ARange: TTextRange; const AUses: TUsesContext);
var
  mNames: TArray<TSmartPasteName>;
  mItem: TSmartPasteName;
  mChoices: TJSONArray;
  mChoice: TJSONObject;
begin
  mNames := TSmartPaste.Missing(ATokens, ATree, ARange, AUses.Declaring, AUses.Namespaces);
  AResult.AddPair('units', NamesJson(TSmartPaste.Certain(mNames)));
  mChoices := TJSONArray.Create;
  for mItem in mNames do
  begin
    if Length(mItem.Units) > 1 then
    begin
      mChoice := TJSONObject.Create;
      mChoice.AddPair('name', mItem.Name);
      mChoice.AddPair('units', NamesJson(mItem.Units));
      mChoices.AddElement(mChoice);
    end;
  end;
  AResult.AddPair('choices', mChoices);
  AResult.AddPair('interface', TJSONBool.Create(TSmartPaste.InInterface(ATokens, ARange.StartPos)));
end;

/// <summary>Zeichenketten aus AValues.</summary>
function StringsOf(AValues: TJSONArray): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  for mValue in AValues do
  begin
    if mValue is TJSONString then
    begin
      Result := Result + [mValue.Value];
    end;
  end;
end;

/// <summary>WorkspaceEdit mit AEdits für die Datei AUri.</summary>
function WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  mList: TJSONArray;
  mChange, mChanges: TJSONObject;
  mEdit: TTextEdit;
begin
  mList := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mChange := TJSONObject.Create;
    mChange.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mChange.AddPair('newText', mEdit.NewText);
    mList.AddElement(mChange);
  end;
  mChanges := TJSONObject.Create;
  mChanges.AddPair(AUri, mList);
  Result := TJSONObject.Create;
  Result.AddPair('changes', mChanges);
end;

class function TLspSmartPaste.Execute(const AArguments: TJSONArray; const AUri, AText: string; ATree: TSyntaxTree;
  const AUses: TUsesContext; const AInterfaceUses: TInterfaceUsesFunc): TJSONObject;
var
  mRange: TTextRange;
  mTarget: TSmartPasteTarget;
  mUses: TSmartPasteUses;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONObject) then
  begin
    raise EArgumentException.Create(cTexts[TSmartPasteText.ArgumentsUriAndRangeMissing].Text);
  end;
  mRange := TLspPositions.ReadRange(AArguments.Items[1]);
  mTarget := Default(TSmartPasteTarget);
  mTarget.Tokens := TPascalLexer.Tokenize(AText);
  Result := TJSONObject.Create;
  if (AArguments.Count < 3) or not (AArguments.Items[2] is TJSONArray) then
  begin
    AddMissing(Result, mTarget.Tokens, ATree, mRange, AUses);
    Exit;
  end;
  mTarget.Position := mRange.StartPos;
  mTarget.InterfaceUses := AInterfaceUses;
  mTarget.Namespaces := AUses.Namespaces;
  mTarget.LineBreak := TTextLines.LineBreakOf(AText);
  if TSmartPaste.UsesEdits(mTarget, StringsOf(TJSONArray(AArguments.Items[2])), mUses) then
  begin
    Result.AddPair('edit', WorkspaceEditJson(AUri, mUses.Edits));
  end
  else
  begin
    Result.AddPair('edit', TJSONNull.Create);
  end;
  Result.AddPair('added', NamesJson(mUses.Added));
  Result.AddPair('toImplementation', NamesJson(mUses.ToImplementation));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SmartPaste', cTexts);

end.
