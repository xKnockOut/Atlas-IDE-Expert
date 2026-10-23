unit Atlas.Common.Lsp.MoveClass;

// „Klasse in eigene Unit verschieben“ über das Protokoll (#103 Teil B):
//   - Code-Aktion „Klasse TFoo in eigene Unit verschieben …“ auf der ersten
//     Zeile einer Klassendeklaration, nur wenn refactoring.moveClass an ist
//     und sich die Klasse verschieben lässt. Sie trägt den Client-Befehl
//     atlas.moveClass mit [uri, position, vorgeschlagener Name]; das Plugin
//     fragt den Namen ab (Klassenname ohne T, abweichend wählbar).
//   - Befehl atlas.server.moveClass [uri, position, name]: WorkspaceEdit mit
//     documentChanges: neue Datei neben der Ursprungs-Unit anlegen und füllen,
//     Ursprungs-Unit ändern, die neue Unit in uses bzw. contains der .dpr/.dpk
//     und als DCCReference in die .dproj eintragen, und alle Units, die die
//     Klasse verwenden (Referenzsuche, #29), erhalten die neue Unit im uses.
// Die Namensauflösung bestimmt, aus welcher Unit jeder benötigte Name stammt;
// die Logik liegt in Atlas.Common.Editing.MoveClass.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.References;

type
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TMoveClassExists = reference to function(const AFileName: string): Boolean;

  TMoveClassContext = record
    Index: ISymbolIndex;
    /// <summary>Projekt der Datei; ohne Projekt wird nur die Unit angelegt.</summary>
    HasProject: Boolean;
    Project: TProjectInfo;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Exists: TMoveClassExists;
  end;

  TLspMoveClass = class
  public const
    ClientCommand = 'atlas.moveClass';
    ApplyCommand = 'atlas.server.moveClass';
  public
    /// <summary>Namensauflösung für den Kern über AResolver.</summary>
    class function Lookup(AResolver: TNameResolver): TMoveClassLookup; static;
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet und die Klasse dort verschiebbar ist; sonst nil.
    /// Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "file": URI der neuen Unit, "warnings": [...]}; EJsonRpcError, wenn die
    /// Klasse nicht verschiebbar ist oder die Datei schon existiert. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AUnitName: string; const AContext: TMoveClassContext): TJSONObject;
      static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions;

type
  TFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

procedure AddEdits(var AFiles: TArray<TFileEdits>; const AFileName: string; const AEdits: TArray<TTextEdit>);
var
  Index: Integer;
  Item: TFileEdits;
begin
  if AEdits = nil then
    Exit;
  for Index := 0 to High(AFiles) do
    if SameText(AFiles[Index].FileName, AFileName) then
    begin
      AFiles[Index].Edits := AFiles[Index].Edits + AEdits;
      Exit;
    end;
  Item.FileName := AFileName;
  Item.Edits := AEdits;
  AFiles := AFiles + [Item];
end;

function DocumentEdit(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Document, Item: TJSONObject;
  Edits: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Edits := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Edits.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Edits);
end;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Klasse verschieben: ' + AMessage);
end;

function IsSource(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']);
end;

class function TLspMoveClass.Lookup(AResolver: TNameResolver): TMoveClassLookup;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TMoveClassMeaning
    var
      Resolved: TResolvedSymbol;
    begin
      Result := Default(TMoveClassMeaning);
      Resolved := AResolver.ResolveChain(ATree, AFileName, ANames, AOffset);
      case Resolved.Kind of
        TResolvedKind.Local:
          begin
            Result.Found := True;
            Result.IsLocal := True;
          end;
        TResolvedKind.UnitName, TResolvedKind.Symbol:
          begin
            Result.Found := True;
            Result.UnitName := Resolved.UnitName;
            Result.FileName := Resolved.FileName;
            Result.Position := Resolved.Range.StartPos;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
end;

class function TLspMoveClass.Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  Decl: TSyntaxNode;
  Plan: TMoveClassPlan;
  Reason, Title, Name: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled then
    Exit;
  Decl := TMoveClass.ClassAt(ATree, APosition);
  if Decl = nil then
    Exit;
  Name := TMoveClass.DefaultUnitName(Decl.Name);
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(AFileName, AText, ATree, APosition, Name, Lookup(AResolver), Plan, Reason) then
      Exit;
  finally
    AResolver.UnpinTree;
  end;
  Title := Format('Klasse %s in eigene Unit verschieben …', [Plan.ClassName]);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Arguments.Add(Name);
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', TMoveClass.Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

class function TLspMoveClass.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AUnitName: string; const AContext: TMoveClassContext): TJSONObject;
var
  Plan: TMoveClassPlan;
  Reason, NewFile, NewUri, Text, Relative, MainSource, ProjectFile: string;
  Decl: TSyntaxNode;
  Item: TProjectUnit;
  Files: TArray<TFileEdits>;
  FileEdit: TFileEdits;
  References: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Users: TArray<string>;
  User: string;
  Ranges: TArray<TTextRange>;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Tree: TSyntaxTree;
  Changes, Warnings: TJSONArray;
  Creation, Options, WorkspaceEdit: TJSONObject;
  Known: Boolean;
