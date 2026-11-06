unit Atlas.Common.Lsp.EnumTables;

// Aufzählung mit Namenstabelle über das Protokoll (#667), nur mit
// refactoring.enumTables:
//   - Auf einem Aufzählungstyp: „Namenstabelle anlegen (TTyp)“ (hinter dem
//     Typ) und im interface-Teil zusätzlich „…, im implementation-Teil“, je
//     als Client-Befehl atlas.enumTable [uri, position, vorgeschlagener Name,
//     afterType|implementation]; das Plugin fragt den Namen ab. Dazu
//     „Tabellen von TTyp nachziehen“ als atlas.enumTablesSync [uri, position].
//   - Auf einer Tabelle array[TTyp] of …, deren Einträge nicht zum Typ passen:
//     „Fehlenden Eintrag ergänzen (osX)“ bzw. „Überzähligen Eintrag entfernen“
//     mit den Änderungen direkt in der Aktion.
//   - Befehle atlas.server.enumTable und atlas.server.enumTablesSync: {"edit",
//     "warnings", "places", "files", "preview"}. Nachziehen ändert alle
//     Tabellen über den Typ im Projekt und ergänzt in case-Anweisungen ohne
//     else die fehlenden Zweige (wie „case vervollständigen“, #449).
// Der Typ einer Tabelle kommt aus der Namensauflösung: gleichnamige Typen
// anderer Units zählen nicht.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.EnumTables,
  Atlas.Common.Lsp.References;

