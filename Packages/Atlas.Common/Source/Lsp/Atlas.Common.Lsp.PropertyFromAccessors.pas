unit Atlas.Common.Lsp.PropertyFromAccessors;

// „Property aus Getter und Setter“ über das Protokoll (#682):
//   - Code-Aktionen auf der Deklaration einer Zugriffsmethode („Property X
//     anlegen“) und auf der Kopfzeile einer Klasse („Fehlende Properties
//     anlegen (n)“), nur mit refactoring.propertyFromAccessors. Nach
//     refactoring.propertyFromAccessorsReplaceCalls gibt es sie ohne, mit oder
//     (ask) in beiden Formen „… und Aufrufe umstellen“. Sie tragen den
//     Client-Befehl atlas.propertyFromAccessors mit [uri, position, Aufrufe].
//   - Befehl atlas.server.propertyFromAccessors [uri, position, Aufrufe]:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau. Die Aufrufe findet die Referenzsuche (#29) im ganzen Projekt;
//     X.GetCaption → X.Caption, X.SetCaption(V) → X.Caption := V. Methoden-
//     zeiger (@X.GetCaption, Ereigniszuweisungen, Argumente vom Typ eines
//     Methodenzeigers) bleiben; lässt sich der Zieltyp nicht bestimmen, bleibt
//     die Stelle mit einem Hinweis. Rümpfe der Zugriffsmethoden selbst bleiben.
//   - Verbergen (refactoring.propertyFromAccessorsHideAccessors): Eine
//     Zugriffsmethode wandert nur, wenn sie danach außerhalb der Methoden
//     ihrer Klasse nicht mehr benutzt wird.
// Erkennung und Änderungen in der Klasse liefert TPropertyFromAccessors.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.PropertyFromAccessors,
  Atlas.Common.Lsp.References;

type
  TPropertyFromAccessorsContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Aufrufsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Options: TPropertyFromAccessorsOptions;
    /// <summary>Aufrufe auf die Property umstellen.</summary>
    ReplaceCalls: Boolean;
  end;

  TLspPropertyFromAccessors = class
  public const
    cClientCommand = 'atlas.propertyFromAccessors';
    cApplyCommand = 'atlas.server.propertyFromAccessors';
    cKind = 'refactor.rewrite';
    cAnnotationId = 'propertyFromAccessors';
  public
    /// <summary>Code-Aktionen an APosition; nil, wenn dort keine Property fehlt. Der Aufrufer
    /// übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition; const AOptions: TPropertyFromAccessorsOptions;
      AReplaceCalls: TReplaceCalls): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "properties": n, "calls": n}; EJsonRpcError, wenn an
    /// APosition keine Property fehlt oder das Ergebnis nicht parst. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TPropertyFromAccessorsContext): TJSONObject; static;
    /// <summary>Ist ATypeName ein prozeduraler Typ (procedure/function … of object, reference to)?</summary>
    class function IsProcedural(const ATypeName: string; const AIndex: ISymbolIndex): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPropertyFromAccessorsText = (AfterTheChangeNoLonger, PropertyFromGetterAndSetter, WhetherIsMeantAsA,
    IsUsedAsAMethod, StaysVisibleItIsStill, AndUpdateCalls, NoPropertyIsMissingHere, PropertiesCallsUpdatedFiles,
    CreateMissingProperties, CreateProperty, Line);

const
  cTexts: array[TPropertyFromAccessorsText] of TAtlasText = (
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).';
     En: 'After the change %s no longer parses without errors (line %d: %s).'),
    (De: 'Property aus Getter und Setter'; En: 'Property from getter and setter'),
    (De: '%s: Ob %s dort als Methodenzeiger gemeint ist, lässt sich nicht bestimmen; die Stelle bleibt.';
     En: '%s: whether %s is meant as a method pointer there cannot be determined; the place stays.'),
    (De: '%s: %s wird als Methodenzeiger verwendet und bleibt.'; En: '%s: %s is used as a method pointer and stays.'),
    (De: '%s bleibt sichtbar: Es wird außerhalb der Klasse noch benutzt.';
     En: '%s stays visible: it is still used outside the class.'),
    (De: ' und Aufrufe umstellen'; En: ' and update calls'),
    (De: 'Hier fehlt keine Property.'; En: 'No property is missing here.'),
    (De: '%d Properties, %d Aufrufe umgestellt, %d Dateien'; En: '%d properties, %d calls updated, %d files'),
    (De: 'Fehlende Properties anlegen (%d)'; En: 'Create missing properties (%d)'),
    (De: 'Property %s anlegen'; En: 'Create property %s'),
    (De: '%s, Zeile %d'; En: '%s, line %d'));

