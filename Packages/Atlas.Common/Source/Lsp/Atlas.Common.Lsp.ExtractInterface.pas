unit Atlas.Common.Lsp.ExtractInterface;

// „Interface aus Klasse herauslösen“ über das Protokoll (#664):
//   - Code-Aktion „Interface aus TFoo herauslösen …“ auf der Kopfzeile einer
//     Klasse mit wählbaren Mitgliedern, nur mit refactoring.extractInterface.
//     Sie trägt den Client-Befehl atlas.extractInterface mit [uri, position];
//     das Plugin holt die Kandidaten, zeigt den Dialog und dann die Vorschau.
//   - atlas.server.extractInterface.prepare [uri, position]: Klasse,
//     vorgeschlagener Name, Kandidaten (id, name, kind, display, visibility,
//     checked, enabled, reason), Hinweise und die Units des Projekts als Ziele.
//   - atlas.server.extractInterface [uri, position, {name, unit, members}]:
//     WorkspaceEdit mit Änderungsanmerkung für die Vorschau. unit leer oder
//     der eigene Name: dieselbe Unit. Eine Unit des Projekts bzw. des Index
//     erhält das Interface vor ihrer implementation und die Units der Typen
//     in den Signaturen in ihr uses; sonst entsteht eine neue Unit neben der
//     Klasse (und kommt ins Projekt). Die Unit der Klasse erhält die Ziel-Unit
//     in ihr uses. Braucht das Interface einen Typ aus der Unit der Klasse,
//     die es selbst im interface einbindet, bricht Atlas ab (Kreisverweis).
// Die Logik liegt in Atlas.Common.Editing.ExtractInterface.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ExtractInterface,
  Atlas.Common.Lsp.References;

type
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TExtractExists = reference to function(const AFileName: string): Boolean;

  TExtractInterfaceContext = record
    Index: ISymbolIndex;
    HasProject: Boolean;
    Project: TProjectInfo;
    ReadText: TReferenceReadText;
    Exists: TExtractExists;
    /// <summary>GUID für das Interface; leer = neue GUID.</summary>
    Guid: string;
  end;

  TLspExtractInterface = class
  public const
    ClientCommand = 'atlas.extractInterface';
    PrepareCommand = 'atlas.server.extractInterface.prepare';
    ApplyCommand = 'atlas.server.extractInterface';
    AnnotationId = 'extractInterface';
  public
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet und die Klasse dort wählbare Mitglieder hat;
    /// sonst nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Vorfahren über Baum und Index (für TExtractInterface.Supports).</summary>
    class function AncestorsLookup(ATree: TSyntaxTree; const AIndex: ISymbolIndex): TClassAncestorsLookup; static;
    /// <summary>Antwort auf prepare; EJsonRpcError ohne Klasse oder Kandidaten. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const AContext: TExtractInterfaceContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "file": URI der Ziel-Unit, "name": Interface};
    /// EJsonRpcError bei ungültiger Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; ARequest: TJSONValue; const AContext: TExtractInterfaceContext): TJSONObject;
      static;
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
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.PropertyFromAccessors,
  Atlas.Common.Lsp.WorkspaceChanges;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Interface herauslösen: ' + AMessage);
end;

function VisibilityText(AVisibility: TClassVisibility): string;
begin
  Result := TClassEdits.VisibilityName(AVisibility);
end;

function MethodPointer(const AIndex: ISymbolIndex): TIsMethodPointer;
begin
  Result :=
    function(const ATypeName: string): Boolean
    begin
      Result := TLspPropertyFromAccessors.IsProcedural(ATypeName, AIndex);
    end;
end;

class function TLspExtractInterface.AncestorsLookup(ATree: TSyntaxTree;
  const AIndex: ISymbolIndex): TClassAncestorsLookup;