type
  TEnumTablesContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für das Nachziehen.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>refactoring.enumTablesResourceStrings.</summary>
    ResourceStrings: Boolean;
  end;

  /// <summary>Datei und Stelle, an der eine Tabelle angelegt oder nachgezogen wird.</summary>
  TEnumTablesDocument = record
    Tree: TSyntaxTree;
    FileName: string;
    Text: string;
    /// <summary>Stelle des Typnamens.</summary>
    Position: TTextPosition;
    class function Create(ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition): TEnumTablesDocument; static;
  end;

  TLspEnumTables = class
  public const
    cClientCommand = 'atlas.enumTable';
    cApplyCommand = 'atlas.server.enumTable';
    cSyncClientCommand = 'atlas.enumTablesSync';
    cSyncApplyCommand = 'atlas.server.enumTablesSync';
    cCreateKind = 'refactor.rewrite';
    cRepairKind = 'quickfix';
    cAnnotationId = 'enumTables';
    cAfterTypeName = 'afterType';
    cImplementationName = 'implementation';
  public
    /// <summary>Die Code-Aktionen an APosition; AResolver hat ATree gepinnt. Der Aufrufer übernimmt die Objekte.
    /// </summary>
    class function Actions(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.enumTable; EJsonRpcError mit dem Grund, wenn es nicht geht.</summary>
    class function Execute(const ADocument: TEnumTablesDocument; const AName, APlacement: string;
      const AContext: TEnumTablesContext): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.enumTablesSync.</summary>
    class function Sync(AResolver: TNameResolver; const ADocument: TEnumTablesDocument;
      const AContext: TEnumTablesContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspEnumTablesText = (NameTableNotPossible, WithEntries, CaseBranchesAdded, TablesAndCaseStatementsIn,
    UpdateNotPossible, PlacesInFiles, UnknownPlace, Line);

const
  cTexts: array[TLspEnumTablesText] of TAtlasText = (
    (De: 'Namenstabelle geht nicht: '; En: 'Name table not possible: '),
    (De: '%s: %s mit %d Einträgen.'; En: '%s: %s with %d entries.'),
    (De: '%s: case: %d Zweige ergänzt'; En: '%s: case: %d branches added'),
    (De: '%s: %d Tabellen und %d case-Anweisungen in %d Dateien.';
     En: '%s: %d tables and %d case statements in %d files.'),
    (De: 'Nachziehen geht nicht: '; En: 'Update not possible: '),
    (De: '%d Stellen in %d Dateien'; En: '%d places in %d files'),
    (De: 'Unbekannte Stelle "%s"'; En: 'Unknown place "%s"'),
    (De: '%s, Zeile %d'; En: '%s, line %d'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Anweisung eines case-Zweigs; die Kinder davor sind Marken.</summary>
  cStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.cRequestFailed, AMessage);
end;

function CommandAction(const ATitle, AKind, ACommand: string; AArguments: TJSONArray): TJSONObject;
var
  mCommand: TJSONObject;
begin
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', ATitle);
  mCommand.AddPair('command', ACommand);
  mCommand.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', AKind);
  Result.AddPair('command', mCommand);
end;

function CreateAction(const ATitle, AUri: string; const ATarget: TEnumTarget; const APlacement: string): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(ATarget.NamePosition));
  mArguments.Add(TEnumTables.TableName(ATarget.TypeName));
  mArguments.Add(APlacement);
  Result := CommandAction(Format(ATitle, [ATarget.TypeName]), TLspEnumTables.cCreateKind,
    TLspEnumTables.cClientCommand, mArguments);
end;

type
  /// <summary>Baum einer Datei samt Namensauflösung, in der Tabellen und case-Anweisungen gesucht werden.</summary>
  TEnumSource = record
    Resolver: TNameResolver;
    Tree: TSyntaxTree;
    FileName: string;
    class function Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TEnumSource;
      static;
  end;

class function TEnumSource.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string):
  TEnumSource;
begin
  Result.Resolver := AResolver;
  Result.Tree := ATree;
  Result.FileName := AFileName;
end;

{ TEnumTablesDocument }

class function TEnumTablesDocument.Create(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition): TEnumTablesDocument;
begin
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Position := APosition;
end;

/// <summary>Elemente des Indextyps der Tabelle ATable über die Namensauflösung; AUnit: Unit des Typs.</summary>
function IndexNames(const ASource: TEnumSource; const AIndex: ISymbolIndex; const ATable: TEnumTable;
  out ANames: TArray<string>; out AUnit: string): Boolean;
var
  mResolved: TResolvedSymbol;
  mValues: TConstantValues;
begin
  ANames := nil;
  AUnit := '';
  mResolved := ASource.Resolver.ResolveType(ASource.Tree, ASource.FileName, ATable.IndexType.StartPos);
  if not mResolved.Found or (mResolved.SymbolKind <> TIndexSymbolKind.EnumType) then
  begin
    Exit(False);
  end;
  AUnit := mResolved.UnitName;
  mValues := TConstantValues.Create(ASource.Tree, ASource.FileName, AIndex, ASource.Resolver);
  try
    Result := mValues.EnumMembers(mResolved, ANames);
  finally
    mValues.Free;
  end;
end;

/// <summary>Art neuer Einträge für die Tabelle ATable: nach dem Namen, sonst über die Namensauflösung.</summary>
function ValuesOf(const ASource: TEnumSource; const ATable: TEnumTable): TEnumTableValues;
var
  mName: string;
  mElement: TEnumTableElement;
  mResolved: TResolvedSymbol;
begin
  mName := '';
  if ATable.ElementType.Kind = TSyntaxKind.TypeReference then
  begin
    mName := ATable.ElementType.Name;
  end;
  mElement := TEnumTables.ElementOf(mName);
  if (mElement = TEnumTableElement.Other) and (mName <> '') then
  begin
    mResolved := ASource.Resolver.ResolveType(ASource.Tree, ASource.FileName, ATable.ElementType.StartPos);
    if mResolved.Found then
      case mResolved.SymbolKind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          mElement := TEnumTableElement.Pointer_;
        TIndexSymbolKind.EnumType:
          mElement := TEnumTableElement.Enum;
      else
        // Übrige Arten: nichts zu tun.
      end;
  end;
  Result := TEnumTableValues.Create(mElement, mName, ATable.IndexType.Name);
end;

class function TLspEnumTables.Actions(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  mTarget: TEnumTarget;
  mTable: TEnumTable;
  mReason, mFileName, mUnitName: string;
  mNames: TArray<string>;
  mRepair: TEnumTableRepair;
  mArguments: TJSONArray;
  mAction: TJSONObject;
  mSource: TEnumSource;
begin
  Result := nil;
  mFileName := TDocumentUris.ToPath(AUri);
  if TEnumTables.Target(ATree, APosition, mTarget, mReason) then
  begin
    Result := Result + [CreateAction(TEnumTables.CreateTitle, AUri, mTarget, cAfterTypeName)];
    if mTarget.InInterface then
    begin
      Result := Result + [CreateAction(TEnumTables.CreateImplementationTitle, AUri, mTarget, cImplementationName)];
    end;
    mArguments := TJSONArray.Create;
    mArguments.Add(AUri);
    mArguments.AddElement(TLspPositions.PositionToJson(mTarget.NamePosition));
    Result := Result + [CommandAction(Format(TEnumTables.SyncTitle, [mTarget.TypeName]), cCreateKind,
      cSyncClientCommand, mArguments)];
    Exit;
  end;
  mSource := TEnumSource.Create(AResolver, ATree, mFileName);
  if not TEnumTables.TableAt(ATree, APosition, mTable) or not IndexNames(mSource, AIndex, mTable, mNames, mUnitName) or
    not TEnumTables.Repair(AText, ATree, mTable.Value, mNames, ValuesOf(mSource, mTable), mRepair) then
  begin
    Exit;
  end;
  mAction := TJSONObject.Create;
  mAction.AddPair('title', mRepair.Title);
  mAction.AddPair('kind', cRepairKind);
  mAction.AddPair('edit', TLspCodeActions.WorkspaceEditJson(AUri, mRepair.Edits));
  Result := Result + [mAction];
end;

function EditsJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  mDocument, mItem: TJSONObject;
  mItems: TJSONArray;
  mEdit: TTextEdit;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('version', TJSONNull.Create);
  mItems := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mItem.AddPair('annotationId', TLspEnumTables.cAnnotationId);
    mItems.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mDocument);
  Result.AddPair('edits', mItems);
end;

type
  TFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

function AnswerJson(const AFiles: TArray<TFileEdits>; const AWarnings: TArray<string>; APlaces: Integer;
  const ALabel, APreview: string): TJSONObject;
var
  mItem: TFileEdits;
  mChanges, mWarnings: TJSONArray;
  mEdit, mAnnotation, mAnnotations: TJSONObject;
  mWarning: string;
begin
  mChanges := TJSONArray.Create;
  for mItem in AFiles do
  begin
    mChanges.AddElement(EditsJson(TDocumentUris.FromPath(mItem.FileName), mItem.Edits));
  end;
  mAnnotation := TJSONObject.Create;
  mAnnotation.AddPair('label', ALabel);
  mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  mAnnotation.AddPair('description', cTexts[TLspEnumTablesText.PlacesInFiles].Fmt([APlaces, Length(AFiles)]));
  mAnnotations := TJSONObject.Create;
  mAnnotations.AddPair(TLspEnumTables.cAnnotationId, mAnnotation);
  mEdit := TJSONObject.Create;
  mEdit.AddPair('documentChanges', mChanges);
  mEdit.AddPair('changeAnnotations', mAnnotations);
  mWarnings := TJSONArray.Create;
  for mWarning in AWarnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', mEdit);
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('places', TJSONNumber.Create(APlaces));
  Result.AddPair('files', TJSONNumber.Create(Length(AFiles)));
  Result.AddPair('preview', APreview);
end;

/// <summary>Stelle der neuen Tabelle zum Namen APlacement; EJsonRpcError bei unbekanntem Namen.</summary>
function PlacementOf(const APlacement: string): TEnumTablePlacement;
begin
  if SameText(APlacement, TLspEnumTables.cAfterTypeName) then
  begin
    Exit(TEnumTablePlacement.AfterType);
  end;
  if not SameText(APlacement, TLspEnumTables.cImplementationName) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspEnumTablesText.UnknownPlace].Fmt([
      APlacement]));
  end;
  Result := TEnumTablePlacement.InImplementation;