{$SCOPEDENUMS OFF}

const
  cProceduralPattern = '=\s*(reference\s+to\s+)?(procedure|function)\b';
  /// <summary>Bekannte Methodenzeiger der RTL, falls die RTL nicht im Index steht.</summary>
  cKnownProcedural: array[0..5] of string = ('TProc', 'TFunc', 'TPredicate', 'TNotifyEvent', 'TThreadMethod',
    'TThreadProcedure');
  /// <summary>Eingebaute Routinen, deren Argumente Werte sind.</summary>
  cValueIntrinsics: array[0..13] of string = ('Exit', 'Write', 'Writeln', 'Length', 'Ord', 'Chr', 'Inc', 'Dec', 'Abs',
    'Round', 'Trunc', 'Succ', 'Pred', 'High');

type
  {$SCOPEDENUMS ON}
  TUnclearResult = (Value, Pointer_, Unknown);
  {$SCOPEDENUMS OFF}

  TSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Edits: TArray<TTextEdit>;
    destructor Destroy; override;
  end;

destructor TSourceFile.Destroy;
begin
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

function Where(const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := cTexts[TPropertyFromAccessorsText.Line].Fmt([ExtractFileName(AFileName), APosition.Line + 1]);
end;

/// <summary>Routine mit Rumpf, in der APosition liegt; nil außerhalb.</summary>
function RoutineAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= APosition.Line) and (ANode.EndPos.Line >= APosition.Line);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

/// <summary>Liegt APosition in der Klassendeklaration von AProperty?</summary>
function InClassDecl(ATree: TSyntaxTree; const AProperty: TAccessorProperty; const APosition: TTextPosition): Boolean;
var
  mFound: Boolean;
begin
  mFound := False;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = AProperty.ClassLine) and
        (APosition.Line >= ANode.StartPos.Line) and (APosition.Line <= ANode.EndPos.Line) then
      begin
        mFound := True;
      end;
      Result := not mFound;
    end);
  Result := mFound;
end;

class function TLspPropertyFromAccessors.IsProcedural(const ATypeName: string; const AIndex: ISymbolIndex): Boolean;
var
  mName: string;
  mLocation: TSymbolLocation;
begin
  if TRegEx.IsMatch(ATypeName, '^\s*(reference\s+to\s+)?(procedure|function)\b', [roIgnoreCase]) then
  begin
    Exit(True);
  end;
  mName := Trim(ATypeName);
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  if IndexText(mName, cKnownProcedural) >= 0 then
  begin
    Exit(True);
  end;
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(mName) do
    begin
      if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias) and
        TRegEx.IsMatch(mLocation.Symbol.Signature, cProceduralPattern, [roIgnoreCase]) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Wert oder Methodenzeiger nach dem Typnamen ATypeName.</summary>
function ByType(const ATypeName: string; const AIndex: ISymbolIndex): TUnclearResult;
begin
  if TLspPropertyFromAccessors.IsProcedural(ATypeName, AIndex) then
  begin
    Result := TUnclearResult.Pointer_;
  end
  else
  begin
    Result := TUnclearResult.Value;
  end;
end;

/// <summary>Zuweisung an Result bei APosition: der Ergebnistyp der Routine.</summary>
function ResultTarget(const AIndex: ISymbolIndex; ASource: TSourceFile; const APosition: TTextPosition):
  TUnclearResult;
var
  mRoutine, mHeader, mTypeRef: TSyntaxNode;
