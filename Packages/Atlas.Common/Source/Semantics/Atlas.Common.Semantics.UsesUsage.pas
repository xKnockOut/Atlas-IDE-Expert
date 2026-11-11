unit Atlas.Common.Semantics.UsesUsage;

// Welche uses-Einträge eine Unit braucht, über die Namensauflösung (#1925)
// statt über den Namensvergleich allein. Ergebnis ist eine TUsesResolution für
// TUsesActions (unused-uses, Abblenden im Editor, /cleanuses, Code-Aktionen).
//
// Ein Eintrag wird gebraucht, wenn ohne ihn ein Name nicht mehr übersetzte:
// - ein Bezeichner wird zu einer Deklaration der Unit auf Unit-Ebene
//   aufgelöst (Typ, Routine, Konstante, Variable, Enum-Wert, Attribut ohne
//   Endung wie [Test]), auch qualifiziert (Unit.Name) oder als Unit-Name;
// - ein Mitglied stammt aus einem Class- oder Record-Helper der Unit: Helper
//   wirken nur, wenn ihre Unit im uses steht;
// - der Rumpf einer gerufenen inline-Routine braucht die Unit (ohne sie
//   bettet dcc nicht ein, H2443; TInlineCallees).
// Mitglieder einer Klasse oder eines Records (Liste.Count) brauchen die Unit
// ihres Typs nicht, ebenso Namen, die lokal oder in der eigenen Unit
// deklariert sind oder eine andere Unit im uses verdeckt (die letzte gewinnt).
// Bei überladenen Routinen über mehrere Units zählen alle Units, die den Namen
// auf Unit-Ebene deklarieren: Die Auswahl der Überladung ist nicht sicher.
//
// Bezeichner, die sich nicht auflösen lassen, bleiben offen; für sie
// vergleicht TUsesActions die Namen wie vor #1925, nur genauer (vor einem
// Punkt TopNames, dahinter HelperNames). So bleibt eine Unit eher stehen, als
// dass eine benötigte entfernt wird.
//
// Aufgelöst werden nur Bezeichner, deren Name ein noch nicht gebrauchter
// Eintrag deklariert, und Kandidaten für inline-Routinen; sobald alle Einträge
// gebraucht werden, endet die Suche.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Was die Nutzung der uses-Einträge aus dem Projekt braucht.</summary>
  TUsesUsageSource = record
    Index: ISymbolIndex;
    /// <summary>Lädt eine Unit in den Index nach; nil = nur, was der Index kennt.</summary>
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Geteilter Stand der Bäume eines Prüflaufs (#1322); nil = je Resolver neu.</summary>
    TreeUnits: ITreeUnits;
    /// <summary>Antworten zum Index über alle Units (inline-Kandidaten); nil = je Unit neu.</summary>
    NameFacts: IIndexNameFacts;
    /// <summary>Unit-Namespaces des Projekts (System für SysUtils).</summary>
    Namespaces: TArray<string>;
  end;

  TUsesUsage = class
  public
    /// <summary>Auskunft über eine Unit im uses aus AIndex (Names, TopNames, HelperNames, initialization); lädt sie
    /// vorher über AEnsureUnit, wenn gesetzt. AModules: Module, auf die die Formulardatei der geprüften Unit
    /// verweist (UsedByForm).</summary>
    class function UnitInfo(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
      const AModules: TArray<string>): TUsesUnitInfoFunc; static;
    /// <summary>Nutzung der uses-Einträge von ATree (Datei AFileName); Token in AInactive zählen nicht. Nicht
    /// Active ohne Index, ohne AInfo oder ohne Baum.</summary>
    class function Resolve(const ASource: TUsesUsageSource; ATree: TSyntaxTree; const AFileName: string;
      const AInactive: TArray<TTextRange>; const AInfo: TUsesUnitInfoFunc): TUsesResolution; static;
    /// <summary>TUsesContext.Resolve für die Datei AFileName: übersetzt den Text und löst ihn auf; bei
    /// Syntaxfehlern nicht Active.</summary>
    class function ResolveFunc(const ASource: TUsesUsageSource; const AFileName: string;
      const AInfo: TUsesUnitInfoFunc): TUsesResolveFunc; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.InlineCallees;

const
  cAttributeSuffix = 'Attribute';

type
  /// <summary>Ein Eintrag der uses-Listen und die Teile, in denen er bisher gebraucht wird.</summary>
  TUsageEntry = record
    Name: string;
    InInterface: Boolean;
    Mask: Integer;
    /// <summary>Namen, mit denen ein Bezeichner ihn brauchen kann (TopNames und HelperNames).</summary>
    Names: TArray<string>;
  end;

  /// <summary>Ein Lauf von TUsesUsage.Resolve.</summary>
  TUsageRun = class
  private
    FSource: TUsesUsageSource;
    FTree: TSyntaxTree;
    FFileName: string;
    FTokens: TArray<TPascalToken>;
    FEntries: TArray<TUsageEntry>;
    // Name (klein) -> Einträge, die ihn deklarieren; Unit-Name (klein, auch mit Namespace) -> Eintrag.
    FByName: TDictionary<string, TArray<Integer>>;
    FByUnit: TDictionary<string, Integer>;
    FOpen: Integer;
    FSettled: TList<Integer>;
    FResolver: TNameResolver;
    FCallees: TInlineCallees;
    // Offset von "implementation" (-1 ohne) und ob die Datei mit "unit" beginnt: davor liegt der interface-Teil.
    FImplementation: Integer;
    FIsUnit: Boolean;
    // "unit|container" (klein) -> Ist der Container ein Helper?
    FHelpers: TDictionary<string, Boolean>;
    procedure AddEntries(const AInfo: TUsesUnitInfoFunc);
    function IsHelperMember(const AResolved: TResolvedSymbol): Boolean;
    function NeedsUnit(const AResolved: TResolvedSymbol): Boolean;
    function IsDone(const AEntry: TUsageEntry): Boolean;
    function IsOpenName(const AName: string): Boolean;
    procedure MarkUnit(const AUnitName: string; APart: Integer);
    procedure MarkDeclaring(const AName: string; APart: Integer);
    function PartAt(AOffset: Integer): Integer;
    procedure MarkNeeds(const ACallee: TInlineCallee; APart: Integer);
    procedure CheckToken(AIndex: Integer; APart: Integer);
    procedure CheckForIns(const AInactive: TArray<TTextRange>);
    procedure FindParts;
    function InlineOff: Boolean;
  public
    constructor Create(const ASource: TUsesUsageSource; ATree: TSyntaxTree; const AFileName: string);
    destructor Destroy; override;
    function Run(const AInactive: TArray<TTextRange>; const AInfo: TUsesUnitInfoFunc): TUsesResolution;
  end;

function Bare(const AIdentifier: string): string;
begin
  if (AIdentifier <> '') and (AIdentifier[1] = '&') then
  begin
    Result := Copy(AIdentifier, 2, MaxInt);
  end
  else
  begin
    Result := AIdentifier;
  end;
end;

function IsBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ TUsageRun }

