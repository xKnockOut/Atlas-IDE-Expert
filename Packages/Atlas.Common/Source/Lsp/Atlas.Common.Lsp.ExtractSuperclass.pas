unit Atlas.Common.Lsp.ExtractSuperclass;

// „Basisklasse herauslösen“ über das Protokoll (#713):
//   - Code-Aktion „Basisklasse aus TFoo herauslösen …“ auf der Kopfzeile einer
//     Klasse mit Feldern, Methoden oder Properties, nur mit
//     refactoring.extractSuperclass. Sie trägt den Client-Befehl
//     atlas.extractSuperclass mit [uri, position].
//   - atlas.server.extractSuperclass.prepare [uri, position]: Klasse, eigene
//     Unit, vorgeschlagener Name (refactoring.extractSuperclassNameSuffix),
//     Kandidaten (id, name, kind, display, visibility, checked, enabled,
//     reason, canAbstract, abstract nach refactoring.extractSuperclassMethodMode,
//     needs), Hinweise, vorgeschlagene neue Unit (units) und das Ziel nach
//     refactoring.extractSuperclassTarget (unit: '' = dieselbe Unit).
//   - atlas.server.extractSuperclass [uri, position, {name, unit, members,
//     abstract}]: WorkspaceEdit mit Änderungsanmerkung. unit leer oder der
//     eigene Name: Die Basisklasse steht über der Klasse. Sonst entsteht sie
//     zuerst dort und wandert dann mit „Klasse verschieben“ (#103) in die neue
//     Unit: uses der neuen Unit aus den benötigten Namen, die alte Unit bindet
//     die neue ein, Eintrag ins Projekt; Kreisverweise und Zugriffe auf
//     implementation-lokale Namen brechen dort mit Grund ab. Gehobene
//     Sichtbarkeit nach refactoring.extractSuperclassRaiseVisibility.
// Die Logik liegt in Atlas.Common.Editing.ExtractSuperclass.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TExtractSuperclassExists = reference to function(const AFileName: string): Boolean;

  TExtractSuperclassContext = record
    Index: ISymbolIndex;
    HasProject: Boolean;
    Project: TProjectInfo;
    ReadText: TReferenceReadText;
    Exists: TExtractSuperclassExists;
    /// <summary>refactoring.extractSuperclassTarget, …NameSuffix, …MethodMode, …RaiseVisibility.</summary>
    Target: string;
    NameSuffix: string;
    MethodMode: string;
    RaiseVisibility: string;
  end;

  TLspExtractSuperclass = class
  public const
    ClientCommand = 'atlas.extractSuperclass';
    PrepareCommand = 'atlas.server.extractSuperclass.prepare';
    ApplyCommand = 'atlas.server.extractSuperclass';
    AnnotationId = 'extractSuperclass';
  public
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet und die Klasse dort Kandidaten hat; sonst nil.
    /// Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Antwort auf prepare; EJsonRpcError ohne Klasse oder Kandidaten. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const AContext: TExtractSuperclassContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "file": URI der Unit mit der Basisklasse, "line":
    /// Zeile dort (0-basiert), "name", "moved"}; EJsonRpcError bei ungültiger Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; ARequest: TJSONValue; const AContext: TExtractSuperclassContext): TJSONObject;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.ExtractInterface,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.ExtractSuperclass,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.WorkspaceChanges;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Basisklasse herauslösen: ' + AMessage);
end;

function KindText(AKind: TTransferKind): string;
begin
  case AKind of
    TTransferKind.Field:
      Result := 'field';
    TTransferKind.Property_:
      Result := 'property';
  else
    Result := 'method';
  end;
end;

/// <summary>Ist AName ein Interface: im Baum oder im Index.</summary>
function InterfaceCheck(ATree: TSyntaxTree; const AIndex: ISymbolIndex): TIsInterfaceType;
begin
  Result :=
    function(const AName: string): Boolean
    var
      Found: Boolean;
      Location: TSymbolLocation;
    begin
      Found := False;
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := not Found;
          if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
            (ANode.FindChild(TSyntaxKind.InterfaceType) <> nil) then
          begin
            Found := True;
          end;
        end);
      if not Found and (AIndex <> nil) then
      begin
        for Location in AIndex.FindSymbols(AName) do
        begin
          if (Location.Symbol.Kind = TIndexSymbolKind.InterfaceType) and (Location.Symbol.Container = '') then
          begin
            Found := True;
          end;
        end;
      end;
      Result := Found;
    end;
end;