begin
  Result := TUnclearResult.Unknown;
  mRoutine := RoutineAt(ASource.Tree, APosition);
  mHeader := nil;
  if mRoutine <> nil then
  begin
    mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  end;
  mTypeRef := nil;
  if mHeader <> nil then
  begin
    mTypeRef := mHeader.FindChild(TSyntaxKind.TypeReference);
  end;
  if mTypeRef <> nil then
  begin
    Result := ByType(Copy(ASource.Text, mTypeRef.StartOffset + 1, mTypeRef.EndOffset - mTypeRef.StartOffset), AIndex);
  end;
end;

/// <summary>Zuweisung an eine Variable, ein Feld oder eine Property bei APosition: der deklarierte Typ, sonst der
/// aufgelöste Typ.</summary>
function AssignTarget(AResolver: TNameResolver; const AIndex: ISymbolIndex; ASource: TSourceFile;
  const APosition: TTextPosition): TUnclearResult;
var
  mResolved: TResolvedSymbol;
begin
  mResolved := AResolver.Resolve(ASource.Tree, ASource.FileName, APosition);
  if mResolved.Found and (mResolved.TypeName <> '') then
  begin
    Exit(ByType(mResolved.TypeName, AIndex));
  end;
  mResolved := AResolver.ResolveType(ASource.Tree, ASource.FileName, APosition);
  if not mResolved.Found then
  begin
    Exit(TUnclearResult.Unknown);
  end;
  if mResolved.Builtin or (not TRegEx.IsMatch(mResolved.Signature, cProceduralPattern, [roIgnoreCase]) and
    not TLspPropertyFromAccessors.IsProcedural(mResolved.Name, AIndex)) then
  begin
    Result := TUnclearResult.Value;
  end
  else
  begin
    Result := TUnclearResult.Pointer_;
  end;
end;

/// <summary>Argument Nummer AArgument des Aufrufs ATarget: Assigned prüft Zeiger, die eingebauten Routinen in
/// ValueIntrinsics nehmen Werte, sonst entscheiden die Parameter der Kandidaten.</summary>
function ArgumentTarget(AResolver: TNameResolver; const AIndex: ISymbolIndex; ASource: TSourceFile;
  const ATarget: TPascalToken; AArgument: Integer): TUnclearResult;
var
  mCandidate: TResolvedSymbol;
begin
  if SameText(ATarget.Text, 'Assigned') then
  begin
    Exit(TUnclearResult.Pointer_);
  end;
  if IndexText(ATarget.Text, cValueIntrinsics) >= 0 then
  begin
    Exit(TUnclearResult.Value);
  end;
  Result := TUnclearResult.Unknown;
  for mCandidate in AResolver.ResolveAll(ASource.Tree, ASource.FileName, ATarget.StartPos) do
  begin
    if AArgument <= High(mCandidate.ParamTypes) then
    begin
      if TLspPropertyFromAccessors.IsProcedural(mCandidate.ParamTypes[AArgument], AIndex) then
      begin
        Exit(TUnclearResult.Pointer_);
      end;
      Result := TUnclearResult.Value;
    end;
  end;
end;

/// <summary>Ist der Getter bei ANameToken ein Wert oder ein Methodenzeiger? Ziel der Zuweisung bzw. Parameter
/// des Aufrufs entscheiden.</summary>
function ResolveUnclear(AResolver: TNameResolver; const AIndex: ISymbolIndex; ASource: TSourceFile;
  ANameToken: Integer): TUnclearResult;
var
  mTokens: TArray<TPascalToken>;
  mTarget, mArgument: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  mTarget := TPropertyFromAccessors.UnclearTarget(mTokens, ANameToken, mArgument);
  if mTarget < 0 then
  begin
    Result := TUnclearResult.Unknown;
  end
  else if mArgument >= 0 then
  begin
    Result := ArgumentTarget(AResolver, AIndex, ASource, mTokens[mTarget], mArgument);
  end
  else if SameText(mTokens[mTarget].Text, 'Result') then
  begin
    Result := ResultTarget(AIndex, ASource, mTokens[mTarget].StartPos);
  end
  else
  begin
    Result := AssignTarget(AResolver, AIndex, ASource, mTokens[mTarget].StartPos);
  end;
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
    mItem.AddPair('annotationId', TLspPropertyFromAccessors.cAnnotationId);
    mItems.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mDocument);
  Result.AddPair('edits', mItems);
