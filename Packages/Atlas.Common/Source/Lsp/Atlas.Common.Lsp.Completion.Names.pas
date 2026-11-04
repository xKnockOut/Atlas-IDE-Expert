unit Atlas.Common.Lsp.Completion.Names;

// Namensvorschläge an der Namensposition einer Deklaration (#452) und das Präfix dafür (Vorgabe des Projekts
// oder Zählung im Index). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.CompletionRequest;

type
  /// <summary>Präfix für Namensvorschläge (#452) der Art AKind im Projekt von AUri: Vorgabe der Projektdatei,
  /// sonst nach der Zählung im Index (TCompletionNames.NamingPrefix); '' ohne.</summary>
  TCompletionNamingFunc = reference to function(const AUri: string; AKind: TNamingKind): string;

  TCompletionNames = class
  public
    /// <summary>Präfix F, A bzw. L für AKind, wenn mindestens 60 % dieser Deklarationen in den Projekt-Units
    /// von AIndex es tragen (#452); sonst ''.</summary>
    class function NamingPrefix(const AIndex: ISymbolIndex; AKind: TNamingKind): string; static;
    /// <summary>Präfix für AKind im Dokument von ARequest: über ANamingFor, ohne Zuweisung NamingPrefix über den
    /// Index der Anfrage.</summary>
    class function PrefixFor(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
      AKind: TNamingKind): string; static;
    /// <summary>Namensvorschläge an der Namensposition einer Deklaration (#452): Namen aus dem Typ mit dem Präfix,
    /// vergebene mit Ziffer. False, wenn keine Namensposition mit bekanntem Typ vorliegt oder
    /// completion.nameSuggestions aus ist.</summary>
    class function NameItems(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
      out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.NameSuggestions,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Context;

/// <summary>Der Name, der an der Namensposition ASite schon steht; '' ohne.</summary>
function OwnNameAt(ARequest: TCompletionRequest; const ASite: TNameSite): string;
begin
  Result := '';
  if ComparePositions(ASite.NameRange.StartPos, ASite.NameRange.EndPos) <> 0 then
  begin
    Result := Copy(ARequest.LineText(ASite.NameRange.StartPos.Line), ASite.NameRange.StartPos.Character + 1,
      ASite.NameRange.EndPos.Character - ASite.NameRange.StartPos.Character);
  end;
end;

/// <summary>Sichtbare Namen an AOffset: lokal, eigene Klasse, eigene Unit.</summary>
function ScopeNames(ARequest: TCompletionRequest; AOffset: Integer): TArray<string>;
var
  mCandidate: TResolvedSymbol;
begin
  Result := nil;
  if ARequest.Resolver = nil then
  begin
    Exit;
  end;
  for mCandidate in ARequest.Resolver.Candidates.OwnScopeCandidates(ARequest.Tree, ARequest.FileName, AOffset) do
  begin
    Result := Result + [mCandidate.Name];
  end;
end;

/// <summary>Innerster Knoten von ATree, der AOffset enthält.</summary>
function InnermostNode(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mChild: TSyntaxNode;
  mIndex: Integer;
begin
  Result := ATree.Root;
  while Result <> nil do
  begin
    mChild := nil;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if (Result[mIndex].StartOffset <= AOffset) and (AOffset <= Result[mIndex].EndOffset) then
      begin
        mChild := Result[mIndex];
      end;
    end;
    if mChild = nil then
    begin
      Exit;
    end;
    Result := mChild;
  end;
end;

/// <summary>Namen der Parameter der Parameterliste, in der ANode liegt.</summary>
function ParameterNames(ANode: TSyntaxNode): TArray<string>;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  mNode := ANode;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.Parameters) do
  begin
    mNode := mNode.Parent;
  end;
  if mNode = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mNode.ChildCount - 1 do
  begin
    for mName in mNode[mIndex].Name.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>Mitglieder des Typs, in dessen Rumpf ANode liegt.</summary>
function MemberNames(ARequest: TCompletionRequest; ANode: TSyntaxNode): TArray<string>;
var
  mNode: TSyntaxNode;
  mContainer: string;
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  mNode := ANode;
  while (mNode <> nil) and not (mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
    TSyntaxKind.RecordType, TSyntaxKind.HelperType]) do
  begin
    mNode := mNode.Parent;
  end;
  if (mNode = nil) or (mNode.Parent = nil) then
  begin
    Exit;
  end;
  mContainer := mNode.Parent.Name;
  for mSymbol in ARequest.UnitIndex.Symbols do
  begin
    if (mSymbol.Container <> '') and SameText(mSymbol.Container.Substring(mSymbol.Container.LastIndexOf('.') + 1),
      mContainer) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

