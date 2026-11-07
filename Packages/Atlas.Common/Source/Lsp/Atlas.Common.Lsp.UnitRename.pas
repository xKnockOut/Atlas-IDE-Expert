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
    cCommand = 'atlas.server.unitRenamed';
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
  mEdit: TTextEdit;
  mList: TJSONArray;
  mItem, mIdentifier: TJSONObject;
begin
  mIdentifier := TJSONObject.Create;
  mIdentifier.AddPair('uri', TDocumentUris.FromPath(AFileName));
  mIdentifier.AddPair('version', TJSONNull.Create);
  mList := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mList.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mIdentifier);
  Result.AddPair('edits', mList);
end;

/// <summary>Umbenennungen von AOldName in der Datei AFileName; False, wenn sie ihn nicht verwendet.</summary>
function FileEdits(const AFileName, AOldName, ANewName: string; const AReadText: TReferenceReadText;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']) and Assigned(AReadText) and
    AReadText(AFileName, mText) and (Pos(LowerCase(AOldName), LowerCase(mText)) > 0);
  if not Result then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TUnitRename.Edits(AFileName, mText, mTree, AOldName, ANewName, AEdits);
  finally
    mTree.Free;
  end;
end;

class function TLspUnitRename.Execute(const AOldFile, ANewFile: string; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText): TJSONObject;
var
  mOldName, mNewName, mFileName: string;
  mEdits: TArray<TTextEdit>;
  mChanges: TJSONArray;
  mWorkspaceEdit: TJSONObject;
  mCount: Integer;
begin
  mOldName := TUnitRename.UnitNameOf(AOldFile);
  mNewName := TUnitRename.UnitNameOf(ANewFile);
  mChanges := TJSONArray.Create;
  mCount := 0;
  if (mOldName <> '') and (mNewName <> '') and not SameText(mOldName, mNewName) then
  begin
    for mFileName in AFiles do
    begin
      if FileEdits(mFileName, mOldName, mNewName, AReadText, mEdits) then
      begin
        Inc(mCount);
        mChanges.AddElement(DocumentJson(mFileName, mEdits));
      end;
    end;
  end;
  mWorkspaceEdit := TJSONObject.Create;
  mWorkspaceEdit.AddPair('documentChanges', mChanges);
  Result := TJSONObject.Create;
  Result.AddPair('enabled', TJSONBool.Create(True));
  Result.AddPair('old', mOldName);
  Result.AddPair('new', mNewName);
  Result.AddPair('count', TJSONNumber.Create(mCount));
  Result.AddPair('edit', mWorkspaceEdit);
end;

end.
