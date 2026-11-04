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
    /// <summary>Name der neuen Unit.</summary>
    UnitName: string;
  end;

  TLspMoveClass = class
  public const
    ClientCommand = 'atlas.moveClass';
    ApplyCommand = 'atlas.server.moveClass';
  public
    /// <summary>Namensauflösung für den Kern über AResolver.</summary>
    class function Lookup(AResolver: TNameResolver): TMoveClassLookup; static;
    /// <summary>Die Code-Aktion an APosition, wenn die Klasse dort verschiebbar ist; sonst nil. Ob die Funktion
    /// eingeschaltet ist, prüft der Aufrufer. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "file": URI der neuen Unit, "warnings": [...]}; EJsonRpcError, wenn die
    /// Klasse nicht verschiebbar ist oder die Datei schon existiert. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TMoveClassContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.WorkspaceChanges;

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

class function TLspMoveClass.Actions(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  Decl: TSyntaxNode;
  Plan: TMoveClassPlan;
  Reason, Title, Name: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  Decl := TMoveClass.ClassAt(ATree, APosition);
  if Decl = nil then
  begin
    Exit;
  end;
  Name := TMoveClass.DefaultUnitName(Decl.Name);
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(TMoveClassSource.Create(AFileName, AText, ATree), APosition, Name, Lookup(AResolver), Plan,
      Reason) then
    begin
      Exit;
    end;
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

/// <summary>EJsonRpcError, wenn es die Datei ANewFile oder die Unit im Projekt schon gibt.</summary>
procedure CheckNewUnit(const AContext: TMoveClassContext; const APlan: TMoveClassPlan; const ANewFile: string);
var
  Item: TProjectUnit;
begin
  if Assigned(AContext.Exists) and AContext.Exists(ANewFile) then
  begin
    raise Failed(Format('%s gibt es schon', [ExtractFileName(ANewFile)]));
  end;
  if not AContext.HasProject then
  begin
    Exit;
  end;
  for Item in AContext.Project.Units do
  begin
    if SameText(Item.Name, APlan.NewUnit) then
    begin
      raise Failed(Format('%s steht schon im Projekt', [APlan.NewUnit]));
    end;
  end;
end;

/// <summary>Quelldateien mit Verweisen außer AFileName, jede einmal.</summary>
function UserFiles(const AReferences: TArray<TReferenceLocation>; const AFileName: string): TArray<string>;
var
  Location: TReferenceLocation;
begin
  Result := nil;
  for Location in AReferences do
  begin
    if not SameText(Location.FileName, AFileName) and IsSource(Location.FileName) and
      (IndexText(Location.FileName, Result) < 0) then
    begin
      Result := Result + [Location.FileName];
    end;
  end;
end;

/// <summary>Verweise in der Datei AUser.</summary>
function RangesOf(const AReferences: TArray<TReferenceLocation>; const AUser: string): TArray<TTextRange>;
var
  Location: TReferenceLocation;
begin
  Result := nil;
  for Location in AReferences do
  begin
    if SameText(Location.FileName, AUser) then
    begin
      Result := Result + [Location.Range];
    end;
  end;
end;

/// <summary>uses der verwendenden Units; die Hauptdatei des Projekts erhält die Unit unten mit Pfad.</summary>
procedure AddUserEdits(AChanges: TWorkspaceChanges; const AContext: TMoveClassContext; const APlan: TMoveClassPlan;
  const AReferences: TArray<TReferenceLocation>; const AFileName: string);
var
  MainSource, User, Text: string;
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
begin
  MainSource := '';
  if AContext.HasProject then
  begin
    MainSource := AContext.Project.MainSource;
  end;
  for User in UserFiles(AReferences, AFileName) do
  begin
    if not (Assigned(AContext.ReadText) and AContext.ReadText(User, Text)) then
    begin
      Continue;
    end;
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      if TMoveClass.UpdateUser(Text, Tree, APlan.Names, RangesOf(AReferences, User),
        not SameText(User, MainSource), Edits) then
      begin
        AChanges.Add(User, Edits);
      end;
    finally
      Tree.Free;
    end;
  end;
end;

class function TLspMoveClass.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TMoveClassContext): TJSONObject;
var
  Plan: TMoveClassPlan;
  Reason, NewFile: string;
  Decl: TSyntaxNode;
  Changes: TWorkspaceChanges;
  References: TArray<TReferenceLocation>;
begin
  Decl := TMoveClass.ClassAt(ATree, APosition);
  if Decl = nil then
  begin
    raise Failed('an dieser Stelle steht keine Klasse');
  end;
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(TMoveClassSource.Create(AFileName, AText, ATree), APosition, AContext.UnitName,
      Lookup(AResolver), Plan, Reason) then
    begin
      raise Failed(Reason);
    end;
    NewFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFileName), Plan.NewUnit + '.pas');
    CheckNewUnit(AContext, Plan, NewFile);
    // Verwendende Units über die Referenzsuche (#29).
    References := TLspReferences.Find(AResolver, AContext.Index, ATree, AFileName, Decl.StartPos, False,
      AContext.Files, AContext.ReadText);
  finally
    AResolver.UnpinTree;
  end;
  Changes := TWorkspaceChanges.Create;
  try
    // documentChanges: erst die neue Datei, dann die Änderungen je Datei.
    Changes.CreateFile(NewFile, Plan.Text);
    Changes.Add(AFileName, Plan.OriginEdits);
    AddUserEdits(Changes, AContext, Plan, References, AFileName);
    // Projekt: uses bzw. contains der .dpr/.dpk und DCCReference der .dproj, jeweils mit relativem Pfad.
    Changes.RegisterUnit(AContext.HasProject, AContext.Project, AContext.ReadText, NewFile, Plan.NewUnit);
    if Plan.Unresolved <> nil then
    begin
      Changes.Warn(Format('Unbekannte Herkunft von %s: Die neue Unit übernimmt dafür die uses der Ursprungs-Unit.',
        [string.Join(', ', Plan.Unresolved)]));
    end;
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson);
    Result.AddPair('file', TDocumentUris.FromPath(NewFile));
    Result.AddPair('warnings', Changes.WarningsJson);
  finally
    Changes.Free;
  end;
end;

end.