begin
  Result :=
    function(const AClassName: string; out AAncestors: TArray<string>): Boolean
    var
      Decl, Body: TSyntaxNode;
      Index: Integer;
      Location: TSymbolLocation;
    begin
      AAncestors := nil;
      Decl := TClassLayout.DeclNamed(ATree, AClassName);
      if Decl <> nil then
      begin
        Body := Decl.FindChild(TSyntaxKind.ClassType);
        for Index := 0 to Body.ChildCount - 1 do
          if Body[Index].Kind = TSyntaxKind.TypeReference then
            AAncestors := AAncestors + [Body[Index].Name]
          else
            Break;
        Exit(True);
      end;
      if AIndex <> nil then
        for Location in AIndex.FindSymbols(AClassName) do
          if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
          begin
            AAncestors := Location.Symbol.Ancestors;
            Exit(True);
          end;
      Result := False;
    end;
end;

class function TLspExtractInterface.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Info: TExtractInterfaceInfo;
  Reason, Title: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) or (TExtractInterface.ClassAt(ATree, APosition.Line) = nil) then
    Exit;
  if not TExtractInterface.Prepare(ATree, AText, APosition.Line, nil, nil, Info, Reason) then
    Exit;
  Title := Format('Interface aus %s herauslösen …', [Info.ClassName]);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', TExtractInterface.Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

class function TLspExtractInterface.Prepare(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TExtractInterfaceContext): TJSONObject;
var
  Info: TExtractInterfaceInfo;
  Reason, Note: string;
  Item: TExtractCandidate;
  List, Notes, Units: TJSONArray;
  Entry: TJSONObject;
  ProjectUnit: TProjectUnit;
