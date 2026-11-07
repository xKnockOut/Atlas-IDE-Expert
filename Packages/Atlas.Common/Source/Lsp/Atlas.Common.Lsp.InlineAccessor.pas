unit Atlas.Common.Lsp.InlineAccessor;

// „Triviale Zugriffsmethode durch Feld ersetzen“ über das Protokoll (#717):
//   - Code-Aktionen auf einer Property, auf der Deklaration und im Rumpf einer
//     trivialen Zugriffsmethode („Zugriffsmethode GetName durch Feld FName
//     ersetzen“), nur mit refactoring.inlineAccessor. Mit
//     refactoring.inlineAccessorBulk dort und auf der Kopfzeile einer Klasse
//     zusätzlich „Alle trivialen Zugriffsmethoden der Unit ersetzen (n)“ und
//     „… des Projekts ersetzen“. Sie tragen den Client-Befehl
//     atlas.inlineAccessor mit [uri, position, here|unit|project].
//   - Befehl atlas.server.inlineAccessor mit denselben Argumenten:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau. Die Referenzsuche (#29) prüft jede Methode: Wird sie außerhalb
//     ihrer Deklaration, ihres Rumpfs und der Properties ihrer Klasse
//     benutzt, bleibt sie, und ein Hinweis nennt die Stelle. Bleibt nichts
//     übrig, scheitert der Befehl mit diesen Hinweisen.
// Erkennung und Änderungen liefert TInlineAccessor.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Lsp.References;

type
  TInlineAccessorContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche und die Sammelaktion über das Projekt.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Options: TInlineAccessorOptions;
    /// <summary>Bereich: ScopeHere, ScopeUnit oder ScopeProject.</summary>
    Scope: string;
  end;

  /// <summary>Was die Code-Aktionen anbieten dürfen.</summary>
  TInlineAccessorOffer = record
    /// <summary>refactoring.inlineAccessor</summary>
    Enabled: Boolean;
    /// <summary>refactoring.inlineAccessorBulk: auch die Sammelaktionen.</summary>
    Bulk: Boolean;
    Options: TInlineAccessorOptions;
    Index: ISymbolIndex;
  end;

  TLspInlineAccessor = class
  public const
    cClientCommand = 'atlas.inlineAccessor';
    cApplyCommand = 'atlas.server.inlineAccessor';
    cKind = 'refactor.inline';
    cAnnotationId = 'inlineAccessor';
    cScopeHere = 'here';
    cScopeUnit = 'unit';
    cScopeProject = 'project';
  public
    /// <summary>Code-Aktionen an APosition; nil, wenn abgeschaltet oder dort nichts zu ersetzen ist. Der
    /// Aufrufer übernimmt die Objekte.</summary>
    class function Actions(const AOffer: TInlineAccessorOffer; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "accessors": n, "edits": n, "files": n};
    /// EJsonRpcError, wenn nichts zu ersetzen ist oder das Ergebnis nicht parst. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TInlineAccessorContext): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.WorkspaceChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspInlineAccessorText = (ReplaceAllTrivialAccessorsOf, ReplaceAllTrivialAccessorsOf2, ThereIsNoTrivialAccessor,
    StaysItIsStillCalled, NoTrivialAccessorFound, AfterTheChangeNoLonger, ReplaceAccessorWithField, AccessorsFiles,
    UnknownScope);

const
  cTexts: array[TLspInlineAccessorText] of TAtlasText = (
    (De: 'Alle trivialen Zugriffsmethoden der Unit ersetzen (%d)';
     En: 'Replace all trivial accessors of the unit (%d)'),
    (De: 'Alle trivialen Zugriffsmethoden des Projekts ersetzen …';
     En: 'Replace all trivial accessors of the project …'),
    (De: 'Hier steht keine triviale Zugriffsmethode.'; En: 'There is no trivial accessor here.'),
    (De: '%s.%s bleibt: Es wird noch aufgerufen (%s).'; En: '%s.%s stays: it is still called (%s).'),
    (De: 'Keine triviale Zugriffsmethode gefunden.'; En: 'No trivial accessor found.'),
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).';
     En: 'After the change %s no longer parses without errors (line %d: %s).'),
    (De: 'Zugriffsmethode durch Feld ersetzen'; En: 'Replace accessor with field'),
    (De: '%d Zugriffsmethoden, %d Dateien'; En: '%d accessors, %d files'),
    (De: 'Unbekannter Bereich "%s".'; En: 'Unknown scope "%s".'));

{$SCOPEDENUMS OFF}

type
  TAccessorGroups = TList<TArray<TTrivialAccessor>>;

  /// <summary>Eine Datei mit den Klassen, deren Zugriffsmethoden ersetzt werden.</summary>
  TAccessorUnit = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Layouts: TObjectList<TClassLayout>;
    Accessors: TAccessorGroups;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TAccessorUnit.Create;