end;

/// <summary>Getter und Setter von AItem, soweit vorhanden.</summary>
function MethodsOf(const AItem: TAccessorProperty): TArray<TAccessorMethod>;
begin
  Result := nil;
  if AItem.Getter.Exists then
  begin
    Result := Result + [AItem.Getter];
  end;
  if AItem.Setter.Exists then
  begin
    Result := Result + [AItem.Setter];
  end;
end;

/// <summary>EJsonRpcError, wenn AUnit nach ihren Änderungen mehr Parserfehler hat als vorher.</summary>
procedure CheckParses(AUnit: TSourceFile);
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(TChangeSignature.ApplyEdits(AUnit.Text, AUnit.Edits));
  try
    if Length(mTree.Diagnostics) > Length(AUnit.Tree.Diagnostics) then
    begin
      raise Fail(cTexts[TPropertyFromAccessorsText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AUnit.FileName),
        mTree.Diagnostics[0].StartPos.Line + 1, mTree.Diagnostics[0].Message]));
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Änderungsanmerkung für die Vorschau.</summary>
function AnnotationsJson(APropertyCount, ACalls, AFileCount: Integer): TJSONObject;
var
  mAnnotation: TJSONObject;
begin
  mAnnotation := TJSONObject.Create;
  mAnnotation.AddPair('label', cTexts[TPropertyFromAccessorsText.PropertyFromGetterAndSetter].Text);
  mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  mAnnotation.AddPair('description', cTexts[TPropertyFromAccessorsText.PropertiesCallsUpdatedFiles].Fmt([
    APropertyCount, ACalls, AFileCount]));
  Result := TJSONObject.Create;
  Result.AddPair(TLspPropertyFromAccessors.cAnnotationId, mAnnotation);
end;

type
  /// <summary>Verwendung einer Zugriffsmethode an einer Fundstelle der Referenzsuche.</summary>
  TAccessorHit = record
    Item: TAccessorProperty;
    Method: TAccessorMethod;
    IsGetter: Boolean;
    Location: TReferenceLocation;
    Unit_: TSourceFile;
    Token: Integer;
    /// <summary>In der eigenen Klasse (Deklaration oder Methoden).</summary>
    Internal: Boolean;
    /// <summary>Im Rumpf des Getters oder Setters selbst.</summary>
    OwnBody: Boolean;
  end;

  /// <summary>Ein Lauf von Execute: gelesene Dateien, Fundstellen, Warnungen und Zähler.</summary>
  TPropertyRun = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FContext: TPropertyFromAccessorsContext;
    FSources: TObjectDictionary<string, TSourceFile>;
    FOrder: TList<string>;
    /// <summary>Zugriffsmethoden, die außerhalb der Klasse benutzt bleiben.</summary>
    FRemaining: TDictionary<string, Boolean>;
    FWarnings: TArray<string>;
    FHidden: TArray<string>;
    FCalls: Integer;
    FEditCount: Integer;
    FFileCount: Integer;
    procedure Warn(const AText: string);
    function NewSource(const AName: string): TSourceFile;
    function Source(const AName: string): TSourceFile;
    function HitAt(const AItem: TAccessorProperty; const AMethod: TAccessorMethod;
      const ALocation: TReferenceLocation; out AHit: TAccessorHit): Boolean;
    function UseOf(const AHit: TAccessorHit): TAccessorUse;
    procedure AddReference(const AItem: TAccessorProperty; const AMethod: TAccessorMethod;
      const ALocation: TReferenceLocation);
    procedure CollectReferences(const AItem: TAccessorProperty; const AMethods: TArray<TAccessorMethod>);
    procedure HideMethods(const AMethods: TArray<TAccessorMethod>);
    function Changes: TJSONArray;
  public
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TPropertyFromAccessorsContext);
    destructor Destroy; override;
    procedure Run(const AProperties: TArray<TAccessorProperty>);
    /// <summary>Antwort von Execute; der Aufrufer übernimmt das Objekt.</summary>
    function Answer(APropertyCount: Integer): TJSONObject;
  end;