constructor TUsageRun.Create(const ASource: TUsesUsageSource; ATree: TSyntaxTree; const AFileName: string);
begin
  inherited Create;
  FSource := ASource;
  FTree := ATree;
  FFileName := AFileName;
  FByName := TDictionary<string, TArray<Integer>>.Create;
  FByUnit := TDictionary<string, Integer>.Create;
  FSettled := TList<Integer>.Create;
  FHelpers := TDictionary<string, Boolean>.Create;
  FResolver := TNameResolver.Create(ASource.Index, ASource.EnsureUnit, ASource.TreeUnits);
  FResolver.Namespaces := ASource.Namespaces;
end;

destructor TUsageRun.Destroy;
begin
  FCallees.Free;
  FResolver.Free;
  FHelpers.Free;
  FSettled.Free;
  FByUnit.Free;
  FByName.Free;
  inherited;
end;

procedure TUsageRun.AddEntries(const AInfo: TUsesUnitInfoFunc);
var
  mReference: TUsesReference;
  mEntry: TUsageEntry;
  mInfo: TUsesUnitInfo;
  mName, mKey, mNamespace: string;
  mPosition: Integer;
  mList: TArray<Integer>;
begin
  for mReference in TUsesClauses.References(FTokens) do
  begin
    if (mReference.List <> TUsesListKind.UsesList) or FByUnit.ContainsKey(LowerCase(mReference.Name)) then
    begin
      Continue;
    end;
    mInfo := AInfo(mReference.Name);
    if not mInfo.Known then
    begin
      Continue;
    end;
    mEntry := Default(TUsageEntry);
    mEntry.Name := mReference.Name;
    mEntry.InInterface := mReference.InInterface;
    mEntry.Names := mInfo.TopNames + mInfo.HelperNames;
    mPosition := Length(FEntries);
    FEntries := FEntries + [mEntry];
    Inc(FOpen);
    FByUnit.AddOrSetValue(LowerCase(mReference.Name), mPosition);
    for mNamespace in FSource.Namespaces do
    begin
      mKey := LowerCase(mNamespace + '.' + mReference.Name);
      if not FByUnit.ContainsKey(mKey) then
      begin
        FByUnit.Add(mKey, mPosition);
      end;
    end;
    for mName in mEntry.Names do
    begin
      mKey := LowerCase(mName);
      if not FByName.TryGetValue(mKey, mList) then
      begin
        mList := nil;
      end;
      if (Length(mList) = 0) or (mList[High(mList)] <> mPosition) then
      begin
        FByName.AddOrSetValue(mKey, mList + [mPosition]);
      end;
    end;
  end;