/// <summary>Ist AName in der Unit oder im Index als Typ vergeben?</summary>
function NameCheck(ATree: TSyntaxTree; const AIndex: ISymbolIndex): TNameInUse;
begin
  Result :=
    function(const AName: string): Boolean
    var
      Found: Boolean;
      Location: TSymbolLocation;
    begin
      Found := False;
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := not Found;
          if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
          begin
            Found := True;
          end;
        end);
      if not Found and (AIndex <> nil) then
      begin
        for Location in AIndex.FindSymbols(AName) do
        begin
          if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.ClassType,
            TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
            TIndexSymbolKind.TypeAlias]) then
          begin
            Found := True;
          end;
        end;
      end;
      Result := Found;
    end;
end;

class function TLspExtractSuperclass.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Info: TSuperclassInfo;
  Reason, Title: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) or (TExtractSuperclass.ClassAt(ATree, APosition.Line) = nil) then
  begin
    Exit;
  end;
  if not TExtractSuperclass.Prepare(TClassSource.Create(ATree, AText, APosition.Line), 'Base', nil, Info,
    Reason) then
  begin
    Exit;
  end;
  Title := Format('Basisklasse aus %s herauslösen …', [Info.ClassName]);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', TExtractSuperclass.Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

class function TLspExtractSuperclass.Prepare(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TExtractSuperclassContext): TJSONObject;
var
  Info: TSuperclassInfo;
  Reason, Note, NewUnit: string;
  Item: TTransferCandidate;
  List, Notes, Units, Needs: TJSONArray;
  Entry: TJSONObject;
  Need: Integer;
begin
  if not TExtractSuperclass.Prepare(TClassSource.Create(ATree, AText, APosition.Line), AContext.NameSuffix,
    NameCheck(ATree, AContext.Index), Info, Reason) then
  begin
    raise Failed(Reason);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('className', Info.ClassName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  Result.AddPair('name', Info.SuggestedName);
  Result.AddPair('ancestor', Info.Ancestor);
  List := TJSONArray.Create;
  for Item in Info.Candidates do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('id', TJSONNumber.Create(Item.Id));
    Entry.AddPair('name', Item.Name);
    Entry.AddPair('kind', KindText(Item.Kind));
    Entry.AddPair('display', Item.Display);
    Entry.AddPair('visibility', TClassEdits.VisibilityName(Item.Visibility));
    Entry.AddPair('checked', TJSONBool.Create(False));
    Entry.AddPair('enabled', TJSONBool.Create(Item.Enabled));
    Entry.AddPair('reason', Item.Reason);
    Entry.AddPair('canAbstract', TJSONBool.Create(Item.CanAbstract));
    Entry.AddPair('abstract', TJSONBool.Create(Item.CanAbstract and SameText(AContext.MethodMode, 'abstract')));
    Needs := TJSONArray.Create;
    for Need in Item.Needs do
    begin
      Needs.AddElement(TJSONNumber.Create(Need));
    end;
    Entry.AddPair('needs', Needs);
    List.AddElement(Entry);
  end;
  Result.AddPair('candidates', List);
  Notes := TJSONArray.Create;
  for Note in Info.Notes do
  begin
    Notes.Add(Note);
  end;
  Result.AddPair('notes', Notes);
  // Ziele: dieselbe Unit oder eine neue mit dem Namen der Basisklasse ohne T.
  NewUnit := TMoveClass.DefaultUnitName(Info.SuggestedName);
  Units := TJSONArray.Create;
  Units.Add(NewUnit);
  Result.AddPair('units', Units);
  if SameText(AContext.Target, 'newUnit') then
  begin
    Result.AddPair('unit', NewUnit);
  end
  else
  begin
    Result.AddPair('unit', '');
  end;
end;

function Ids(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      if Item is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(Item).AsInt];
      end;
    end;
  end;
end;

function Field(AObject: TJSONObject; const AKey: string): string;
begin
  Result := '';
  if AObject.GetValue(AKey) <> nil then
  begin
    Result := Trim(AObject.GetValue(AKey).Value);
  end;
end;

/// <summary>Fehlerfrei parsen wie vorher; sonst EJsonRpcError mit der ersten Meldung.</summary>
procedure CheckParses(const AFileName, ANewText: string; ABefore: Integer);
var
  Check: TSyntaxTree;
begin
  Check := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(Check.Diagnostics) > ABefore then
    begin
      raise Failed(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
        [ExtractFileName(AFileName), Check.Diagnostics[0].StartPos.Line + 1, Check.Diagnostics[0].Message]));
    end;
  finally
    Check.Free;
  end;
end;

class function TLspExtractSuperclass.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; ARequest: TJSONValue;
  const AContext: TExtractSuperclassContext): TJSONObject;
var
  Body: TJSONObject;
  Request: TSuperclassRequest;
  Plan: TSuperclassPlan;
  Move: TMoveClassPlan;
  UnitName, OwnUnit, Reason, NewFile, NewText, Description: string;
  Item: TProjectUnit;
  Changes: TWorkspaceChanges;
  Tree: TSyntaxTree;
  Warning: string;
