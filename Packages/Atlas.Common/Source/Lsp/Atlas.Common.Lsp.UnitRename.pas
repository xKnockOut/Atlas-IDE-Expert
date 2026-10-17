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

class function TLspUnitRename.Execute(const AOldFile, ANewFile: string; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText): TJSONObject;
var
  OldName, NewName, FileName, Text: string;
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Changes, List: TJSONArray;
  Document, Item, Identifier, WorkspaceEdit: TJSONObject;
  Count: Integer;
begin
  OldName := TUnitRename.UnitNameOf(AOldFile);
  NewName := TUnitRename.UnitNameOf(ANewFile);
  Changes := TJSONArray.Create;
  Count := 0;
  if (OldName <> '') and (NewName <> '') and not SameText(OldName, NewName) then
    for FileName in AFiles do
    begin
      if not MatchText(ExtractFileExt(FileName), ['.pas', '.dpr', '.dpk', '.inc']) or
        not (Assigned(AReadText) and AReadText(FileName, Text)) or (Pos(LowerCase(OldName), LowerCase(Text)) = 0) then
        Continue;
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        if not TUnitRename.Edits(FileName, Text, Tree, OldName, NewName, Edits) then
          Continue;
      finally
        Tree.Free;
      end;
      Inc(Count);
      Identifier := TJSONObject.Create;
      Identifier.AddPair('uri', TDocumentUris.FromPath(FileName));
      Identifier.AddPair('version', TJSONNull.Create);
      List := TJSONArray.Create;
      for Edit in Edits do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
        Item.AddPair('newText', Edit.NewText);
        List.AddElement(Item);
      end;
      Document := TJSONObject.Create;
      Document.AddPair('textDocument', Identifier);
      Document.AddPair('edits', List);
      Changes.AddElement(Document);
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