begin
  inherited Create;
  Layouts := TObjectList<TClassLayout>.Create(True);
  Accessors := TAccessorGroups.Create;
end;

destructor TAccessorUnit.Destroy;
begin
  Accessors.Free;
  // Die Layouts verweisen auf den Baum: zuerst freigeben.
  Layouts.Free;
  if OwnsTree then
  begin
    Tree.Free;
  end;
  inherited;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.cRequestFailed, AMessage);
end;

/// <summary>Klasse an ALine: Deklaration (Kopf bis end) oder Rumpf einer ihrer Methoden; nil ohne.</summary>
function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
  mName: string;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, True);
  if Result <> nil then
  begin
    Exit;
  end;
  mRoutine := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        mRoutine := ANode;
      end;
    end);
  if (mRoutine = nil) or (Pos('.', mRoutine.Name) = 0) then
  begin
    Exit;
  end;
  mName := Copy(mRoutine.Name, 1, LastDelimiter('.', mRoutine.Name) - 1);
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := TClassLayout.DeclNamed(ATree, mName);
end;

/// <summary>Alle trivialen Zugriffsmethoden der Datei.</summary>
function CountInFile(ATree: TSyntaxTree; const AText: string; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares): Integer;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
begin
  Result := 0;
  for mDecl in TClassLayout.AllDecls(ATree) do
  begin
    mLayout := TClassLayout.Read(ATree, AText, mDecl);
    try
      Inc(Result, Length(TInlineAccessor.InClass(mLayout, AOptions, AInterfaces)));
    finally
      mLayout.Free;
    end;
  end;
end;

{ TLspInlineAccessor }

/// <summary>Code-Aktion mit dem Client-Befehl für den Bereich AScope.</summary>
function Action(const ATitle, AUri: string; const APosition: TTextPosition; const AScope: string): TJSONObject;
var
  mArguments: TJSONArray;
  mCommand: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(AScope);
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', ATitle);
  mCommand.AddPair('command', TLspInlineAccessor.cClientCommand);
  mCommand.AddPair('arguments', mArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TLspInlineAccessor.cKind);
  Result.AddPair('command', mCommand);
end;