end;

class function TLspEnumTables.Execute(const ADocument: TEnumTablesDocument; const AName, APlacement: string;
  const AContext: TEnumTablesContext): TJSONObject;
var
  mPlacement: TEnumTablePlacement;
  mEdits: TArray<TTextEdit>;
  mReason: string;
  mTarget: TEnumTarget;
  mFiles: TArray<TFileEdits>;
begin
  mPlacement := PlacementOf(APlacement);
  if not TEnumTables.Target(ADocument.Tree, ADocument.Position, mTarget, mReason) or
    not TEnumTables.CreateTable(ADocument.Text, ADocument.Tree, ADocument.Position,
    TEnumTableRequest.Create(Trim(AName), mPlacement, AContext.ResourceStrings), mEdits, mReason) then
  begin
    raise Fail(cTexts[TLspEnumTablesText.NameTableNotPossible].Text + mReason);
  end;
  SetLength(mFiles, 1);
  mFiles[0].FileName := ADocument.FileName;
  mFiles[0].Edits := mEdits;
  Result := AnswerJson(mFiles, nil, 1, Format(TEnumTables.CreateTitle, [mTarget.TypeName]),
    cTexts[TLspEnumTablesText.WithEntries].Fmt([mTarget.TypeName, Trim(AName), Length(mTarget.Names)]));
