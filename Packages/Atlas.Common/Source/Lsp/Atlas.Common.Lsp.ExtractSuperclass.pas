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
    /// <summary>Auflöser für Execute; gehört dem Aufrufer. Prepare braucht ihn nicht.</summary>
    Resolver: TNameResolver;
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
    class function Execute(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      ARequest: TJSONValue; const AContext: TExtractSuperclassContext): TJSONObject; static;
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

/// <summary>Ein Kandidat für prepare; abstract nach refactoring.extractSuperclassMethodMode (AMethodMode).</summary>
function CandidateJson(const AItem: TTransferCandidate; const AMethodMode: string): TJSONObject;
var
  mNeeds: TJSONArray;
  mNeed: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(AItem.Id));
  Result.AddPair('name', AItem.Name);
  Result.AddPair('kind', KindText(AItem.Kind));
  Result.AddPair('display', AItem.Display);
  Result.AddPair('visibility', TClassEdits.VisibilityName(AItem.Visibility));
  Result.AddPair('checked', TJSONBool.Create(False));
  Result.AddPair('enabled', TJSONBool.Create(AItem.Enabled));
  Result.AddPair('reason', AItem.Reason);
  Result.AddPair('canAbstract', TJSONBool.Create(AItem.CanAbstract));
  Result.AddPair('abstract', TJSONBool.Create(AItem.CanAbstract and SameText(AMethodMode, 'abstract')));
  mNeeds := TJSONArray.Create;
  for mNeed in AItem.Needs do
  begin
    mNeeds.AddElement(TJSONNumber.Create(mNeed));
  end;
  Result.AddPair('needs', mNeeds);
end;

class function TLspExtractSuperclass.Prepare(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TExtractSuperclassContext): TJSONObject;
var
  Info: TSuperclassInfo;
  Reason, Note, NewUnit: string;
  Item: TTransferCandidate;
  List, Notes, Units: TJSONArray;
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
    List.AddElement(CandidateJson(Item, AContext.MethodMode));
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

function RaiseVisibilityOf(const ASetting: string): TClassVisibility;
begin
  if SameText(ASetting, 'strictProtected') then
  begin
    Result := TClassVisibility.StrictProtected;
  end
  else
  begin
    Result := TClassVisibility.Protected_;
  end;
end;

type
  /// <summary>Ein Lauf von atlas.server.extractSuperclass: Plan, Verschieben in eine neue Unit, Antwort.</summary>
  TSuperclassExtraction = class
  private
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FPosition: TTextPosition;
    FContext: TExtractSuperclassContext;
    FRequest: TSuperclassRequest;
    FUnitName: string;
    FPlan: TSuperclassPlan;
    FChanges: TWorkspaceChanges;
    FNewFile: string;
    FNewText: string;
    procedure MakePlan;
    procedure CheckNewUnit;
    function PlanMove: TMoveClassPlan;
    procedure MoveToNewUnit;
    function Answer: TJSONObject;
  public
    constructor Create(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      const AContext: TExtractSuperclassContext);
    destructor Destroy; override;
    procedure ReadRequest(ARequest: TJSONValue);
    function Run: TJSONObject;
  end;

constructor TSuperclassExtraction.Create(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TExtractSuperclassContext);
begin
  inherited Create;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FPosition := APosition;
  FContext := AContext;
  FChanges := TWorkspaceChanges.Create;
end;

destructor TSuperclassExtraction.Destroy;
begin
  FChanges.Free;
  inherited;
end;

procedure TSuperclassExtraction.ReadRequest(ARequest: TJSONValue);
var
  mBody: TJSONObject;