begin
  Decl := TMoveClass.ClassAt(ATree, APosition);
  if Decl = nil then
    raise Failed('an dieser Stelle steht keine Klasse');
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(AFileName, AText, ATree, APosition, AUnitName, Lookup(AResolver), Plan, Reason) then
      raise Failed(Reason);
    NewFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFileName), Plan.NewUnit + '.pas');
    if Assigned(AContext.Exists) and AContext.Exists(NewFile) then
      raise Failed(Format('%s gibt es schon', [ExtractFileName(NewFile)]));
    if AContext.HasProject then
      for Item in AContext.Project.Units do
        if SameText(Item.Name, Plan.NewUnit) then
          raise Failed(Format('%s steht schon im Projekt', [Plan.NewUnit]));
    // Verwendende Units über die Referenzsuche (#29).
    References := TLspReferences.Find(AResolver, AContext.Index, ATree, AFileName, Decl.StartPos, False,
      AContext.Files, AContext.ReadText);
  finally
    AResolver.UnpinTree;
  end;
  Files := nil;
  AddEdits(Files, AFileName, Plan.OriginEdits);
  MainSource := '';
  if AContext.HasProject then
    MainSource := AContext.Project.MainSource;
  Users := nil;
  for Location in References do
  begin
    Known := SameText(Location.FileName, AFileName) or not IsSource(Location.FileName);
    for User in Users do
      if SameText(User, Location.FileName) then
        Known := True;
    if not Known then
      Users := Users + [Location.FileName];
  end;
  for User in Users do
  begin
    if not (Assigned(AContext.ReadText) and AContext.ReadText(User, Text)) then
      Continue;
    Ranges := nil;
    for Location in References do
      if SameText(Location.FileName, User) then
        Ranges := Ranges + [Location.Range];
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      // Die Hauptdatei des Projekts erhält die Unit unten mit Pfad.
      if TMoveClass.UpdateUser(Text, Tree, Plan.OriginUnit, Plan.NewUnit, Plan.ClassName, Ranges,
        not SameText(User, MainSource), Edits) then
        AddEdits(Files, User, Edits);
    finally
      Tree.Free;
    end;
  end;
  // Projekt: uses bzw. contains der .dpr/.dpk und DCCReference der .dproj, jeweils mit relativem Pfad.
  Warnings := TJSONArray.Create;
  if AContext.HasProject then
  begin
    if (MainSource <> '') and Assigned(AContext.ReadText) and AContext.ReadText(MainSource, Text) then
    begin
      Relative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(MainSource), NewFile);
      if TUnitTemplates.UnitProgramEdit(Text, Plan.NewUnit, Relative, Edit) then
        AddEdits(Files, MainSource, [Edit])
      else
        Warnings.Add(Format('%s hat kein uses bzw. contains für die neue Unit', [ExtractFileName(MainSource)]));
    end;
    ProjectFile := AContext.Project.FileName;
    if Assigned(AContext.ReadText) and AContext.ReadText(ProjectFile, Text) then
    begin
      Relative := TTestUnits.RelativePath(TProjectPaths.DirectoryOf(ProjectFile), NewFile);
      if (Pos('"' + Relative + '"', Text) = 0) and
        TUnitTemplates.ProjectEdit(Text, Relative, '', TFormKind.Form, False, Edit) then
        AddEdits(Files, ProjectFile, [Edit]);
    end;
  end
  else
    Warnings.Add('Kein Projekt geladen: Die neue Unit steht in keiner .dpr, .dpk oder .dproj.');
  if Plan.Unresolved <> nil then
    Warnings.Add(Format('Unbekannte Herkunft von %s: Die neue Unit übernimmt dafür die uses der Ursprungs-Unit.',
      [string.Join(', ', Plan.Unresolved)]));
  // documentChanges: erst die neue Datei, dann die Änderungen je Datei.
  NewUri := TDocumentUris.FromPath(NewFile);
  Changes := TJSONArray.Create;
  Creation := TJSONObject.Create;
  Creation.AddPair('kind', 'create');
  Creation.AddPair('uri', NewUri);
  Options := TJSONObject.Create;
  Options.AddPair('ignoreIfExists', TJSONBool.Create(False));
  Creation.AddPair('options', Options);
  Changes.AddElement(Creation);
  Changes.AddElement(DocumentEdit(NewUri, [TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), Plan.Text)]));
  for FileEdit in Files do
    Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(FileEdit.FileName), FileEdit.Edits));
  WorkspaceEdit := TJSONObject.Create;
  WorkspaceEdit.AddPair('documentChanges', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('edit', WorkspaceEdit);
  Result.AddPair('file', NewUri);
  Result.AddPair('warnings', Warnings);
end;

end.