end;

type
  /// <summary>Eine Datei für das Nachziehen; gibt einen selbst geparsten Baum frei.</summary>
  TSyncFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    destructor Destroy; override;
  end;

destructor TSyncFile.Destroy;
begin
  if OwnsTree then
  begin
    Tree.Free;
  end;
  inherited;
end;

function Where(const AFileName, AText: string; AOffset: Integer): string;
begin
  Result := cTexts[TLspEnumTablesText.Line].Fmt([ExtractFileName(AFileName),
    TLineTable.Build(AText).PositionAt(AOffset).Line + 1]);
end;

type
  /// <summary>Prüft die Marken einer case-Anweisung gegen die Namen einer Aufzählung.</summary>
  TCaseLabels = record
    TypeName: string;
    Names: TArray<string>;
    /// <summary>"TypeName." bei qualifizierten Marken.</summary>
    Prefix: string;
    /// <summary>Die erste Marke.</summary>
    First: TSyntaxNode;
    /// <summary>Alle bisher geprüften Marken sind Werte aus Names.</summary>
    Matching: Boolean;
    procedure Check(ALabel: TSyntaxNode);
    procedure CheckRange(ARange: TSyntaxNode);
    procedure CheckItem(AItem: TSyntaxNode);
  end;

procedure TCaseLabels.Check(ALabel: TSyntaxNode);
begin
  if ALabel.Kind = TSyntaxKind.MemberAccess then
  begin
    Prefix := TypeName + '.';
  end
  else if ALabel.Kind <> TSyntaxKind.Identifier then
  begin
    Matching := False;
  end;
  if IndexText(ALabel.Name, Names) < 0 then
  begin
    Matching := False;
  end;
  if First = nil then
  begin
    First := ALabel;
  end;
end;

procedure TCaseLabels.CheckRange(ARange: TSyntaxNode);
begin
  if ARange.ChildCount <> 2 then
  begin
    Matching := False;
    Exit;
  end;
  Check(ARange[0]);
  Check(ARange[1]);
end;

procedure TCaseLabels.CheckItem(AItem: TSyntaxNode);
var
  mLabel: Integer;
begin
  for mLabel := 0 to AItem.ChildCount - 1 do
  begin
    if AItem[mLabel].Kind = TSyntaxKind.RangeExpr then
    begin
      CheckRange(AItem[mLabel]);
    end
    else if not (AItem[mLabel].Kind in cStatementKinds) then
    begin
      Check(AItem[mLabel]);
    end;
  end;
end;

/// <summary>Sind alle Marken der case-Anweisung ACase (ohne else) Werte aus ANames? APrefix: "ATypeName." bei
/// qualifizierten Marken; AFirst: die erste Marke.</summary>
function CaseMatches(ACase: TSyntaxNode; const ATypeName: string; const ANames: TArray<string>; out APrefix: string;
  out AFirst: TSyntaxNode): Boolean;
var
  mItem: Integer;
  mLabels: TCaseLabels;
begin
  mLabels := Default(TCaseLabels);
  mLabels.TypeName := ATypeName;
  mLabels.Names := ANames;
  mLabels.Matching := ACase.FindChild(TSyntaxKind.CaseElse) = nil;
  for mItem := 1 to ACase.ChildCount - 1 do
  begin
    if ACase[mItem].Kind = TSyntaxKind.CaseItem then
    begin
      mLabels.CheckItem(ACase[mItem]);
    end;
  end;
  APrefix := mLabels.Prefix;
  AFirst := mLabels.First;
  Result := mLabels.Matching and (mLabels.First <> nil);
end;

/// <summary>Alle case-Anweisungen in ATree.</summary>
function AllCases(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mCases: TArray<TSyntaxNode>;
begin
  mCases := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.CaseStatement then
      begin
        mCases := mCases + [ANode];
      end;
      Result := True;
    end);
  Result := mCases;
end;

/// <summary>case-Anweisungen in ASource über ANames ohne else, deren erste Marke zu AUnit auflöst.</summary>
function CaseStatements(const ASource: TEnumSource; const ATypeName, AUnit: string; const ANames: TArray<string>;
  out APrefixes: TArray<string>): TArray<TSyntaxNode>;
var
  mNode, mFirst: TSyntaxNode;
  mPrefix: string;