end;

function TUsageRun.IsHelperMember(const AResolved: TResolvedSymbol): Boolean;
var
  mKey: string;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  if AResolved.IsHelper then
  begin
    Exit(True);
  end;
  mKey := LowerCase(AResolved.UnitName + '|' + AResolved.Container);
  if FHelpers.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := False;
  if FSource.Index.FindUnit(AResolved.UnitName, mUnit) then
  begin
    for mSymbol in mUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.HelperType) and SameText(mSymbol.QualifiedName, AResolved.Container) then
      begin
        Result := True;
        Break;
      end;
    end;
  end;
  FHelpers.Add(mKey, Result);
end;

/// <summary>Braucht der Bezeichner, der zu AResolved aufgelöst ist, die Unit der Deklaration im uses? Ja für
/// Unit-Namen, Deklarationen auf Unit-Ebene, Enum-Werte und Mitglieder von Helpern; nicht für Mitglieder von
/// Klassen und Records, lokale und eingebaute Namen.</summary>
function TUsageRun.NeedsUnit(const AResolved: TResolvedSymbol): Boolean;
begin
  case AResolved.Kind of
    TResolvedKind.UnitName:
      Result := True;
    TResolvedKind.Symbol:
      Result := not AResolved.Builtin and ((AResolved.Container = '') or
        (AResolved.SymbolKind = TIndexSymbolKind.EnumMember) or IsHelperMember(AResolved));
  else
    Result := False;
  end;
end;

function TUsageRun.IsDone(const AEntry: TUsageEntry): Boolean;
begin
  // Im interface-uses zählt auch, ob der interface-Teil die Unit braucht (sonst gehört sie ins implementation-uses).
  if AEntry.InInterface then
  begin
    Result := AEntry.Mask and TUsesResolution.cInterfacePart <> 0;
  end
  else
  begin
    Result := AEntry.Mask <> 0;
  end;
end;

function TUsageRun.IsOpenName(const AName: string): Boolean;
var
  mList: TArray<Integer>;
  mPosition: Integer;
begin
  if FByName.TryGetValue(AName, mList) then
  begin
    for mPosition in mList do
    begin
      if not IsDone(FEntries[mPosition]) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

procedure TUsageRun.MarkUnit(const AUnitName: string; APart: Integer);
var
  mPosition: Integer;
  mWasDone: Boolean;
begin
  if not FByUnit.TryGetValue(LowerCase(AUnitName), mPosition) then
  begin
    Exit;
  end;
  mWasDone := IsDone(FEntries[mPosition]);
  FEntries[mPosition].Mask := FEntries[mPosition].Mask or APart;
  if not mWasDone and IsDone(FEntries[mPosition]) then
  begin
    Dec(FOpen);
  end;
end;

procedure TUsageRun.MarkDeclaring(const AName: string; APart: Integer);
var
  mList: TArray<Integer>;
  mPosition: Integer;
begin
  if FByName.TryGetValue(LowerCase(AName), mList) then
  begin
    for mPosition in mList do
    begin
      MarkUnit(FEntries[mPosition].Name, APart);
    end;
  end;
end;

procedure TUsageRun.FindParts;
var
  mIndex: Integer;
  mFirst: Boolean;
begin
  FImplementation := -1;
  FIsUnit := False;
  mFirst := True;
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if mFirst then
    begin
      FIsUnit := FTokens[mIndex].IsKeyword('unit');
      mFirst := False;
    end;
    if FTokens[mIndex].IsKeyword('implementation') then
    begin
      FImplementation := FTokens[mIndex].Offset;
      Exit;
    end;
  end;
end;

function TUsageRun.PartAt(AOffset: Integer): Integer;
begin
  if FIsUnit and ((FImplementation < 0) or (AOffset < FImplementation)) then
  begin
    Result := TUsesResolution.cInterfacePart;
  end
  else
  begin
    Result := TUsesResolution.cImplementationPart;
  end;