class function TLspInlineAccessor.Actions(const AOffer: TInlineAccessorOffer; ATree: TSyntaxTree; const AText,
  AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mInterfaces: TInterfaceDeclares;
  mFound: TArray<TTrivialAccessor>;
  mReason: string;
  mOnHeader: Boolean;
  mCount: Integer;
begin
  Result := nil;
  mDecl := nil;
  if AOffer.Enabled and (ATree <> nil) then
  begin
    mDecl := ClassAt(ATree, APosition.Line);
  end;
  if mDecl = nil then
  begin
    Exit;
  end;
  mInterfaces := TInlineAccessor.IndexInterfaces(AOffer.Index);
  mLayout := TClassLayout.Read(ATree, AText, mDecl);
  try
    mFound := TInlineAccessor.At(mLayout, APosition.Line, AOffer.Options, mInterfaces, mReason);
    mOnHeader := APosition.Line = mLayout.HeaderLine;
  finally
    mLayout.Free;
  end;
  if mFound <> nil then
  begin
    Result := Result + [Action(TInlineAccessor.Title(mFound), AUri, APosition, cScopeHere)];
  end;
  mCount := 0;
  if AOffer.Bulk and ((mFound <> nil) or mOnHeader) then
  begin
    mCount := CountInFile(ATree, AText, AOffer.Options, mInterfaces);
  end;
  if mCount > 0 then
  begin
    Result := Result + [Action(cTexts[TLspInlineAccessorText.ReplaceAllTrivialAccessorsOf].Fmt([mCount]), AUri,
      APosition, cScopeUnit), Action(cTexts[TLspInlineAccessorText.ReplaceAllTrivialAccessorsOf2].Text, AUri, APosition,
      cScopeProject)];
  end;
end;

type
  /// <summary>Ein Lauf von Execute: die Dateien mit ihren Zugriffsmethoden und die Änderungen.</summary>
  TAccessorRun = class
  private
    FResolver: TNameResolver;
    FContext: TInlineAccessorContext;
    FUnits: TObjectList<TAccessorUnit>;
    FInterfaces: TInterfaceDeclares;
    FChanges: TWorkspaceChanges;
    function AddUnit(const AName, AUnitText: string; AUnitTree: TSyntaxTree; AOwnsTree: Boolean): TAccessorUnit;
    procedure AddClasses(AUnit: TAccessorUnit);
    procedure AddHere(AUnit: TAccessorUnit; const APosition: TTextPosition);
    procedure AddProject(const AFileName: string);
    function ForeignUses(AUnit: TAccessorUnit; ALayout: TClassLayout; const AAccessor: TTrivialAccessor):
      TArray<string>;
    function KeepUnused(AUnit: TAccessorUnit; AIndex: Integer): Integer;
    function KeepAllUnused: Integer;
    procedure AddEdits(AUnit: TAccessorUnit);
  public
    constructor Create(AResolver: TNameResolver; const AContext: TInlineAccessorContext);
    destructor Destroy; override;
    procedure Collect(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition);
    function Answer: TJSONObject;
  end;

constructor TAccessorRun.Create(AResolver: TNameResolver; const AContext: TInlineAccessorContext);
begin
  inherited Create;
  FResolver := AResolver;
  FContext := AContext;
  FInterfaces := TInlineAccessor.IndexInterfaces(AContext.Index);
  FUnits := TObjectList<TAccessorUnit>.Create(True);
  FChanges := TWorkspaceChanges.Create;
end;

destructor TAccessorRun.Destroy;
begin
  FChanges.Free;
  FUnits.Free;
  inherited;
end;

function TAccessorRun.AddUnit(const AName, AUnitText: string; AUnitTree: TSyntaxTree;
  AOwnsTree: Boolean): TAccessorUnit;
begin
  Result := TAccessorUnit.Create;
  Result.FileName := AName;
  Result.Text := AUnitText;
  Result.Tree := AUnitTree;
  Result.OwnsTree := AOwnsTree;
  FUnits.Add(Result);
end;

procedure TAccessorRun.AddClasses(AUnit: TAccessorUnit);
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mFound: TArray<TTrivialAccessor>;
begin
  for mDecl in TClassLayout.AllDecls(AUnit.Tree) do
  begin
    mLayout := TClassLayout.Read(AUnit.Tree, AUnit.Text, mDecl);
    mFound := TInlineAccessor.InClass(mLayout, FContext.Options, FInterfaces);
    if mFound = nil then
    begin
      mLayout.Free;
      Continue;
    end;
    AUnit.Layouts.Add(mLayout);
    AUnit.Accessors.Add(mFound);
  end;
end;

procedure TAccessorRun.AddHere(AUnit: TAccessorUnit; const APosition: TTextPosition);
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mFound: TArray<TTrivialAccessor>;
  mReason: string;
begin
  mDecl := ClassAt(AUnit.Tree, APosition.Line);
  mReason := '';
  mFound := nil;
  mLayout := nil;
  if mDecl <> nil then
  begin
    mLayout := TClassLayout.Read(AUnit.Tree, AUnit.Text, mDecl);
    mFound := TInlineAccessor.At(mLayout, APosition.Line, FContext.Options, FInterfaces, mReason);
  end;
  if mFound = nil then
  begin
    mLayout.Free;
    raise Fail(IfThen(mReason = '', cTexts[TLspInlineAccessorText.ThereIsNoTrivialAccessor].Text, mReason));
  end;
  AUnit.Layouts.Add(mLayout);
  AUnit.Accessors.Add(mFound);
end;

procedure TAccessorRun.AddProject(const AFileName: string);
var
  mFileName, mText: string;
begin
  for mFileName in FContext.Files do
  begin
    if SameText(ExtractFileExt(mFileName), '.pas') and not SameText(mFileName, AFileName) and
      Assigned(FContext.ReadText) and FContext.ReadText(mFileName, mText) then
    begin
      AddClasses(AddUnit(mFileName, mText, TSyntaxTreeCache.Parse(mText), True));
    end;
  end;
end;

procedure TAccessorRun.Collect(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition);
var
  mCurrent: TAccessorUnit;
begin
  mCurrent := AddUnit(AFileName, AText, ATree, False);
  if FContext.Scope = TLspInlineAccessor.cScopeHere then
  begin
    AddHere(mCurrent, APosition);
    Exit;
  end;
  AddClasses(mCurrent);
  if FContext.Scope = TLspInlineAccessor.cScopeProject then
  begin
    AddProject(AFileName);
  end;
end;

function TAccessorRun.ForeignUses(AUnit: TAccessorUnit; ALayout: TClassLayout;
  const AAccessor: TTrivialAccessor): TArray<string>;
var
  mLocation: TReferenceLocation;
begin
  Result := nil;
  for mLocation in TLspReferences.Find(FResolver, FContext.Index, AUnit.Tree, TReferenceSearch.Create(AUnit.FileName,
    AAccessor.NamePos, False, FContext.Files, FContext.ReadText)) do
  begin
    if not SameText(mLocation.FileName, AUnit.FileName) or not TInlineAccessor.IsOwnReference(ALayout, AAccessor,
      mLocation.Range.StartPos) then
    begin
      Result := Result + [Format('%s:%d', [ExtractFileName(mLocation.FileName), mLocation.Range.StartPos.Line + 1])];
    end;
  end;
end;

function TAccessorRun.KeepUnused(AUnit: TAccessorUnit; AIndex: Integer): Integer;
var
  mKept: TArray<TTrivialAccessor>;
  mAccessor: TTrivialAccessor;
  mUses: TArray<string>;
begin
  mKept := nil;
  for mAccessor in AUnit.Accessors[AIndex] do
  begin
    mUses := ForeignUses(AUnit, AUnit.Layouts[AIndex], mAccessor);
    if mUses = nil then
    begin
      mKept := mKept + [mAccessor];
    end
    else
    begin
      FChanges.Warn(cTexts[TLspInlineAccessorText.StaysItIsStillCalled].Fmt([mAccessor.ClassName, mAccessor.Name,
        string.Join(', ', mUses)]));
    end;
  end;
  AUnit.Accessors[AIndex] := mKept;
  Result := Length(mKept);
end;

function TAccessorRun.KeepAllUnused: Integer;
var
  mUnit: TAccessorUnit;
  mIndex: Integer;
begin
  // Aufrufe außerhalb der Klasse: die Methode bleibt.
  Result := 0;
  for mUnit in FUnits do
  begin
    for mIndex := 0 to mUnit.Layouts.Count - 1 do
    begin
      Inc(Result, KeepUnused(mUnit, mIndex));
    end;
  end;
  if Result > 0 then
  begin
    Exit;
  end;
  if FChanges.Warnings = nil then
  begin
    raise Fail(cTexts[TLspInlineAccessorText.NoTrivialAccessorFound].Text);
  end;
  raise Fail(string.Join(' ', FChanges.Warnings));
end;

/// <summary>Das Ergebnis muss weiter fehlerfrei parsen.</summary>
procedure CheckParses(AUnit: TAccessorUnit; const ANewText: string);
var
  mBefore, mCheck: TSyntaxTree;
begin
  mBefore := TSyntaxTreeCache.Parse(AUnit.Text);
  mCheck := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(mCheck.Diagnostics) > Length(mBefore.Diagnostics) then
    begin
      raise Fail(cTexts[TLspInlineAccessorText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AUnit.FileName),
        mCheck.Diagnostics[0].StartPos.Line + 1, mCheck.Diagnostics[0].Message]));
    end;
  finally
    mCheck.Free;
    mBefore.Free;
  end;