begin
  if not TExtractInterface.Prepare(ATree, AText, APosition.Line, AncestorsLookup(ATree, AContext.Index),
    MethodPointer(AContext.Index), Info, Reason) then
    raise Failed(Reason);
  Result := TJSONObject.Create;
  Result.AddPair('className', Info.ClassName);
  Result.AddPair('name', Info.SuggestedName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  List := TJSONArray.Create;
  for Item in Info.Candidates do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('id', TJSONNumber.Create(Item.Id));
    Entry.AddPair('name', Item.Name);
    if Item.Kind = TExtractCandidateKind.Property_ then
      Entry.AddPair('kind', 'property')
    else
      Entry.AddPair('kind', 'method');
    Entry.AddPair('display', Item.Display);
    Entry.AddPair('visibility', VisibilityText(Item.Visibility));
    Entry.AddPair('checked', TJSONBool.Create(Item.Checked));
    Entry.AddPair('enabled', TJSONBool.Create(Item.Enabled));
    Entry.AddPair('reason', Item.Reason);
    List.AddElement(Entry);
  end;
  Result.AddPair('candidates', List);
  Notes := TJSONArray.Create;
  for Note in Info.Notes do
    Notes.Add(Note);
  Result.AddPair('notes', Notes);
  Units := TJSONArray.Create;
  if AContext.HasProject then
    for ProjectUnit in AContext.Project.Units do
      Units.Add(ProjectUnit.Name);
  Result.AddPair('units', Units);
end;

function ReadRequest(ARequest: TJSONValue; out AName, AUnit: string): TArray<Integer>;
var
  Item: TJSONValue;
  Members: TJSONValue;
begin
  if not (ARequest is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Anfrage mit name, unit und members fehlt');
  AName := '';
  AUnit := '';
  if TJSONObject(ARequest).GetValue('name') <> nil then
    AName := Trim(TJSONObject(ARequest).GetValue('name').Value);
  if TJSONObject(ARequest).GetValue('unit') <> nil then
    AUnit := Trim(TJSONObject(ARequest).GetValue('unit').Value);
  Result := nil;
  Members := TJSONObject(ARequest).GetValue('members');
  if Members is TJSONArray then
    for Item in TJSONArray(Members) do
      if Item is TJSONNumber then
        Result := Result + [TJSONNumber(Item).AsInt];
end;

/// <summary>Datei der Unit AUnitName aus Projekt oder Index; '' ohne.</summary>
function UnitFile(const AContext: TExtractInterfaceContext; const AUnitName: string): string;
var
  ProjectUnit: TProjectUnit;
  UnitIndex: TUnitIndex;
begin
  if AContext.HasProject then
    for ProjectUnit in AContext.Project.Units do
      if SameText(ProjectUnit.Name, AUnitName) and (ProjectUnit.FileName <> '') then
        Exit(ProjectUnit.FileName);
  if (AContext.Index <> nil) and AContext.Index.FindUnit(AUnitName, UnitIndex) and (UnitIndex.FileName <> '') then
    Exit(UnitIndex.FileName);
  Result := '';
end;

class function TLspExtractInterface.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; ARequest: TJSONValue;
  const AContext: TExtractInterfaceContext): TJSONObject;
var
  Name, UnitName, OwnUnit, TargetFile, TargetText, Reason, TypeName, LineBreak: string;
  Members: TArray<Integer>;
  Request: TExtractInterfaceRequest;
  Plan: TExtractInterfacePlan;
  Lookup: TMoveClassLookup;
  Meaning: TMoveClassMeaning;
  Needed, TargetUses: TArray<string>;
  NeedsOwn, IsNew: Boolean;
  TargetTree: TSyntaxTree;
  Edit: TTextEdit;
  Edits, ClassEdits: TArray<TTextEdit>;
  Changes: TWorkspaceChanges;
  Before, Count: Integer;
  Check: TSyntaxTree;
  NewText, Description: string;
begin
  Members := ReadRequest(ARequest, Name, UnitName);
  OwnUnit := TUsesClauses.OwnName(ATree.Tokens);
  Request := Default(TExtractInterfaceRequest);
  Request.Name := Name;
  Request.Members := Members;
  Request.Guid := AContext.Guid;
  if Request.Guid = '' then
    Request.Guid := TGUID.NewGuid.ToString;
  Request.SameUnit := (UnitName = '') or SameText(UnitName, OwnUnit);
  if not Request.SameUnit and not IsIdentifier(StringReplace(UnitName, '.', '_', [rfReplaceAll])) then
    raise Failed(Format('"%s" ist kein gültiger Unit-Name.', [UnitName]));
  LineBreak := TTextLines.LineBreakOf(AText);
  AResolver.PinTree(ATree, AFileName);
  try
    if not TExtractInterface.Plan(ATree, AText, APosition.Line, Request, AncestorsLookup(ATree, AContext.Index),
      function(const AName: string): Boolean
      var
        Resolved: TResolvedSymbol;
      begin
        Resolved := AResolver.ResolveChain(ATree, AFileName, [AName], TExtractInterface.ClassAt(ATree,
          APosition.Line).StartOffset);
        Result := Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.UnitName];
      end, MethodPointer(AContext.Index), Plan, Reason) then
      raise Failed(Reason);
    // Units der Typen in den Signaturen (nur für eine andere Ziel-Unit).
    Needed := nil;
    NeedsOwn := False;
    if not Request.SameUnit then
    begin
      Lookup := TLspMoveClass.Lookup(AResolver);
      for TypeName in Plan.TypeNames do
      begin
        Meaning := Lookup(ATree, AFileName, [TypeName], Plan.ClassOffset);
        if not Meaning.Found or Meaning.IsLocal or (Meaning.UnitName = '') or SameText(Meaning.UnitName, 'System') or
          SameText(Meaning.UnitName, UnitName) then
          Continue;
        if SameText(Meaning.UnitName, OwnUnit) then
        begin
          if Plan.InInterface then
            raise Failed(Format('%s stammt aus %s, die %s im interface einbinden müsste (Kreisverweis). ' +
              'Das Interface bitte in derselben Unit anlegen.', [TypeName, OwnUnit, UnitName]));
          NeedsOwn := True;
          Continue;
        end;
        if IndexText(Meaning.UnitName, Needed) < 0 then
          Needed := Needed + [Meaning.UnitName];
      end;
      if NeedsOwn then
        Needed := Needed + [OwnUnit];
    end;
  finally
    AResolver.UnpinTree;
  end;
  Changes := TWorkspaceChanges.Create;
  try
    for Reason in Plan.Warnings do
      Changes.Warn(Reason);
    ClassEdits := Plan.Edits;
    TargetFile := AFileName;
    if not Request.SameUnit then
    begin
      // Die Unit der Klasse bindet die Ziel-Unit ein (im Abschnitt der Klasse).
      if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), UnitName, nil) and
        TUsesClauses.AddUnit(ATree.Tokens, Plan.ClassOffset, UnitName, LineBreak, Edit) then
        ClassEdits := ClassEdits + [Edit];
      TargetFile := UnitFile(AContext, UnitName);
      IsNew := TargetFile = '';
      if IsNew then
      begin
        TargetFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFileName), UnitName + '.pas');
        if Assigned(AContext.Exists) and AContext.Exists(TargetFile) then
          raise Failed(Format('%s gibt es schon, gehört aber nicht zum Projekt.', [ExtractFileName(TargetFile)]));
        Changes.CreateFile(TargetFile, TExtractInterface.NewUnitText(UnitName, Plan.Declaration, Needed, LineBreak));
      end
      else
      begin
        if not (Assigned(AContext.ReadText) and AContext.ReadText(TargetFile, TargetText)) then
          raise Failed(Format('%s lässt sich nicht lesen.', [ExtractFileName(TargetFile)]));
        TargetTree := TSyntaxTreeCache.Parse(TargetText);
        try
          if TClassLayout.DeclNamed(TargetTree, Name) <> nil then
            raise Failed(Format('Der Name %s ist in %s schon vergeben.', [Name, UnitName]));
          if not TExtractInterface.InsertIntoUnit(TargetTree, TargetText, Plan.Declaration, Edit) then
            raise Failed(Format('%s hat keinen interface-Teil.', [UnitName]));
          // Fehlende uses der Ziel-Unit in einem Schritt (eine Einfügung), dann das Interface.
          TargetUses := nil;
          for TypeName in Needed do
            if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(TargetTree.Tokens), TypeName, nil) then
              TargetUses := TargetUses + [TypeName];
          Edits := [Edit];
          if (TargetUses <> nil) and TUsesClauses.AddUnit(TargetTree.Tokens, 0, string.Join(', ', TargetUses),
            TTextLines.LineBreakOf(TargetText), Edit) then
            Edits := Edits + [Edit];
          NewText := TTextChanges.Apply(TargetText, Edits);
          // Ergebnis prüfen.
          Check := TSyntaxTreeCache.Parse(NewText);
          try
            if Length(Check.Diagnostics) > Length(TargetTree.Diagnostics) then
              raise Failed(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
                [ExtractFileName(TargetFile), Check.Diagnostics[0].StartPos.Line + 1, Check.Diagnostics[0].Message]));
          finally
            Check.Free;
          end;
          Changes.Add(TargetFile, TTextChanges.Diff(TargetText, NewText));
        finally
          TargetTree.Free;
        end;
      end;
    end
    else
      IsNew := False;
    // Die Unit der Klasse muss weiter fehlerfrei parsen.
    NewText := TTextChanges.Apply(AText, ClassEdits);
    Check := TSyntaxTreeCache.Parse(NewText);
    try
      Before := Length(ATree.Diagnostics);
      if Length(Check.Diagnostics) > Before then
        raise Failed(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
          [ExtractFileName(AFileName), Check.Diagnostics[0].StartPos.Line + 1, Check.Diagnostics[0].Message]));
    finally
      Check.Free;
    end;
    Changes.Add(AFileName, ClassEdits);
    if IsNew then
      Changes.RegisterUnit(AContext.HasProject, AContext.Project, AContext.ReadText, TargetFile, UnitName);
    Count := Length(Plan.Methods);
    Description := Format('%s mit %d Methoden, %d Dateien', [Name, Count, Changes.FileCount]);
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson(AnnotationId, 'Interface herauslösen', Description));
    Result.AddPair('warnings', Changes.WarningsJson);
    Result.AddPair('file', TDocumentUris.FromPath(TargetFile));
    Result.AddPair('name', Name);
    Result.AddPair('methods', TJSONNumber.Create(Count));
  finally
    Changes.Free;
  end;
end;

end.