constructor TPropertyRun.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TPropertyFromAccessorsContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FSources := TObjectDictionary<string, TSourceFile>.Create([doOwnsValues]);
  FOrder := TList<string>.Create;
  FRemaining := TDictionary<string, Boolean>.Create;
end;

destructor TPropertyRun.Destroy;
begin
  FRemaining.Free;
  FOrder.Free;
  FSources.Free;
  inherited;
end;

procedure TPropertyRun.Warn(const AText: string);
begin
  FWarnings := FWarnings + [AText];
end;

function TPropertyRun.NewSource(const AName: string): TSourceFile;
var
  mText: string;
begin
  Result := nil;
  if SameText(AName, FFileName) then
  begin
    Result := TSourceFile.Create;
    Result.Text := FText;
    Result.Tree := FTree;
  end
  else if Assigned(FContext.ReadText) and FContext.ReadText(AName, mText) then
  begin
    Result := TSourceFile.Create;
    Result.Text := mText;
    Result.Tree := TSyntaxTreeCache.Parse(mText);
    Result.OwnsTree := True;
  end;
end;

function TPropertyRun.Source(const AName: string): TSourceFile;
begin
  if not FSources.TryGetValue(UpperCase(AName), Result) then
  begin
    Result := NewSource(AName);
    if Result <> nil then
    begin
      Result.FileName := AName;
      FSources.Add(UpperCase(AName), Result);
      FOrder.Add(AName);
    end;
  end;
end;

function TPropertyRun.HitAt(const AItem: TAccessorProperty; const AMethod: TAccessorMethod;
  const ALocation: TReferenceLocation; out AHit: TAccessorHit): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  AHit := Default(TAccessorHit);
  AHit.Item := AItem;
  AHit.Method := AMethod;
  AHit.IsGetter := AMethod.Name = AItem.Getter.Name;
  AHit.Location := ALocation;
  AHit.Unit_ := Source(ALocation.FileName);
  Result := (AHit.Unit_ <> nil) and (AHit.Unit_.Tree <> nil);
  if Result then
  begin
    AHit.Token := TChangeSignature.NameTokenAt(AHit.Unit_.Tree.Tokens, ALocation.Range.StartPos);
    Result := (AHit.Token >= 0) and not TPropertyFromAccessors.IsHeaderName(AHit.Unit_.Tree.Tokens, AHit.Token);
  end;
  if Result then
  begin
    // In der eigenen Klasse (Deklaration oder Methoden) bleibt eine Verwendung „innen“.
    mRoutine := RoutineAt(AHit.Unit_.Tree, ALocation.Range.StartPos);
    AHit.Internal := SameText(ALocation.FileName, FFileName) and (InClassDecl(AHit.Unit_.Tree, AItem,
      ALocation.Range.StartPos) or ((mRoutine <> nil) and StartsText(AItem.ClassName + '.', mRoutine.Name)));
    AHit.OwnBody := AHit.Internal and (mRoutine <> nil) and
      (SameText(mRoutine.Name, AItem.ClassName + '.' + AItem.Getter.Name) or
      SameText(mRoutine.Name, AItem.ClassName + '.' + AItem.Setter.Name));
  end;
end;

function TPropertyRun.UseOf(const AHit: TAccessorHit): TAccessorUse;
begin
  Result := TPropertyFromAccessors.UseOf(AHit.Unit_.Tree.Tokens, AHit.Token, AHit.IsGetter);
  if Result <> TAccessorUse.Unclear then
  begin
    Exit;
  end;
  case ResolveUnclear(FResolver, FContext.Index, AHit.Unit_, AHit.Token) of
    TUnclearResult.Value:
      Result := TAccessorUse.Call;
    TUnclearResult.Pointer_:
      Result := TAccessorUse.Pointer_;
  else
    if FContext.ReplaceCalls and not AHit.OwnBody then
    begin
      Warn(cTexts[TPropertyFromAccessorsText.WhetherIsMeantAsA].Fmt([Where(AHit.Location.FileName,
        AHit.Location.Range.StartPos), AHit.Method.Name]));
    end;
    Result := TAccessorUse.Keep;
  end;
