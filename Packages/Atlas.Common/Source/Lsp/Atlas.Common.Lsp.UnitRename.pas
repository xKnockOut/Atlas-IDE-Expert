unit Atlas.Common.Lsp.UnitRename;

// uses nachziehen nach dem Umbenennen einer Unit über das Protokoll (#512):
// Befehl atlas.server.unitRenamed [alte URI, neue URI, [URIs des Bereichs]].
// Das Plugin meldet das Umbenennen aus der Projektverwaltung und schickt die
// Dateien des gewählten Bereichs (Projekt oder Projektgruppe). Antwort:
// {"enabled": false}, wenn refactoring.unitRenameFollowUp "off" ist, sonst
// {"enabled": true, "old", "new", "count": Zahl der Dateien, "edit":
// WorkspaceEdit}. Die Logik je Datei liegt in Atlas.Common.Editing.UnitRename.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.References;

type
  TLspUnitRename = class
  public const
    Command = 'atlas.server.unitRenamed';
  public
    /// <summary>Änderungen in AFiles für AOldFile → ANewFile (Pfade). Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(const AOldFile, ANewFile: string; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UnitRename,
  Atlas.Common.Lsp.Positions;

/// <summary>Änderungen einer Datei als TextDocumentEdit.</summary>
function DocumentJson(const AFileName: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Edit: TTextEdit;
  List: TJSONArray;
  Item, Identifier: TJSONObject;
begin
  Identifier := TJSONObject.Create;
  Identifier.AddPair('uri', TDocumentUris.FromPath(AFileName));
  Identifier.AddPair('version', TJSONNull.Create);
  List := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    List.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Identifier);
  Result.AddPair('edits', List);
end;

/// <summary>Umbenennungen von AOldName in der Datei AFileName; False, wenn sie ihn nicht verwendet.</summary>
function FileEdits(const AFileName, AOldName, ANewName: string; const AReadText: TReferenceReadText;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']) and Assigned(AReadText) and
    AReadText(AFileName, Text) and (Pos(LowerCase(AOldName), LowerCase(Text)) > 0);
  if not Result then
  begin
    Exit;
  end;
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Result := TUnitRename.Edits(AFileName, Text, Tree, AOldName, ANewName, AEdits);
  finally
    Tree.Free;
  end;
end;

class function TLspUnitRename.Execute(const AOldFile, ANewFile: string; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText): TJSONObject;
var
  OldName, NewName, FileName: string;
  Edits: TArray<TTextEdit>;
  Changes: TJSONArray;
  WorkspaceEdit: TJSONObject;
  Count: Integer;
begin
  OldName := TUnitRename.UnitNameOf(AOldFile);
  NewName := TUnitRename.UnitNameOf(ANewFile);
  Changes := TJSONArray.Create;
  Count := 0;
  if (OldName <> '') and (NewName <> '') and not SameText(OldName, NewName) then
  begin
    for FileName in AFiles do
    begin
      if FileEdits(FileName, OldName, NewName, AReadText, Edits) then
      begin
        Inc(Count);
        Changes.AddElement(DocumentJson(FileName, Edits));
      end;
    end;
  end;
  WorkspaceEdit := TJSONObject.Create;
  WorkspaceEdit.AddPair('documentChanges', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('enabled', TJSONBool.Create(True));
  Result.AddPair('old', OldName);
  Result.AddPair('new', NewName);
  Result.AddPair('count', TJSONNumber.Create(Count));
  Result.AddPair('edit', WorkspaceEdit);
end;

end.