end;

procedure TAccessorRun.AddEdits(AUnit: TAccessorUnit);
var
  mEdits: TArray<TTextEdit>;
  mIndex: Integer;
  mNewText: string;
begin
  mEdits := nil;
  for mIndex := 0 to AUnit.Layouts.Count - 1 do
  begin
    if AUnit.Accessors[mIndex] <> nil then
    begin
      mEdits := mEdits + TInlineAccessor.Edits(AUnit.Layouts[mIndex], AUnit.Accessors[mIndex]);
    end;
  end;
  if mEdits = nil then
  begin
    Exit;
  end;
  mNewText := TTextChanges.Apply(AUnit.Text, mEdits);
  CheckParses(AUnit, mNewText);
  FChanges.Add(AUnit.FileName, TTextChanges.Diff(AUnit.Text, mNewText));
end;

function TAccessorRun.Answer: TJSONObject;
var
  mTotal: Integer;
  mUnit: TAccessorUnit;
begin
  mTotal := KeepAllUnused;
  for mUnit in FUnits do
  begin
    AddEdits(mUnit);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', FChanges.ToJson(TLspInlineAccessor.cAnnotationId,
    cTexts[TLspInlineAccessorText.ReplaceAccessorWithField].Text,
    cTexts[TLspInlineAccessorText.AccessorsFiles].Fmt([mTotal, FChanges.FileCount])));
  Result.AddPair('warnings', FChanges.WarningsJson);
  Result.AddPair('accessors', TJSONNumber.Create(mTotal));
  Result.AddPair('edits', TJSONNumber.Create(FChanges.EditCount));
  Result.AddPair('files', TJSONNumber.Create(FChanges.FileCount));
end;

class function TLspInlineAccessor.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AContext: TInlineAccessorContext): TJSONObject;
var
  mRun: TAccessorRun;
begin
  if not MatchText(AContext.Scope, [cScopeHere, cScopeUnit, cScopeProject]) then
  begin
    raise Fail(cTexts[TLspInlineAccessorText.UnknownScope].Fmt([AContext.Scope]));
  end;
  mRun := TAccessorRun.Create(AResolver, AContext);
  try
    mRun.Collect(ATree, AFileName, AText, APosition);
    Result := mRun.Answer;
  finally
    mRun.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.InlineAccessor', cTexts);

end.