end;

procedure TPropertyRun.AddReference(const AItem: TAccessorProperty; const AMethod: TAccessorMethod;
  const ALocation: TReferenceLocation);
var
  mHit: TAccessorHit;
  mUse: TAccessorUse;
  mAdded: TArray<TTextEdit>;
begin
  // Formulardateien binden Ereignisse: Methodenzeiger, die Methode bleibt sichtbar.
  if MatchText(ExtractFileExt(ALocation.FileName), ['.dfm', '.fmx']) then
  begin
    FRemaining.AddOrSetValue(UpperCase(AMethod.Name), True);
    Exit;
  end;
  if not HitAt(AItem, AMethod, ALocation, mHit) then
  begin
    Exit;
  end;
  mUse := UseOf(mHit);
  if (mUse = TAccessorUse.Call) and FContext.ReplaceCalls and not mHit.OwnBody and
    TPropertyFromAccessors.CallEdit(mHit.Unit_.Tree.Tokens, mHit.Token, AItem, mHit.IsGetter, mAdded) then
  begin
    mHit.Unit_.Edits := mHit.Unit_.Edits + mAdded;
    Inc(FCalls);
    Exit;
  end;
  if (mUse = TAccessorUse.Pointer_) and FContext.ReplaceCalls then
  begin
    Warn(cTexts[TPropertyFromAccessorsText.IsUsedAsAMethod].Fmt([Where(ALocation.FileName, ALocation.Range.StartPos),
      AMethod.Name]));
  end;
  if not mHit.Internal then
  begin
    FRemaining.AddOrSetValue(UpperCase(AMethod.Name), True);
  end;
end;

procedure TPropertyRun.CollectReferences(const AItem: TAccessorProperty; const AMethods: TArray<TAccessorMethod>);
var
  mMethod: TAccessorMethod;
  mLocation: TReferenceLocation;
begin
  for mMethod in AMethods do
  begin
    for mLocation in TLspReferences.Find(FResolver, FContext.Index, FTree, TReferenceSearch.Create(FFileName,
      mMethod.NamePos, False, FContext.Files, FContext.ReadText)) do
    begin
      AddReference(AItem, mMethod, mLocation);
    end;
  end;
end;

procedure TPropertyRun.HideMethods(const AMethods: TArray<TAccessorMethod>);
var
  mMethod: TAccessorMethod;
begin
  for mMethod in AMethods do
  begin
    if not TPropertyFromAccessors.CanHide(mMethod, FContext.Options) then
    begin
      Continue;
    end;
    if FRemaining.ContainsKey(UpperCase(mMethod.Name)) then
    begin
      Warn(cTexts[TPropertyFromAccessorsText.StaysVisibleItIsStill].Fmt([mMethod.Name]));
    end
    else
    begin
      FHidden := FHidden + [mMethod.Name];
    end;
  end;
end;

procedure TPropertyRun.Run(const AProperties: TArray<TAccessorProperty>);
var
  mItem: TAccessorProperty;
  mMethods: TArray<TAccessorMethod>;
  mOwn: TSourceFile;
begin
  Source(FFileName);
  for mItem in AProperties do
  begin
    mMethods := MethodsOf(mItem);
    if FContext.ReplaceCalls or (FContext.Options.Hiding <> TAccessorHiding.Off) then
    begin
      CollectReferences(mItem, mMethods);
    end;
    if FContext.Options.Hiding <> TAccessorHiding.Off then
    begin
      HideMethods(mMethods);
    end;
  end;
  mOwn := Source(FFileName);
  mOwn.Edits := mOwn.Edits + TPropertyFromAccessors.Edits(FTree, FText, AProperties, FHidden, FContext.Options);