/// <summary>ANames ohne AName (Groß-/Kleinschreibung egal).</summary>
function WithoutName(const ANames: TArray<string>; const AName: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := ANames;
  if AName = '' then
  begin
    Exit;
  end;
  for mIndex := High(Result) downto 0 do
  begin
    if SameText(Result[mIndex], AName) then
    begin
      Delete(Result, mIndex, 1);
    end;
  end;
end;

/// <summary>Namen, die an der Namensposition ASite schon vergeben sind: sichtbare Namen (lokal, eigene Klasse,
/// eigene Unit), bei Feldern die Mitglieder der Klasse, bei Parametern die übrigen Parameter. Der Name, der an
/// der Stelle selbst steht, zählt nicht.</summary>
function TakenNames(ARequest: TCompletionRequest; const ASite: TNameSite): TArray<string>;
var
  mNode: TSyntaxNode;
begin
  Result := ScopeNames(ARequest, ASite.Offset);
  mNode := InnermostNode(ARequest.Tree, ASite.Offset);
  if ASite.Kind = TNamingKind.Parameter then
  begin
    Result := Result + ParameterNames(mNode);
  end
  else if (ASite.Kind = TNamingKind.Field) and not ASite.Global then
  begin
    Result := Result + MemberNames(ARequest, mNode);
  end;
  Result := WithoutName(Result, OwnNameAt(ARequest, ASite));
end;

class function TCompletionNames.NamingPrefix(const AIndex: ISymbolIndex; AKind: TNamingKind): string;
var
  mUnits: TArray<TUnitIndex>;
  mCount: TNamingCount;
  mIndex: Integer;
begin
  Result := '';
  if AIndex = nil then
  begin
    Exit;
  end;
  mCount := Default(TNamingCount);
  mUnits := AIndex.Units;
  for mIndex := 0 to High(mUnits) do
  begin
    if not mUnits[mIndex].Library_ then
    begin
      Inc(mCount.Total, mUnits[mIndex].Naming[AKind].Total);
      Inc(mCount.Prefixed, mUnits[mIndex].Naming[AKind].Prefixed);
    end;
  end;
  if TNameSuggestions.UsesPrefix(mCount) then
  begin
    Result := NamingPrefixes[AKind];
  end;
end;

class function TCompletionNames.PrefixFor(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
  AKind: TNamingKind): string;
begin
  if Assigned(ANamingFor) then
  begin
    Result := ANamingFor(ARequest.Uri, AKind);
  end
  else
  begin
    Result := NamingPrefix(ARequest.Index, AKind);
  end;
end;

class function TCompletionNames.NameItems(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TNameSite;
  mPrefix, mName: string;
  mItem: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  if not ARequest.Settings.NameSuggestions or (ARequest.Tree = nil) or
    not TNameSuggestions.Site(ARequest.Tree, ARequest.Position, mSite) then
  begin
    Exit;
  end;
  mPrefix := '';
  if not mSite.Global then
  begin
    mPrefix := PrefixFor(ARequest, ANamingFor, mSite.Kind);
  end;
  for mName in TNameSuggestions.Suggest(mSite.TypeText, mPrefix, TakenNames(ARequest, mSite)) do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mName;
    mItem.Kind := KindVariable;
    if mSite.Kind = TNamingKind.Field then
    begin
      mItem.Kind := KindField;
    end;
    mItem.Detail := mSite.TypeText;
    mItem.Fits := True;
    mItem.HasTextEdit := True;
    mItem.TextEdit := TRuleEdit.Create(mSite.NameRange, mName);
    AItems.Items := AItems.Items + [mItem];
  end;
  Result := Length(AItems.Items) > 0;
end;

end.
