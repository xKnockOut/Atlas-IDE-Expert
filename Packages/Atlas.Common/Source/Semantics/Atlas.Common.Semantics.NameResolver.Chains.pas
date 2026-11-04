unit Atlas.Common.Semantics.NameResolver.Chains;

// Ketten der Namensauflösung: Foo.Bar.Baz an einer Stelle im Quelltext, vom ersten Namen (oder einem Ausdruck
// davor, oder inherited) über die Mitglieder bis zum letzten; dazu der Name unter dem Cursor samt Unit-Namen mit
// Punkten, Attributen und Methodenzuordnungen, und die Typen von Ketten und Ausdrücken.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup,
  Atlas.Common.Semantics.NameResolver.Typing,
  Atlas.Common.Semantics.NameResolver.Members,
  Atlas.Common.Semantics.NameResolver.Locals,
  Atlas.Common.Semantics.NameResolver.Expressions;

type
  /// <summary>Womit eine Kette beginnt: inherited, ein Ausdruck vor dem ersten Punkt (Empfänger) und der Aufruf, dessen
  /// Argumente die Überladung des letzten Namens bestimmen.</summary>
  TResolverChainStart = record
    IsInherited: Boolean;
    Receiver: TSyntaxNode;
    Call: TSyntaxNode;
    /// <summary>Kette ab dem ersten Namen, ohne Aufruf.</summary>
    class function Plain: TResolverChainStart; static;
    /// <summary>Kette mit den Angaben aus ResolveAt.</summary>
    class function Make(AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TResolverChainStart; static;
  end;

  TResolverChains = class
  private type
    // Name unter dem Cursor: Tokens, Platz des Namens, erster Name der Kette davor, die Namen bis zum Cursor.
    TChainAt = record
      Tree: TSyntaxTree;
      FileName: string;
      Position: TTextPosition;
      Tokens: TArray<TPascalToken>;
      Index: Integer;
      First: Integer;
      Names: TArray<string>;
      Receiver: TSyntaxNode;
    end;
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    FTyping: TResolverTyping;
    FMembers: TResolverMembers;
    FLocals: TResolverLocals;
    FExpressions: TResolverExpressions;
    function ReceiverStart(AReceiver: TSyntaxNode; out AConsumed: Integer;
      out ACandidates: TArray<TResolvedSymbol>): Boolean;
    function InheritedStart(const AName: string; out AConsumed: Integer;
      out ACandidates: TArray<TResolvedSymbol>): Boolean;
    function StartCandidates(const ANames: TArray<string>; const AStart: TResolverChainStart; out AConsumed: Integer;
      out ACandidates: TArray<TResolvedSymbol>): Boolean;
    function NextCandidates(const ACurrent: TResolvedSymbol; const AName: string;
      out ACandidates: TArray<TResolvedSymbol>): Boolean;
    function FollowChain(const ANames: TArray<string>; AConsumed: Integer;
      var ACandidates: TArray<TResolvedSymbol>): Boolean;
    function UnitAtCursor(const AAt: TChainAt; out ASymbol: TResolvedSymbol): Boolean;
    function ResolutionTarget(const AAt: TChainAt; out AResult: TArray<TResolvedSymbol>): Boolean;
    function AttributeAt(const AAt: TChainAt): Boolean;
    function AttributeTarget(const AAt: TChainAt): TArray<TResolvedSymbol>;
    function ResolveTail(const AAt: TChainAt): TArray<TResolvedSymbol>;
    function ElementDecides(AWith: TSyntaxNode; AIndex: Integer; const AName: string; out AHidden: Boolean): Boolean;
    function WithDecides(const AName: string; out AHidden: Boolean): Boolean;
  public
    constructor Create(const AParts: TResolverParts; AExpressions: TResolverExpressions);
    /// <summary>Kette ANames an AOffset: alle passenden Symbole des letzten Namens, ohne eingebaute Typen.</summary>
    function ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>; AOffset: Integer;
      const AStart: TResolverChainStart): TArray<TResolvedSymbol>;
    /// <summary>Alle Symbole für den Bezeichner an APosition.</summary>
    function ResolveAt(ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TResolvedSymbol>;
    /// <summary>Äußerster Ausdruck im Baum der Stelle, der genau an AEndOffset endet.</summary>
    function FindReceiver(AEndOffset: Integer): TSyntaxNode;
    /// <summary>Aufruf, dessen aufgerufener Ausdruck an ACalleeEnd endet.</summary>
    function FindCall(ACalleeEnd: Integer): TSyntaxNode;
    /// <summary>AType stammt von TCustomAttribute ab (oder sein Vorfahr ist unbekannt).</summary>
    function IsAttributeClass(const AType: TResolvedSymbol): Boolean;
    /// <summary>Erstes Symbol der Kette ANames an AOffset; inherited: im Vorfahren der Methodenklasse.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
    /// <summary>Name am Ende der Kette ANames an AOffset und sein Typ.</summary>
    function ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; out AResult: TResolvedChainType): Boolean;
    /// <summary>Symbol und Typ des Ausdrucks ANode.</summary>
    function NodeType(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
    /// <summary>Mögliche Symbole des aufgerufenen Ausdrucks ACallee (alle Überladungen).</summary>
    function CallCandidates(ATree: TSyntaxTree; const AFileName: string;
      ACallee: TSyntaxNode): TArray<TResolvedSymbol>;
    /// <summary>Könnte ein Mitglied eines unbekannten Typs (with, Vorfahr) den Namen ACallee verdecken?</summary>
    function MayBeHiddenMember(ATree: TSyntaxTree; const AFileName: string; ACallee: TSyntaxNode;
      const ACandidate: TResolvedSymbol): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Attributes;

/// <summary>&amp;Begin → Begin.</summary>
function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

/// <summary>Namen der Kette, die an ATokens[AIndex] endet; AFirst: Platz des ersten Namens.</summary>
function NamesBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AFirst: Integer): TArray<string>;
begin
  Result := TArray<string>.Create(CleanName(ATokens[AIndex].Text));
  AFirst := AIndex;
  while (AFirst >= 2) and ATokens[AFirst - 1].IsSymbol('.') and
    (ATokens[AFirst - 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Dec(AFirst, 2);
    Result := TArray<string>.Create(CleanName(ATokens[AFirst].Text)) + Result;
  end;
end;

/// <summary>Typ, dessen Methodenzuordnung (procedure IFoo.Bar = MyBar) an AOffset ihr Ziel nennt (#849);
/// '' an anderen Stellen.</summary>
function ResolutionOwner(ANode: TSyntaxNode; AOffset: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset <= AOffset) and (AOffset < ANode[mIndex].EndOffset) then
    begin
      if (ANode[mIndex].Kind = TSyntaxKind.Identifier) and (ANode.Kind = TSyntaxKind.Directive) and
        (ANode.Name = 'resolution') then
      begin
        Exit(ANode.EnclosingTypeName);
      end;
      Exit(ResolutionOwner(ANode[mIndex], AOffset));
    end;
  end;
end;

/// <summary>AList ohne eingebaute Typen: Sie haben keine Deklaration, zu der man springen könnte.</summary>
function WithoutBuiltins(const AList: TArray<TResolvedSymbol>): TArray<TResolvedSymbol>;
var
  mSymbol: TResolvedSymbol;
begin
  Result := nil;
  for mSymbol in AList do
  begin
    if not mSymbol.Builtin then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

/// <summary>Erstes Element von AList, sonst ein leeres Ergebnis.</summary>
function FirstOf(const AList: TArray<TResolvedSymbol>): TResolvedSymbol;
begin
  if Length(AList) > 0 then
  begin
    Result := AList[0];
  end
  else
  begin
    Result := TResolvedSymbol.Empty;
  end;
end;

/// <summary>Äußerster Knoten unter ARoot um AOffset, für den AMatch gilt. Iterativ mit eigenem Stapel (Bericht M1).
/// </summary>
function FindAround(ARoot: TSyntaxNode; AOffset: Integer; const AMatch: TFunc<TSyntaxNode, Boolean>): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if AMatch(mNode) then
      begin
        Exit(mNode);
      end;
      TResolverNodes.PushChildrenAround(mPending, mNode, AOffset);
    end;
  finally
    mPending.Free;
  end;
  Result := nil;
end;

class function TResolverChainStart.Plain: TResolverChainStart;
begin
  Result := Make(False, nil, nil);
end;

class function TResolverChainStart.Make(AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TResolverChainStart;
begin
  Result.IsInherited := AInherited;
  Result.Receiver := AReceiver;
  Result.Call := ACall;
end;

constructor TResolverChains.Create(const AParts: TResolverParts; AExpressions: TResolverExpressions);
begin
  inherited Create;
  FPlace := AParts.Place;
  FUnits := AParts.Units;
  FLookup := AParts.Lookup;
  FTyping := AParts.Typing;
  FMembers := AParts.Members;
  FLocals := AParts.Locals;
  FExpressions := AExpressions;
end;

function TResolverChains.ReceiverStart(AReceiver: TSyntaxNode; out AConsumed: Integer;
  out ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mCurrent: TResolvedSymbol;
begin
  // Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar: alle Namen sind Mitglieder.
  AConsumed := 0;
  ACandidates := nil;
  Result := FExpressions.ExprSymbol(AReceiver, mCurrent);
  if Result then
  begin
    ACandidates := [mCurrent];
  end;
end;

function TResolverChains.InheritedStart(const AName: string; out AConsumed: Integer;
  out ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mClass, mAncestor: TResolvedSymbol;
begin
  // inherited Create: im Vorfahren der Klasse der umgebenden Methode suchen.
  AConsumed := 1;
  ACandidates := nil;
  if FTyping.MethodClass(mClass) and FTyping.AncestorOf(mClass, mAncestor) then
  begin
    ACandidates := FMembers.FindMembers(mAncestor, AName);
  end;
  Result := Length(ACandidates) > 0;
end;

function TResolverChains.StartCandidates(const ANames: TArray<string>; const AStart: TResolverChainStart;
  out AConsumed: Integer; out ACandidates: TArray<TResolvedSymbol>): Boolean;
begin
  if AStart.Receiver <> nil then
  begin
    Result := ReceiverStart(AStart.Receiver, AConsumed, ACandidates);
  end
  else if AStart.IsInherited then
  begin
    Result := InheritedStart(ANames[0], AConsumed, ACandidates);
  end
  else
  begin
    Result := FExpressions.ResolveFirstAll(ANames, AConsumed, ACandidates) and (Length(ACandidates) > 0);
  end;
end;

function TResolverChains.NextCandidates(const ACurrent: TResolvedSymbol; const AName: string;
  out ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mOwner: TUnitIndex;
  mSingle, mType: TResolvedSymbol;
begin
  ACandidates := nil;
  if ACurrent.Kind = TResolvedKind.UnitName then
  begin
    Result := FUnits.FindUnit(ACurrent.UnitName, mOwner) and
      FLookup.LookupInUnit(mOwner, AName, not FPlace.IsCurrentFile(mOwner.FileName), False, mSingle);
    if Result then
    begin
      ACandidates := FLocals.UnitRoutines(mSingle);
    end;
    Exit;
  end;
  if FTyping.TypeOf(ACurrent, mType) then
  begin
    ACandidates := FMembers.FindMembers(mType, AName);
  end;
  Result := Length(ACandidates) > 0;
end;

function TResolverChains.FollowChain(const ANames: TArray<string>; AConsumed: Integer;
  var ACandidates: TArray<TResolvedSymbol>): Boolean;
var
  mIndex: Integer;
  mCurrent: TResolvedSymbol;
begin
  for mIndex := AConsumed to High(ANames) do
  begin
    // Kopie: NextCandidates leert ACandidates (out), bevor es den vorigen Namen liest.
    mCurrent := ACandidates[0];
    if not NextCandidates(mCurrent, ANames[mIndex], ACandidates) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TResolverChains.ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; const AStart: TResolverChainStart): TArray<TResolvedSymbol>;
var
  mConsumed: Integer;
  mCandidates: TArray<TResolvedSymbol>;
begin
  Result := nil;
  if (ATree = nil) or (Length(ANames) = 0) then
  begin
    Exit;
  end;
  FPlace.MoveTo(ATree, AFileName, AOffset);
  if not StartCandidates(ANames, AStart, mConsumed, mCandidates) or
    not FollowChain(ANames, mConsumed, mCandidates) then
  begin
    Exit;
  end;
  if AStart.Call <> nil then
  begin
    mCandidates := FExpressions.SelectOverloads(mCandidates, AStart.Call.ChildCount - 1,
      FExpressions.ArgTypes(AStart.Call, 1));
  end;
  Result := WithoutBuiltins(mCandidates);
end;

function TResolverChains.UnitAtCursor(const AAt: TChainAt; out ASymbol: TResolvedSymbol): Boolean;
var
  mLast: Integer;
  mUnitName: string;
  mUnit: TUnitIndex;
begin
  // Cursor auf einem vorderen Teil eines Unit-Namens (Vcl in Vcl.Werkzeug):
  // die folgenden Teile ergänzen und den längsten passenden Unit-Namen nehmen.
  Result := False;
  mLast := AAt.Index;
  mUnitName := string.Join('.', AAt.Names);
  while (mLast + 2 < Length(AAt.Tokens)) and AAt.Tokens[mLast + 1].IsSymbol('.') and
    (AAt.Tokens[mLast + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(mLast, 2);
    mUnitName := mUnitName + '.' + CleanName(AAt.Tokens[mLast].Text);
    // Nur ein Versuch, ob die Teile eine Unit ergeben (TWerkzeug.Create meist nicht): ohne teures
    // Nachladen über alle Suchpfade, außer für Units aus uses (#647).
    if FUnits.FindQualifierUnit(mUnitName, mUnit) then
    begin
      ASymbol := TResolvedSymbol.OfUnit(mUnit);
      Result := True;
    end;
  end;
end;

function TResolverChains.ResolutionTarget(const AAt: TChainAt; out AResult: TArray<TResolvedSymbol>): Boolean;
var
  mOwner: string;
begin
  // Ziel einer Methodenzuordnung procedure IFoo.Bar = MyBar (#849): Methode des umgebenden Typs.
  AResult := nil;
  Result := False;
  if (AAt.Receiver = nil) and (AAt.First >= 1) and AAt.Tokens[AAt.First - 1].IsSymbol('=') then
  begin
    mOwner := ResolutionOwner(AAt.Tree.Root, AAt.Tokens[AAt.Index].Offset);
    Result := mOwner <> '';
  end;
  if Result then
  begin
    AResult := ResolveNames(AAt.Tree, AAt.FileName, mOwner.Split(['.']) + AAt.Names, AAt.Tokens[AAt.Index].Offset,
      TResolverChainStart.Plain);
  end;
end;

function TResolverChains.AttributeAt(const AAt: TChainAt): Boolean;
var
  mUse: TAttributeUse;
  mOpens, mDotFollows: Boolean;
begin
  mOpens := (AAt.First >= 1) and (AAt.Tokens[AAt.First - 1].IsSymbol('[') or AAt.Tokens[AAt.First - 1].IsSymbol(','));
  mDotFollows := (AAt.Index < High(AAt.Tokens)) and AAt.Tokens[AAt.Index + 1].IsSymbol('.');
  Result := (AAt.Receiver = nil) and mOpens and not mDotFollows and TAttributes.At(AAt.Tree, AAt.Position, mUse);
end;

function TResolverChains.AttributeTarget(const AAt: TChainAt): TArray<TResolvedSymbol>;
var
  mNames: TArray<string>;
  mOffset: Integer;
begin
  // Attribut (#119): [Foo] meint zuerst die Klasse FooAttribute, dann Foo; Argumente gehen an den Konstruktor.
  mOffset := AAt.Tokens[AAt.Index].Offset;
  mNames := Copy(AAt.Names);
  mNames[High(mNames)] := mNames[High(mNames)] + 'Attribute';
  Result := ResolveNames(AAt.Tree, AAt.FileName, mNames, mOffset, TResolverChainStart.Plain);
  if (Length(Result) = 0) or (Result[0].SymbolKind <> TIndexSymbolKind.ClassType) or
    not IsAttributeClass(Result[0]) then
  begin
    Result := ResolveNames(AAt.Tree, AAt.FileName, AAt.Names, mOffset, TResolverChainStart.Plain);
  end;
end;

function TResolverChains.ResolveTail(const AAt: TChainAt): TArray<TResolvedSymbol>;
var
  mCall: TSyntaxNode;
  mInherited: Boolean;
begin
  // Aufruf mit Klammern: Argumente bestimmen die Überladung.
  mCall := nil;
  if (AAt.Index < High(AAt.Tokens)) and AAt.Tokens[AAt.Index + 1].IsSymbol('(') then
  begin
    mCall := FindCall(AAt.Tokens[AAt.Index].Offset + Length(AAt.Tokens[AAt.Index].Text));
  end;
  mInherited := (AAt.Receiver = nil) and (AAt.First >= 1) and AAt.Tokens[AAt.First - 1].IsKeyword('inherited');
  if ResolutionTarget(AAt, Result) then
  begin
    Exit;
  end;
  if AttributeAt(AAt) then
  begin
    Exit(AttributeTarget(AAt));
  end;
  Result := ResolveNames(AAt.Tree, AAt.FileName, AAt.Names, AAt.Tokens[AAt.Index].Offset,
    TResolverChainStart.Make(mInherited, AAt.Receiver, mCall));
end;

function TResolverChains.ResolveAt(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
var
  mAt: TChainAt;
  mBefore: TPascalToken;
  mUnit: TResolvedSymbol;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  FPlace.Tree := ATree;
  mAt := Default(TChainAt);
  mAt.Tree := ATree;
  mAt.FileName := AFileName;
  mAt.Position := APosition;
  mAt.Tokens := ATree.Tokens;
  mAt.Index := ATree.IdentifierAt(APosition);
  if mAt.Index < 0 then
  begin
    Exit;
  end;
  mAt.Names := NamesBefore(mAt.Tokens, mAt.Index, mAt.First);
  // Foo(1).Bar, A[0].B, (X as TBar).C: Empfänger ist ein Ausdruck (#263).
  if (mAt.First >= 2) and mAt.Tokens[mAt.First - 1].IsSymbol('.') then
  begin
    mBefore := mAt.Tokens[mAt.First - 2];
    mAt.Receiver := FindReceiver(mBefore.Offset + Length(mBefore.Text));
    if mAt.Receiver = nil then
    begin
      Exit;
    end;
  end
  else if UnitAtCursor(mAt, mUnit) then
  begin
    Result := [mUnit];
    Exit;
  end;
  Result := ResolveTail(mAt);
end;

function TResolverChains.FindReceiver(AEndOffset: Integer): TSyntaxNode;
begin
  // Äußerster Ausdruck, der genau vor dem Punkt endet.
  Result := FindAround(FPlace.Tree.Root, AEndOffset,
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.Kind in cExpressionKinds) and (ANode.EndOffset = AEndOffset);
    end);
end;

function TResolverChains.FindCall(ACalleeEnd: Integer): TSyntaxNode;
begin
  Result := FindAround(FPlace.Tree.Root, ACalleeEnd,
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].EndOffset = ACalleeEnd);
    end);
end;

function TResolverChains.IsAttributeClass(const AType: TResolvedSymbol): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if SameText(mCurrent.Name, 'TCustomAttribute') then
    begin
      Exit(True);
    end;
    if (Length(mCurrent.Ancestors) = 0) or TResolverText.IsObjectRoot(mCurrent.Ancestors[0]) then
    begin
      Exit(False);
    end;
    if not FTyping.AncestorOf(mCurrent, mNext) then
    begin
      Break;
    end;
    mCurrent := mNext;
  end;
  Result := True;
end;

function TResolverChains.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
begin
  Result := FirstOf(ResolveNames(ATree, AFileName, ANames, AOffset, TResolverChainStart.Make(AInherited, nil, nil)));
end;

function TResolverChains.ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; out AResult: TResolvedChainType): Boolean;
begin
  AResult := Default(TResolvedChainType);
  AResult.Owner := ResolveChain(ATree, AFileName, ANames, AOffset, False);
  Result := AResult.Owner.Found;
  if Result and (AResult.Owner.Kind <> TResolvedKind.UnitName) then
  begin
    AResult.TypeFound := FTyping.TypeOf(AResult.Owner, AResult.TypeInfo);
  end;
end;

function TResolverChains.NodeType(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  ASymbol := Default(TResolvedSymbol);
  AType := Default(TResolvedSymbol);
  ATypeFound := False;
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  FPlace.MoveTo(ATree, AFileName, ANode.StartOffset);
  Result := FExpressions.ExprSymbol(ANode, ASymbol);
  if Result and (ASymbol.Kind <> TResolvedKind.UnitName) then
  begin
    ATypeFound := FTyping.TypeOf(ASymbol, AType);
  end;
end;

function TResolverChains.CallCandidates(ATree: TSyntaxTree; const AFileName: string;
  ACallee: TSyntaxNode): TArray<TResolvedSymbol>;
begin
  Result := nil;
  if ACallee = nil then
  begin
    Exit;
  end;
  FPlace.MoveTo(ATree, AFileName, ACallee.StartOffset);
  Result := FExpressions.ExprCandidates(ACallee);
end;

function TResolverChains.ElementDecides(AWith: TSyntaxNode; AIndex: Integer; const AName: string;
  out AHidden: Boolean): Boolean;
var
  mType: TResolvedSymbol;
  mComplete: Boolean;
begin
  AHidden := True;
  if not FExpressions.WithElementType(AWith, AIndex, mType) then
  begin
    Exit(True);
  end;
  AHidden := False;
  if Length(FMembers.FindMembers(mType, AName)) > 0 then
  begin
    Exit(True);
  end;
  FTyping.AncestorNames(mType, mComplete);
  AHidden := not mComplete;
  Result := AHidden;
end;

function TResolverChains.WithDecides(const AName: string; out AHidden: Boolean): Boolean;
var
  mWith: TSyntaxNode;
  mIndex: Integer;
begin
  // with-Objekte verdecken alles weiter außen, innerstes zuerst (wie LookupWithOwner).
  AHidden := False;
  for mWith in FPlace.EnclosingWiths do
  begin
    for mIndex := mWith.ChildCount - 2 downto 0 do
    begin
      if ElementDecides(mWith, mIndex, AName, AHidden) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TResolverChains.MayBeHiddenMember(ATree: TSyntaxTree; const AFileName: string; ACallee: TSyntaxNode;
  const ACandidate: TResolvedSymbol): Boolean;
begin
  Result := False;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  FPlace.MoveTo(ATree, AFileName, ACallee.StartOffset);
  if WithDecides(ACallee.Name, Result) then
  begin
    Exit;
  end;
  Result := (ACandidate.Kind <> TResolvedKind.Local) and (ACandidate.Container = '') and FTyping.HasUnknownAncestor;
end;

end.