end;

function TUsageRun.InlineOff: Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in FTokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and ContainsText(mToken.Text, 'INLINE OFF') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TUsageRun.MarkNeeds(const ACallee: TInlineCallee; APart: Integer);
var
  mUnitName: string;
begin
  if ACallee.Symbol.InlineRefs = nil then
  begin
    Exit;
  end;
  for mUnitName in FCallees.NeedsOf(ACallee).Units do
  begin
    MarkUnit(mUnitName, APart);
  end;
end;

procedure TUsageRun.CheckToken(AIndex: Integer; APart: Integer);
var
  mToken: TPascalToken;
  mName: string;
  mRelevant, mInline: Boolean;
  mResolved: TResolvedSymbol;
  mCallee: TInlineCallee;
begin
  mToken := FTokens[AIndex];
  mName := Bare(mToken.Text);
  mRelevant := IsOpenName(LowerCase(mName));
  mInline := (FCallees <> nil) and FCallees.IsCandidate(mName);
  if not (mRelevant or mInline) then
  begin
    Exit;
  end;
  mResolved := FResolver.Resolve(FTree, FFileName, mToken.StartPos);
  if not mResolved.Found then
  begin
    Exit;
  end;
  FSettled.Add(mToken.Offset);
  if NeedsUnit(mResolved) then
  begin
    // Überladene Routinen mehrerer Units: Welche gewinnt, entscheiden die Argumente, also alle behalten.
    if (mResolved.Kind = TResolvedKind.Symbol) and (MatchText('overload', mResolved.Directives)) and
      not TUsesActions.DotPrecedes(FTokens, AIndex) then
    begin
      MarkDeclaring(mName, APart);
    end;
    MarkUnit(mResolved.UnitName, APart);
  end;
  if mInline and FCallees.CalleeAt(mResolved, FTokens, AIndex, mCallee) then
  begin
    MarkNeeds(mCallee, APart);
  end;
end;

procedure TUsageRun.CheckForIns(const AInactive: TArray<TTextRange>);
var
  mForIns: TList<TSyntaxNode>;
  mNode, mExpr: TSyntaxNode;
  mCallee: TInlineCallee;
  mInactive: TArray<TTextRange>;
begin
  mInactive := AInactive;
  mForIns := TList<TSyntaxNode>.Create;
  try
    FTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mRange: TTextRange;
      begin
        Result := True;
        if ANode.Kind <> TSyntaxKind.ForInStatement then
        begin
          Exit;
        end;
        for mRange in mInactive do
        begin
          if not IsBefore(ANode.StartPos, mRange.StartPos) and IsBefore(ANode.StartPos, mRange.EndPos) then
          begin
            Exit;
          end;
        end;
        mForIns.Add(ANode);
      end);
    for mNode in mForIns do
    begin
      if FOpen = 0 then
      begin
        Exit;
      end;
      for mCallee in FCallees.ForInCallees(FTree, FFileName, mNode, mExpr) do
      begin
        MarkNeeds(mCallee, PartAt(mNode.StartOffset));
      end;
    end;
  finally
    mForIns.Free;
  end;
end;

function TUsageRun.Run(const AInactive: TArray<TTextRange>; const AInfo: TUsesUnitInfoFunc): TUsesResolution;
var
  mClauses: TArray<TUsesClauseInfo>;
  mIndex, mClauseIndex: Integer;
  mEntry: TUsageEntry;
begin
  Result := Default(TUsesResolution);
  FTokens := TUsesActions.ActiveTokens(FTree.Tokens, AInactive);
  FindParts;
  AddEntries(AInfo);
  FResolver.PinTree(FTree, FFileName);
  try
    if not InlineOff then
    begin
      FCallees := TInlineCallees.Create(FSource.Index, FSource.EnsureUnit, FSource.TreeUnits, FSource.Namespaces,
        FSource.NameFacts, FResolver);
      FCallees.Prepare(FResolver.ExtractedUnit(FTree, FFileName), TUsesClauses.OwnName(FTree.Tokens));
    end;
    mClauses := TUsesClauses.Clauses(FTokens);
    mClauseIndex := 0;
    mIndex := 0;
    while (mIndex <= High(FTokens)) and (FOpen > 0) do
    begin
      if (mClauseIndex <= High(mClauses)) and (mIndex = mClauses[mClauseIndex].UsesIndex) then
      begin
        mIndex := mClauses[mClauseIndex].Semicolon + 1;
        Inc(mClauseIndex);
        Continue;
      end;
      if FTokens[mIndex].Kind = TPascalTokenKind.Identifier then
      begin
        CheckToken(mIndex, PartAt(FTokens[mIndex].Offset));
      end;
      Inc(mIndex);
    end;
    if (FOpen > 0) and (FCallees <> nil) then
    begin
      CheckForIns(AInactive);
    end;
  finally
    FResolver.UnpinTree;
  end;
  Result.Active := True;
  Result.Settled := FSettled.ToArray;
  for mEntry in FEntries do
  begin
    Result.Units := Result.Units + [mEntry.Name];
    Result.Masks := Result.Masks + [mEntry.Mask];
  end;