begin
  Result := nil;
  APrefixes := nil;
  for mNode in AllCases(ASource.Tree) do
  begin
    if CaseMatches(mNode, ATypeName, ANames, mPrefix, mFirst) and
      SameText(ASource.Resolver.Resolve(ASource.Tree, ASource.FileName, mFirst.StartPos).UnitName, AUnit) then
    begin
      Result := Result + [mNode];
      APrefixes := APrefixes + [mPrefix];
    end;
  end;
end;

type
  /// <summary>Ein Lauf von „Tabellen nachziehen“: sammelt die Dateien, ändert Tabellen und case-Anweisungen.
  /// </summary>
  TEnumSync = class
  private
    FResolver: TNameResolver;
    FContext: TEnumTablesContext;
    FTarget: TEnumTarget;
    FOwnUnit: string;
    FFiles: TArray<TSyncFile>;
    FEdits: TArray<TFileEdits>;
    FWarnings: TArray<string>;
    FPreview: TArray<string>;
    FPlaces: Integer;
    FTableCount: Integer;
    FCaseCount: Integer;
    procedure AddFile(const AFileName, AText: string; ATree: TSyntaxTree; AOwnsTree: Boolean);
    function MentionsTarget(const AText: string): Boolean;
    function ReadsCandidate(const AFileName, AOwnFile: string; out AText: string): Boolean;
    function BelongsToTarget(const ASource: TEnumSource; const ATable: TEnumTable): Boolean;
    procedure SyncTables(AFile: TSyncFile; var AItem: TFileEdits);
    procedure SyncCases(AFile: TSyncFile; var AItem: TFileEdits);
    procedure SyncFile(AFile: TSyncFile);
  public
    constructor Create(AResolver: TNameResolver; const AContext: TEnumTablesContext; const ATarget: TEnumTarget;
      const AOwnUnit: string);
    destructor Destroy; override;
    procedure Run(const ADocument: TEnumTablesDocument);
    function Answer: TJSONObject;
  end;

constructor TEnumSync.Create(AResolver: TNameResolver; const AContext: TEnumTablesContext;
  const ATarget: TEnumTarget; const AOwnUnit: string);
begin
  inherited Create;
  FResolver := AResolver;
  FContext := AContext;
  FTarget := ATarget;
  FOwnUnit := AOwnUnit;
end;

destructor TEnumSync.Destroy;
var
  mFile: TSyncFile;
begin
  for mFile in FFiles do
  begin
    mFile.Free;
  end;
  inherited;
end;

procedure TEnumSync.AddFile(const AFileName, AText: string; ATree: TSyntaxTree; AOwnsTree: Boolean);
var
  mFile: TSyncFile;
begin
  mFile := TSyncFile.Create;
  FFiles := FFiles + [mFile];
  mFile.FileName := AFileName;
  mFile.Text := AText;
  mFile.Tree := ATree;
  mFile.OwnsTree := AOwnsTree;
end;

function TEnumSync.MentionsTarget(const AText: string): Boolean;
begin
  Result := ContainsText(AText, FTarget.TypeName) or ContainsText(AText, FTarget.Names[0]);
end;

function TEnumSync.ReadsCandidate(const AFileName, AOwnFile: string; out AText: string): Boolean;
begin
  AText := '';
  Result := not SameText(AFileName, AOwnFile) and MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr']) and
    Assigned(FContext.ReadText) and FContext.ReadText(AFileName, AText) and MentionsTarget(AText);
end;

function TEnumSync.BelongsToTarget(const ASource: TEnumSource; const ATable: TEnumTable): Boolean;
var
  mNames: TArray<string>;
  mUnit: string;
begin
  Result := SameText(Copy(ATable.IndexType.Name, LastDelimiter('.', ATable.IndexType.Name) + 1, MaxInt),
    FTarget.TypeName) and IndexNames(ASource, FContext.Index, ATable, mNames, mUnit) and SameText(mUnit, FOwnUnit);
end;

procedure TEnumSync.SyncTables(AFile: TSyncFile; var AItem: TFileEdits);
var
  mSource: TEnumSource;
  mTable: TEnumTable;
  mRepair: TEnumTableRepair;
  mWhere: string;