end;

function TPropertyRun.Changes: TJSONArray;
var
  mName: string;
  mUnit: TSourceFile;
begin
  Result := TJSONArray.Create;
  try
    for mName in FOrder do
    begin
      mUnit := FSources[UpperCase(mName)];
      if mUnit.Edits <> nil then
      begin
        // Das Ergebnis muss weiter fehlerfrei parsen.
        CheckParses(mUnit);
        Result.AddElement(EditsJson(TDocumentUris.FromPath(mName), mUnit.Edits));
        Inc(FEditCount, Length(mUnit.Edits));
        Inc(FFileCount);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPropertyRun.Answer(APropertyCount: Integer): TJSONObject;
var
  mEdit: TJSONObject;
  mWarnings: TJSONArray;
  mWarning: string;
begin
  mEdit := TJSONObject.Create;
  try
    mEdit.AddPair('documentChanges', Changes);
  except
    mEdit.Free;
    raise;
  end;
  mEdit.AddPair('changeAnnotations', AnnotationsJson(APropertyCount, FCalls, FFileCount));
  mWarnings := TJSONArray.Create;
  for mWarning in FWarnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', mEdit);
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('properties', TJSONNumber.Create(APropertyCount));
  Result.AddPair('calls', TJSONNumber.Create(FCalls));
  Result.AddPair('edits', TJSONNumber.Create(FEditCount));
end;

{ TLspPropertyFromAccessors }

class function TLspPropertyFromAccessors.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const AOptions: TPropertyFromAccessorsOptions;
  AReplaceCalls: TReplaceCalls): TArray<TJSONObject>;

  function Action(const ATitle: string; AWithCalls: Boolean): TJSONObject;
  var
    mArguments: TJSONArray;
    mCommand: TJSONObject;
  begin
    mArguments := TJSONArray.Create;
    mArguments.Add(AUri);
    mArguments.AddElement(TLspPositions.PositionToJson(APosition));
    mArguments.AddElement(TJSONBool.Create(AWithCalls));
    mCommand := TJSONObject.Create;
    mCommand.AddPair('title', ATitle);
    mCommand.AddPair('command', cClientCommand);
    mCommand.AddPair('arguments', mArguments);
    Result := TJSONObject.Create;
    Result.AddPair('title', ATitle);
    Result.AddPair('kind', cKind);
    Result.AddPair('command', mCommand);
  end;

var
  mFound: TArray<TAccessorProperty>;
  mWhole: Boolean;
  mTitle: string;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mFound := TPropertyFromAccessors.At(ATree, AText, APosition.Line, AOptions, mWhole);
  if mFound = nil then
  begin
    Exit;
  end;
  if mWhole then
  begin
    mTitle := cTexts[TPropertyFromAccessorsText.CreateMissingProperties].Fmt([Length(mFound)]);
  end
  else
  begin
    mTitle := cTexts[TPropertyFromAccessorsText.CreateProperty].Fmt([mFound[0].Name]);
  end;
  if AReplaceCalls <> TReplaceCalls.Always then
  begin
    Result := Result + [Action(mTitle, False)];
  end;
  if AReplaceCalls <> TReplaceCalls.Never then
  begin
    Result := Result + [Action(mTitle + cTexts[TPropertyFromAccessorsText.AndUpdateCalls].Text, True)];
  end;
end;

class function TLspPropertyFromAccessors.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition;
  const AContext: TPropertyFromAccessorsContext): TJSONObject;
var
  mProperties: TArray<TAccessorProperty>;
  mWhole: Boolean;
  mRun: TPropertyRun;
begin
  mProperties := TPropertyFromAccessors.At(ATree, AText, APosition.Line, AContext.Options, mWhole);
  if mProperties = nil then
  begin
    raise Fail(cTexts[TPropertyFromAccessorsText.NoPropertyIsMissingHere].Text);
  end;
  mRun := TPropertyRun.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    mRun.Run(mProperties);
    Result := mRun.Answer(Length(mProperties));
  finally
    mRun.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.PropertyFromAccessors', cTexts);

end.