begin
  if not (ARequest is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Anfrage mit name, unit und members fehlt');
  end;
  mBody := TJSONObject(ARequest);
  FRequest := Default(TSuperclassRequest);
  FRequest.Name := Field(mBody, 'name');
  FRequest.Members := Ids(mBody, 'members');
  FRequest.Abstract := Ids(mBody, 'abstract');
  FUnitName := Field(mBody, 'unit');
  FRequest.SameUnit := (FUnitName = '') or SameText(FUnitName, TUsesClauses.OwnName(FTree.Tokens));
  FRequest.RaiseVisibility := RaiseVisibilityOf(FContext.RaiseVisibility);
  if not FRequest.SameUnit and not IsIdentifier(StringReplace(FUnitName, '.', '_', [rfReplaceAll])) then
  begin
    raise Failed(Format('"%s" ist kein gültiger Unit-Name.', [FUnitName]));
  end;
end;

procedure TSuperclassExtraction.MakePlan;
var
  mReason: string;
begin
  if not TExtractSuperclass.Plan(TClassSource.Create(FTree, FText, FPosition.Line), FRequest,
    InterfaceCheck(FTree, FContext.Index), NameCheck(FTree, FContext.Index), FPlan, mReason) then
  begin
    raise Failed(mReason);
  end;
end;

procedure TSuperclassExtraction.CheckNewUnit;
var
  mItem: TProjectUnit;
begin
  if Assigned(FContext.Exists) and FContext.Exists(FNewFile) then
  begin
    raise Failed(Format('%s gibt es schon.', [ExtractFileName(FNewFile)]));
  end;
  if not FContext.HasProject then
  begin
    Exit;
  end;
  for mItem in FContext.Project.Units do
  begin
    if SameText(mItem.Name, FUnitName) then
    begin
      raise Failed(Format('%s steht schon im Projekt.', [FUnitName]));
    end;
  end;
end;

function TSuperclassExtraction.PlanMove: TMoveClassPlan;
var
  mTree: TSyntaxTree;
  mReason: string;
begin
  mTree := TSyntaxTreeCache.Parse(FPlan.Text);
  try
    FContext.Resolver.PinTree(mTree, FFileName);
    try
      if not TMoveClass.Plan(TMoveClassSource.Create(FFileName, FPlan.Text, mTree),
        TTextPosition.Create(FPlan.BaseLine, 0), FUnitName, TLspMoveClass.Lookup(FContext.Resolver), Result,
        mReason) then
      begin
        raise Failed(Format('Die Basisklasse lässt sich nicht in eine eigene Unit verschieben: %s', [mReason]));
      end;
    finally
      FContext.Resolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TSuperclassExtraction.MoveToNewUnit;
var
  mMove: TMoveClassPlan;
begin
  // Die Basisklasse steht jetzt über der Klasse; „Klasse verschieben“ bringt sie in die neue Unit.
  FNewFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(FFileName), FUnitName + '.pas');
  CheckNewUnit;
  mMove := PlanMove;
  FNewText := TTextChanges.Apply(FPlan.Text, mMove.OriginEdits);
  FChanges.CreateFile(FNewFile, mMove.Text);
  if mMove.Unresolved <> nil then
  begin
    FChanges.Warn(Format('Unbekannte Herkunft von %s: Die neue Unit übernimmt dafür die uses der alten.',
      [string.Join(', ', mMove.Unresolved)]));
  end;
end;

function TSuperclassExtraction.Answer: TJSONObject;
var
  mMoved: Integer;
  mDescription: string;
begin
  mMoved := Length(FPlan.Moved) + Length(FPlan.Abstracts);
  mDescription := Format('%s mit %d Mitgliedern, %d Dateien', [FPlan.BaseName, mMoved, FChanges.FileCount]);
  Result := TJSONObject.Create;
  Result.AddPair('edit', FChanges.ToJson(TLspExtractSuperclass.AnnotationId, 'Basisklasse herauslösen',
    mDescription));
  Result.AddPair('warnings', FChanges.WarningsJson);
  Result.AddPair('file', TDocumentUris.FromPath(FNewFile));
  // Zeile der Basisklasse in derselben Unit; in der neuen Unit vom Anfang an.
  if FRequest.SameUnit then
  begin
    Result.AddPair('line', TJSONNumber.Create(FPlan.BaseLine));
  end
  else
  begin
    Result.AddPair('line', TJSONNumber.Create(0));
  end;
  Result.AddPair('name', FPlan.BaseName);
  Result.AddPair('moved', TJSONNumber.Create(mMoved));
end;

function TSuperclassExtraction.Run: TJSONObject;
var
  mWarning: string;
begin
  MakePlan;
  for mWarning in FPlan.Warnings do
  begin
    FChanges.Warn(mWarning);
  end;
  FNewFile := FFileName;
  FNewText := FPlan.Text;
  if not FRequest.SameUnit then
  begin
    MoveToNewUnit;
  end;
  CheckParses(FFileName, FNewText, Length(FTree.Diagnostics));
  FChanges.Add(FFileName, TTextChanges.Diff(FText, FNewText));
  if not FRequest.SameUnit then
  begin
    FChanges.RegisterUnit(FContext.HasProject, FContext.Project, FContext.ReadText, FNewFile, FUnitName);
  end;
  Result := Answer;
end;

class function TLspExtractSuperclass.Execute(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; ARequest: TJSONValue; const AContext: TExtractSuperclassContext): TJSONObject;
var
  mExtraction: TSuperclassExtraction;
begin
  mExtraction := TSuperclassExtraction.Create(ATree, AFileName, AText, APosition, AContext);
  try
    mExtraction.ReadRequest(ARequest);
    Result := mExtraction.Run;
  finally
    mExtraction.Free;
  end;
end;

end.
