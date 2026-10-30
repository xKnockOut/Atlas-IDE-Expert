unit Atlas.Common.Lsp.Overloads;

// Überladung anlegen über das Protokoll (#674):
//   - Code-Aktionen auf dem Kopf einer Routine: „Überladung anlegen (als
//     Weiterleitung)“ und „Überladung anlegen (Kopie)“, je mit dem
//     Client-Befehl atlas.createOverload [uri, position, art] (art = forward
//     bzw. copy). Geht es nicht, ist die Aktion abgeschaltet und nennt den
//     Grund.
//   - Befehl atlas.server.createOverload [uri, position, art]:
//     {"edit": WorkspaceEdit, "placeholders": [{"number", "range"}],
//     "warnings": [...]}. Die Platzhalter liegen im Text nach den Änderungen;
//     gleiche Nummern sind verknüpft, 0 ist die Endposition. Geht es nicht,
//     ein Fehler mit Grund.
//   - Den Standardwert eines weggelassenen Parameters liefert die
//     Namensauflösung: nil bei Klassen und Interfaces, das erste Element bei
//     Aufzählungen; sonst die eingebaute Regel bzw. Default(Typ).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.Overloads;

type
  TLspOverloads = class
  public const
    ClientCommand = 'atlas.createOverload';
    ApplyCommand = 'atlas.server.createOverload';
    ActionKind = 'refactor.rewrite';
    CopyName = 'copy';
    ForwardName = 'forward';
  public
    class function KindName(AKind: TOverloadKind): string; static;
    class function KindOf(const AName: string; out AKind: TOverloadKind): Boolean; static;
    /// <summary>Die Code-Aktionen an APosition. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Standardwerte über AResolver (Baum der Datei festhalten, solange gebraucht).</summary>
    class function DefaultFunc(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AText: string): TOverloadDefaultFunc; static;
    /// <summary>Antwort auf atlas.server.createOverload; EJsonRpcError mit dem Grund, wenn es nicht geht. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      const AKind: string; const ADefault: TOverloadDefaultFunc): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Text.Lines;

class function TLspOverloads.KindName(AKind: TOverloadKind): string;
begin
  if AKind = TOverloadKind.Forward then
    Result := ForwardName
  else
    Result := CopyName;
end;

class function TLspOverloads.KindOf(const AName: string; out AKind: TOverloadKind): Boolean;
begin
  Result := True;
  if SameText(AName, ForwardName) then
    AKind := TOverloadKind.Forward
  else if SameText(AName, CopyName) then
    AKind := TOverloadKind.Copy
  else
  begin
    AKind := TOverloadKind.Copy;
    Result := False;
  end;
end;

function NewAction(const AUri: string; const APosition: TTextPosition; const ATarget: TOverloadTarget;
  AKind: TOverloadKind): TJSONObject;
var
  Command: TJSONObject;
  Arguments: TJSONArray;
  Title, Reason: string;
begin
  Title := ATarget.Title(AKind);
  Reason := ATarget.Reason(AKind);
  Result := TJSONObject.Create;
  Result.AddPair('title', Title);
  Result.AddPair('kind', TLspOverloads.ActionKind);
  if Reason <> '' then
  begin
    Result.AddPair('disabled', TJSONObject.Create(TJSONPair.Create('reason', Reason)));
    Exit;
  end;
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Arguments.Add(TLspOverloads.KindName(AKind));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', TLspOverloads.ClientCommand);
  Command.AddPair('arguments', Arguments);
  Result.AddPair('command', Command);
end;

class function TLspOverloads.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Target: TOverloadTarget;
begin
  Result := nil;
  if not TOverloads.Target(AText, ATree, APosition, Target) then
    Exit;
  Result := [NewAction(AUri, APosition, Target, TOverloadKind.Forward),
    NewAction(AUri, APosition, Target, TOverloadKind.Copy)];
end;

/// <summary>Erstes Element der Aufzählung ASymbol; '' ohne.</summary>
function FirstMember(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const ASymbol: TResolvedSymbol): string;
var
  Values: TConstantValues;
  Names: TArray<string>;
begin
  Result := '';
  Values := TConstantValues.Create(ATree, AFileName, AIndex, AResolver);
  try
    if Values.EnumMembers(ASymbol, Names) and (Length(Names) > 0) then
      Result := Names[0];
  finally
    Values.Free;
  end;
end;

class function TLspOverloads.DefaultFunc(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string): TOverloadDefaultFunc;
var
  Lines: TLineTable;
begin
  Lines := TLineTable.Build(AText);
  Result :=
    function(const ATypeName: string; ATypeOffset: Integer): string
    var
      Resolved: TResolvedSymbol;
    begin
      Result := '';
      if ATypeOffset < 0 then
        Exit;
      Resolved := AResolver.ResolveType(ATree, AFileName, Lines.PositionAt(ATypeOffset));
      if not Resolved.Found then
        Exit;
      case Resolved.SymbolKind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          Result := 'nil';
        TIndexSymbolKind.EnumType:
          Result := FirstMember(AResolver, AIndex, ATree, AFileName, Resolved);
      else
        // Übrige Typarten ohne Vorgabewert.
      end;
    end;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function AnswerJson(const AUri: string; const AResult: TOverloadResult): TJSONObject;
var
  Document, Item, Edit, Change: TJSONObject;
  Items, Changes, Placeholders, Warnings: TJSONArray;
  TextEdit: TTextEdit;
  Placeholder: TOverloadPlaceholder;
  Warning: string;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Items := TJSONArray.Create;
  for TextEdit in AResult.Edits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(TextEdit.Range));
    Item.AddPair('newText', TextEdit.NewText);
    Items.AddElement(Item);
  end;
  Change := TJSONObject.Create;
  Change.AddPair('textDocument', Document);
  Change.AddPair('edits', Items);
  Changes := TJSONArray.Create;
  Changes.AddElement(Change);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Placeholders := TJSONArray.Create;
  for Placeholder in AResult.Placeholders do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('number', TJSONNumber.Create(Placeholder.Number));
    Item.AddPair('range', TLspPositions.RangeToJson(Placeholder.Range));
    Placeholders.AddElement(Item);
  end;
  Warnings := TJSONArray.Create;
  for Warning in AResult.Warnings do
    Warnings.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('placeholders', Placeholders);
  Result.AddPair('warnings', Warnings);
end;

class function TLspOverloads.Execute(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AKind: string; const ADefault: TOverloadDefaultFunc): TJSONObject;
var
  Kind: TOverloadKind;
  Target: TOverloadTarget;
  Outcome: TOverloadResult;
  Reason: string;
begin
  if not KindOf(AKind, Kind) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Art "%s"', [AKind]));
  if not TOverloads.Target(AText, ATree, APosition, Target) then
    raise Fail('Hier steht kein Kopf einer Routine mit Rumpf in dieser Unit.');
  if not TOverloads.Build(AText, ATree, Target, Kind, ADefault, Outcome, Reason) then
    raise Fail('Überladung geht nicht: ' + Reason);
  Result := AnswerJson(TDocumentUris.FromPath(AFileName), Outcome);
end;

end.