begin
  mSource := TEnumSource.Create(FResolver, AFile.Tree, AFile.FileName);
  for mTable in TEnumTables.Tables(AFile.Tree) do
  begin
    // Die Elemente aus dem Baum der eigenen Unit: Er ist neuer als der Index.
    if not BelongsToTarget(mSource, mTable) or not TEnumTables.Repair(AFile.Text, AFile.Tree, mTable.Value,
      FTarget.Names, ValuesOf(mSource, mTable), mRepair) then
    begin
      Continue;
    end;
    AItem.Edits := AItem.Edits + mRepair.Edits;
    Inc(FTableCount);
    mWhere := Where(AFile.FileName, AFile.Text, mTable.Decl.StartOffset);
    FPreview := FPreview + [Format('%s: %s: %s', [mWhere, mTable.Decl.Name, mRepair.Title])];
    if mRepair.Uncertain then
    begin
      FWarnings := FWarnings + [Format('%s: %s', [mWhere, TEnumTables.UncertainNote])];
    end;
  end;
end;

procedure TEnumSync.SyncCases(AFile: TSyncFile; var AItem: TFileEdits);
var
  mCases: TArray<TSyntaxNode>;
  mPrefixes: TArray<string>;
  mCompletion: TCaseCompletionEdits;
  mIndex: Integer;
begin
  mCases := CaseStatements(TEnumSource.Create(FResolver, AFile.Tree, AFile.FileName), FTarget.TypeName, FOwnUnit,
    FTarget.Names, mPrefixes);
  for mIndex := 0 to High(mCases) do
  begin
    if TCaseCompletion.Complete(AFile.Text, AFile.Tree, mCases[mIndex], FTarget.Names, mPrefixes[mIndex],
      mCompletion) then
    begin
      AItem.Edits := AItem.Edits + mCompletion.Edits;
      Inc(FCaseCount);
      FPreview := FPreview + [cTexts[TLspEnumTablesText.CaseBranchesAdded].Fmt([Where(AFile.FileName, AFile.Text,
        mCases[mIndex].StartOffset), mCompletion.Count])];
    end;
  end;
end;

procedure TEnumSync.SyncFile(AFile: TSyncFile);
var
  mItem: TFileEdits;
begin
  mItem := Default(TFileEdits);
  mItem.FileName := AFile.FileName;
  FResolver.PinTree(AFile.Tree, AFile.FileName);
  try
    SyncTables(AFile, mItem);
    SyncCases(AFile, mItem);
  finally
    FResolver.UnpinTree;
  end;
  if mItem.Edits <> nil then
  begin
    FEdits := FEdits + [mItem];
    Inc(FPlaces, Length(mItem.Edits));
  end;
end;

procedure TEnumSync.Run(const ADocument: TEnumTablesDocument);
var
  mFileName, mText: string;
  mFile: TSyncFile;
begin
  AddFile(ADocument.FileName, ADocument.Text, ADocument.Tree, False);
  // Andere Units nur, wenn ihr Text den Typ- oder einen Elementnamen nennt.
  for mFileName in FContext.Files do
  begin
    if ReadsCandidate(mFileName, ADocument.FileName, mText) then
    begin
      AddFile(mFileName, mText, TSyntaxTreeCache.Parse(mText), True);
    end;
  end;
  for mFile in FFiles do
  begin
    SyncFile(mFile);
  end;
end;

function TEnumSync.Answer: TJSONObject;
begin
  Result := AnswerJson(FEdits, FWarnings, FPlaces, Format(TEnumTables.SyncTitle, [FTarget.TypeName]),
    cTexts[TLspEnumTablesText.TablesAndCaseStatementsIn].Fmt([FTarget.TypeName, FTableCount, FCaseCount,
    Length(FEdits)]) + sLineBreak + string.Join(sLineBreak, FPreview));
end;

class function TLspEnumTables.Sync(AResolver: TNameResolver; const ADocument: TEnumTablesDocument;
  const AContext: TEnumTablesContext): TJSONObject;
var
  mTarget: TEnumTarget;
  mReason: string;
  mSync: TEnumSync;
begin
  if not TEnumTables.Target(ADocument.Tree, ADocument.Position, mTarget, mReason) then
  begin
    raise Fail(cTexts[TLspEnumTablesText.UpdateNotPossible].Text + mReason);
  end;
  mSync := TEnumSync.Create(AResolver, AContext, mTarget, TUsesClauses.OwnName(ADocument.Tree.Tokens));
  try
    mSync.Run(ADocument);
    Result := mSync.Answer;
  finally
    mSync.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.EnumTables', cTexts);

end.