begin
  if not (ARequest is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Anfrage mit name, unit und members fehlt');
  end;
  Body := TJSONObject(ARequest);
  Request := Default(TSuperclassRequest);
  Request.Name := Field(Body, 'name');
  Request.Members := Ids(Body, 'members');
  Request.Abstract := Ids(Body, 'abstract');
  UnitName := Field(Body, 'unit');
  OwnUnit := TUsesClauses.OwnName(ATree.Tokens);
  Request.SameUnit := (UnitName = '') or SameText(UnitName, OwnUnit);
  if SameText(AContext.RaiseVisibility, 'strictProtected') then
  begin
    Request.RaiseVisibility := TClassVisibility.StrictProtected;
  end
  else
  begin
    Request.RaiseVisibility := TClassVisibility.Protected_;
  end;
  if not Request.SameUnit and not IsIdentifier(StringReplace(UnitName, '.', '_', [rfReplaceAll])) then
  begin
    raise Failed(Format('"%s" ist kein gültiger Unit-Name.', [UnitName]));
  end;
  if not TExtractSuperclass.Plan(TClassSource.Create(ATree, AText, APosition.Line), Request,
    InterfaceCheck(ATree, AContext.Index), NameCheck(ATree, AContext.Index), Plan, Reason) then
  begin
    raise Failed(Reason);
  end;
  Changes := TWorkspaceChanges.Create;
  try
    for Warning in Plan.Warnings do
    begin
      Changes.Warn(Warning);
    end;
    NewFile := AFileName;
    NewText := Plan.Text;
    if not Request.SameUnit then
    begin
      // Die Basisklasse steht jetzt über der Klasse; „Klasse verschieben“ bringt sie in die neue Unit.
      NewFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFileName), UnitName + '.pas');
      if Assigned(AContext.Exists) and AContext.Exists(NewFile) then
      begin
        raise Failed(Format('%s gibt es schon.', [ExtractFileName(NewFile)]));
      end;
      if AContext.HasProject then
      begin
        for Item in AContext.Project.Units do
        begin
          if SameText(Item.Name, UnitName) then
          begin
            raise Failed(Format('%s steht schon im Projekt.', [UnitName]));
          end;
        end;
      end;
      Tree := TSyntaxTreeCache.Parse(Plan.Text);
      try
        AResolver.PinTree(Tree, AFileName);
        try
          if not TMoveClass.Plan(TMoveClassSource.Create(AFileName, Plan.Text, Tree),
            TTextPosition.Create(Plan.BaseLine, 0), UnitName, TLspMoveClass.Lookup(AResolver), Move, Reason) then
          begin
            raise Failed(Format('Die Basisklasse lässt sich nicht in eine eigene Unit verschieben: %s', [Reason]));
          end;
        finally
          AResolver.UnpinTree;
        end;
      finally
        Tree.Free;
      end;
      NewText := TTextChanges.Apply(Plan.Text, Move.OriginEdits);
      Changes.CreateFile(NewFile, Move.Text);
      if Move.Unresolved <> nil then
      begin
        Changes.Warn(Format('Unbekannte Herkunft von %s: Die neue Unit übernimmt dafür die uses der alten.',
          [string.Join(', ', Move.Unresolved)]));
      end;
    end;
    CheckParses(AFileName, NewText, Length(ATree.Diagnostics));
    Changes.Add(AFileName, TTextChanges.Diff(AText, NewText));
    if not Request.SameUnit then
    begin
      Changes.RegisterUnit(AContext.HasProject, AContext.Project, AContext.ReadText, NewFile, UnitName);
    end;
    Description := Format('%s mit %d Mitgliedern, %d Dateien', [Plan.BaseName,
      Length(Plan.Moved) + Length(Plan.Abstracts), Changes.FileCount]);
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson(AnnotationId, 'Basisklasse herauslösen', Description));
    Result.AddPair('warnings', Changes.WarningsJson);
    Result.AddPair('file', TDocumentUris.FromPath(NewFile));
    // Zeile der Basisklasse in derselben Unit; in der neuen Unit vom Anfang an.
    if Request.SameUnit then
    begin
      Result.AddPair('line', TJSONNumber.Create(Plan.BaseLine));
    end
    else
    begin
      Result.AddPair('line', TJSONNumber.Create(0));
    end;
    Result.AddPair('name', Plan.BaseName);
    Result.AddPair('moved', TJSONNumber.Create(Length(Plan.Moved) + Length(Plan.Abstracts)));
  finally
    Changes.Free;
  end;
end;

end.