end;

{ TUsesUsage }

class function TUsesUsage.UnitInfo(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const AModules: TArray<string>): TUsesUnitInfoFunc;
begin
  Result :=
    function(const AUnitName: string): TUsesUnitInfo
    var
      mUnit: TUnitIndex;
      mSymbol: TIndexSymbol;
      mHelpers: TArray<string>;
    begin
      Result := Default(TUsesUnitInfo);
      if Assigned(AEnsureUnit) then
      begin
        AEnsureUnit(AUnitName);
      end;
      if not AIndex.FindUnit(AUnitName, mUnit) then
      begin
        Exit;
      end;
      Result.Known := True;
      Result.HasInitialization := mUnit.HasInitialization;
      mHelpers := nil;
      for mSymbol in mUnit.Symbols do
      begin
        if mSymbol.InInterface and (mSymbol.Kind = TIndexSymbolKind.HelperType) then
        begin
          mHelpers := mHelpers + [mSymbol.QualifiedName];
        end;
      end;
      for mSymbol in mUnit.Symbols do
      begin
        if not mSymbol.InInterface then
        begin
          Continue;
        end;
        Result.Names := Result.Names + [mSymbol.Name];
        if (mSymbol.Container = '') or (mSymbol.Kind = TIndexSymbolKind.EnumMember) then
        begin
          Result.TopNames := Result.TopNames + [mSymbol.Name];
          // Attribute stehen ohne Endung da: [Test] meint TestAttribute.
          if (mSymbol.Kind = TIndexSymbolKind.ClassType) and EndsText(cAttributeSuffix, mSymbol.Name) and
            (Length(mSymbol.Name) > Length(cAttributeSuffix)) then
          begin
            Result.TopNames := Result.TopNames + [Copy(mSymbol.Name, 1, Length(mSymbol.Name) -
              Length(cAttributeSuffix))];
          end;
        end
        else if MatchText(mSymbol.Container, mHelpers) then
        begin
          Result.HelperNames := Result.HelperNames + [mSymbol.Name];
        end;
        Result.UsedByForm := Result.UsedByForm or (MatchText(mSymbol.Name, AModules) and
          (mSymbol.Kind = TIndexSymbolKind.Variable));
      end;
    end;
end;

class function TUsesUsage.Resolve(const ASource: TUsesUsageSource; ATree: TSyntaxTree; const AFileName: string;
  const AInactive: TArray<TTextRange>; const AInfo: TUsesUnitInfoFunc): TUsesResolution;
var
  mRun: TUsageRun;
begin
  if (ATree = nil) or (ASource.Index = nil) or not Assigned(AInfo) then
  begin
    Exit(Default(TUsesResolution));
  end;
  mRun := TUsageRun.Create(ASource, ATree, AFileName);
  try
    Result := mRun.Run(AInactive, AInfo);
  finally
    mRun.Free;
  end;
end;

class function TUsesUsage.ResolveFunc(const ASource: TUsesUsageSource; const AFileName: string;
  const AInfo: TUsesUnitInfoFunc): TUsesResolveFunc;
var
  mSource: TUsesUsageSource;
  mFileName: string;
  mInfo: TUsesUnitInfoFunc;
begin
  mSource := ASource;
  mFileName := AFileName;
  mInfo := AInfo;
  Result :=
    function(const AText: string; const AInactive: TArray<TTextRange>): TUsesResolution
    var
      mTree: TSyntaxTree;
    begin
      Result := Default(TUsesResolution);
      mTree := TSyntaxTreeCache.Parse(AText);
      try
        // Bei Syntaxfehlern fehlen Bezeichner: dann nur der Namensvergleich.
        if Length(mTree.Diagnostics) = 0 then
        begin
          Result := TUsesUsage.Resolve(mSource, mTree, mFileName, AInactive, mInfo);
        end;
      finally
        mTree.Free;
      end;
    end;
end;

end.
