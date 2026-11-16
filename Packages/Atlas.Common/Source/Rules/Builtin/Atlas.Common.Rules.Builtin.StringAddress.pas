unit Atlas.Common.Rules.Builtin.StringAddress;

// Adresse der Zeichen eines Strings (#1130, Gruppe „Fehler finden“):
//   first-char-address
//                     @S[1] bzw. @S[Low(S)] mit S vom Typ string,
//                     UnicodeString, WideString, AnsiString, RawByteString oder
//                     UTF8String (sicher aufgelöst, wie bei
//                     suspicious-string-pointer-cast). Bei leerem S löst der
//                     Index mit {$R+} einen Bereichsfehler aus, ohne Prüfung
//                     ergibt sich ein Zeiger ins Leere; außerdem erzwingt der
//                     Indexzugriff eine eigene Kopie (UniqueString). PChar(S)
//                     bzw. PAnsiChar(S) zeigen auch bei leerem S auf ein #0.
//                     Steht der Ausdruck in PChar(…), PAnsiChar(…),
//                     PWideChar(…), PByte(…) oder Pointer(…), ersetzt die
//                     Korrektur die ganze Umwandlung. Korrektur nur bei
//                     const-Parametern: Bei anderen Strings kann der Zeiger
//                     zum Schreiben dienen, dann ist die eigene Kopie gewollt
//                     (die Meldung nennt dafür UniqueString). Still bleibt die
//                     Regel, wenn eine Bedingung S als nicht leer sichert
//                     (if S <> '' then, if Length(S) > 0 then, if N > 0 then
//                     nach SetLength(S, N), if S = '' then Exit davor, SetLength(S, 2) davor).
//                     string[N] und Aliase darauf sind ShortStrings: Dort
//                     ist @S[1] immer gültig, die Regel schweigt.


interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cFirstCharAddressRuleId = 'first-char-address';

type
  TFirstCharAddressRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterStringAddressRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Rules.Builtin.Constants.Conversions,

  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStringAddressText = (Title, EmptyRead, ReplaceWith, EmptyWrite);

const
  cTexts: array[TStringAddressText] of TAtlasText = (
    (De: 'Adresse des ersten Zeichens über S[1]'; En: 'Address of the first character via S[1]'),
    (De: 'Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. %s ist auch für leere Strings sicher.';
     En: 'With an empty %s, %s raises an error under range checking. %s is safe for empty strings too.'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. Zum Lesen ist %s auch für leere Strings ' +
      'sicher, zum Schreiben vorher UniqueString(%s).';
     En: 'With an empty %s, %s raises an error under range checking. For reading, %s is safe for empty strings too; ' +
      'for writing, call UniqueString(%s) first.'));

{$SCOPEDENUMS OFF}

{ TFirstCharAddressRule }

function TFirstCharAddressRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cFirstCharAddressRuleId, TRuleSeverity.Warning,
    cTexts[TStringAddressText.Title].Text);
end;

const
  cComparisons: array[0..3] of string = ('<', '>', '<=', '>=');
  cMirroredComparisons: array[0..3] of string = ('>', '<', '>=', '<=');

/// <summary>Vergleich mit vertauschten Seiten: aus 0 &lt; N wird N &gt; 0.</summary>
function MirroredOperator(const AOperator: string): string;
var
  mIndex: Integer;
begin
  Result := AOperator;
  mIndex := IndexStr(AOperator, cComparisons);
  if mIndex >= 0 then
  begin
    Result := cMirroredComparisons[mIndex];
  end;
end;

/// <summary>Ist der Vergleich Length(S) AOperator ALimit wahr nur bei nicht leerem S (ANonEmpty) bzw. nur bei
/// leerem S (not ANonEmpty)? AOperator und ALimit klein und ohne Leerraum.</summary>
function LengthSays(const AOperator, ALimit: string; ANonEmpty: Boolean): Boolean;
begin
  if ANonEmpty then
  begin
    Result := (ALimit = '0') and MatchStr(AOperator, ['>', '<>']) or (ALimit = '1') and (AOperator = '>=');
  end
  else
  begin
    Result := (ALimit = '0') and MatchStr(AOperator, ['=', '<=']) or (ALimit = '1') and (AOperator = '<');
  end;
end;

type
  /// <summary>Ein Lauf von TFirstCharAddressRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TFirstCharAddressScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    function IsFirstIndex(AIndex, ABase: TSyntaxNode): Boolean;
    function IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
    function LocalShortAlias(const ATypeName: string): Boolean;
    function DeclaredShort(const ASymbol: TResolvedSymbol): Boolean;
    function IsShortString(const ASymbol: TResolvedSymbol): Boolean;
    function PointerCast(ANode: TSyntaxNode): TSyntaxNode;
    function IsFirstCharAddress(ANode: TSyntaxNode; out ABase: TSyntaxNode; out ASymbol: TResolvedSymbol;
      out AWidth: Integer): Boolean;
    function Squeezed(ANode: TSyntaxNode): string;
    function IsLengthOf(ANode: TSyntaxNode; const ABase, ARoutine: string): Boolean;
    function ConditionSays(ACondition: TSyntaxNode; const ABase, ARoutine: string; ANonEmpty: Boolean): Boolean;
    function Leaves(ANode: TSyntaxNode): Boolean;
    function BranchGuards(AIf, AChild: TSyntaxNode; const ABase, ARoutine: string): Boolean;
    function SetsFixedLength(AStatement: TSyntaxNode; const ABase: string): Boolean;
    function LeftBefore(ABlock, AChild: TSyntaxNode; const ABase, ARoutine: string): Boolean;
    function GuardedNonEmpty(ANode, ABase: TSyntaxNode): Boolean;
    procedure CheckAddress(ANode: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TFirstCharAddressScan }

constructor TFirstCharAddressScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Ist AIndex der erste Index von ABase: 1 oder Low(ABase)?</summary>
function TFirstCharAddressScan.IsFirstIndex(AIndex, ABase: TSyntaxNode): Boolean;
begin
  AIndex := Unwrapped(AIndex);
  if (AIndex.Kind = TSyntaxKind.Literal) and (FScope.Text(AIndex) = '1') then
  begin
    Exit(True);
  end;
  Result := (AIndex.Kind = TSyntaxKind.Call) and (AIndex.ChildCount = 2) and
    (AIndex[0].Kind = TSyntaxKind.Identifier) and SameText(AIndex[0].Name, 'Low') and
    SameText(FScope.Text(Unwrapped(AIndex[1])), FScope.Text(ABase));
end;

/// <summary>Ist ASymbol ein const-Parameter dieser Datei? Vor dem Namen stehen nur weitere Namen mit Komma,
/// davor "const".</summary>
function TFirstCharAddressScan.IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := False;
  if not ASymbol.IsParameter or ((ASymbol.Kind <> TResolvedKind.Local) and
    not SameText(ASymbol.FileName, FScope.FileName)) then
  begin
    Exit;
  end;
  mTokens := FScope.Tokens;
  mIndex := FScope.TokenAtPosition(ASymbol.SelectionRange.StartPos) - 1;
  while mIndex >= 0 do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
    begin
      Dec(mIndex);
    end
    else if (mTokens[mIndex].Text = ',') or (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      not SameText(mTokens[mIndex].Text, 'const') then
    begin
      Dec(mIndex);
    end
    else
    begin
      Exit(SameText(mTokens[mIndex].Text, 'const'));
    end;
  end;
end;

/// <summary>Hat ein Typknoten der Datei namens ATypeName die Form string[N] bzw. ShortString?</summary>
function TFirstCharAddressScan.LocalShortAlias(const ATypeName: string): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, ATypeName) and (mNode.ChildCount > 0) then
      begin
        Result := TStringLengthLimitRule.ShortStringLength(FScope.Text(mNode[0])) > 0;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Steht in der Deklaration von ASymbol in dieser Datei (bis zum nächsten ';') string[…]?</summary>
function TFirstCharAddressScan.DeclaredShort(const ASymbol: TResolvedSymbol): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := False;
  if (ASymbol.Kind <> TResolvedKind.Local) and not SameText(ASymbol.FileName, FScope.FileName) then
  begin
    Exit;
  end;
  mTokens := FScope.Tokens;
  mIndex := FScope.TokenAtPosition(ASymbol.SelectionRange.StartPos);
  while (mIndex >= 0) and (mIndex < High(mTokens)) and (mTokens[mIndex].Text <> ';') do
  begin
    if SameText(mTokens[mIndex].Text, 'string') and (mTokens[mIndex + 1].Text = '[') then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Ist ASymbol ein ShortString (string[N] oder ein Alias darauf, auch aus dem Index)? @S[1] ist dort
/// immer gültig (FP mORMot2: TShort31 = string[31]); die Namensauflösung führt string[N] auf string zurück.
/// </summary>
function TFirstCharAddressScan.IsShortString(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (TStringLengthLimitRule.ShortStringLength(ASymbol.Signature) > 0) or
    (TStringLengthLimitRule.ShortStringLength(ASymbol.TypeName) > 0) or DeclaredShort(ASymbol);
  if not Result and IsValidIdent(ASymbol.TypeName, True) then
  begin
    Result := LocalShortAlias(ASymbol.TypeName) or
      (TStringLengthLimitRule.IndexAliasLength(FContext, ASymbol.TypeName) > 0);
  end;
end;

/// <summary>Umgebende Umwandlung in einen Zeigertyp (PChar(@S[1])) oder nil.</summary>
function TFirstCharAddressScan.PointerCast(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  while (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ParenExpr) do
  begin
    ANode := ANode.Parent;
  end;
  if (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.Call) or (ANode.Parent.ChildCount <> 2) then
  begin
    Exit;
  end;
  if (ANode.Parent[1] = ANode) and (ANode.Parent[0].Kind = TSyntaxKind.Identifier) and
    MatchText(ANode.Parent[0].Name, ['PChar', 'PAnsiChar', 'PWideChar', 'PByte', 'Pointer']) then
  begin
    Result := ANode.Parent;
  end;
end;

/// <summary>Ist ANode @S[1] auf einer String-Variablen oder einem String-Feld? Liefert S, das Symbol und die
/// Zeichenbreite.</summary>
function TFirstCharAddressScan.IsFirstCharAddress(ANode: TSyntaxNode; out ABase: TSyntaxNode;
  out ASymbol: TResolvedSymbol;
  out AWidth: Integer): Boolean;
var
  mAccess: TSyntaxNode;
  mType: TResolvedSymbol;
begin
  Result := False;
  ABase := nil;
  AWidth := 0;
  mAccess := nil;
  if ANode.ChildCount = 1 then
  begin
    mAccess := Unwrapped(ANode[0]);
  end;
  if (mAccess = nil) or (mAccess.Kind <> TSyntaxKind.IndexAccess) or (mAccess.ChildCount <> 2) or
    not IsFirstIndex(mAccess[1], mAccess[0]) then
  begin
    Exit;
  end;
  ABase := mAccess[0];
  if not FScope.SureType(ABase, ASymbol, mType) or ASymbol.IsType or
    not (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
  begin
    Exit;
  end;
  if mType.Builtin or SameText(mType.UnitName, 'System') then
  begin
    AWidth := TSuspiciousStringPointerCastRule.StringWidth(mType.Name);
  end;
  Result := (AWidth <> 0) and not IsShortString(ASymbol);
end;

/// <summary>Text von ANode klein und ohne Leerraum, zum Vergleichen von Bedingungen.</summary>
function TFirstCharAddressScan.Squeezed(ANode: TSyntaxNode): string;
begin
  Result := LowerCase(FScope.Text(ANode)).Replace(' ', '').Replace(#9, '').Replace(#13, '').Replace(#10, '');
end;

/// <summary>Ist ANode Length(S) oder eine Variable N mit SetLength(S, N) in der Routine ARoutine? S ist ABase
/// in Squeezed-Form.</summary>
function TFirstCharAddressScan.IsLengthOf(ANode: TSyntaxNode; const ABase, ARoutine: string): Boolean;
var
  mText: string;
begin
  mText := Squeezed(Unwrapped(ANode));
  Result := (mText = 'length(' + ABase + ')') or (ARoutine <> '') and (ANode.Kind = TSyntaxKind.Identifier) and
    ARoutine.Contains('setlength(' + ABase + ',' + mText + ')');
end;

/// <summary>Ist ACondition (oder ein mit and verknüpfter Teil) wahr nur bei nicht leerem S (ANonEmpty) bzw. nur
/// bei leerem S (not ANonEmpty)? Erkannt: S &lt;&gt; '', Length(S) &gt; 0, &gt;= 1, &lt;&gt; 0 und dieselben
/// Vergleiche mit der Länge aus SetLength(S, N).</summary>
function TFirstCharAddressScan.ConditionSays(ACondition: TSyntaxNode; const ABase, ARoutine: string;
  ANonEmpty: Boolean): Boolean;
var
  mOperator, mLeft, mRight: string;
begin
  ACondition := Unwrapped(ACondition);
  Result := False;
  if (ACondition.Kind <> TSyntaxKind.BinaryExpr) or (ACondition.ChildCount <> 2) then
  begin
    Exit;
  end;
  mOperator := LowerCase(ACondition.Name);
  if ANonEmpty and (mOperator = 'and') or not ANonEmpty and (mOperator = 'or') then
  begin
    Exit(ConditionSays(ACondition[0], ABase, ARoutine, ANonEmpty) or
      ConditionSays(ACondition[1], ABase, ARoutine, ANonEmpty));
  end;
  mLeft := Squeezed(Unwrapped(ACondition[0]));
  mRight := Squeezed(Unwrapped(ACondition[1]));
  if (mLeft = ABase) and (mRight = '''''') or (mRight = ABase) and (mLeft = '''''') then
  begin
    Result := ANonEmpty and (mOperator = '<>') or not ANonEmpty and (mOperator = '=');
  end
  else if IsLengthOf(ACondition[0], ABase, ARoutine) then
  begin
    Result := LengthSays(mOperator, mRight, ANonEmpty);
  end
  else if IsLengthOf(ACondition[1], ABase, ARoutine) then
  begin
    Result := LengthSays(MirroredOperator(mOperator), mLeft, ANonEmpty);
  end;
end;

/// <summary>Verlässt ANode die Routine bzw. Schleife (Exit, raise, Continue, Break)?</summary>
function TFirstCharAddressScan.Leaves(ANode: TSyntaxNode): Boolean;
var
  mText: string;
begin
  mText := Squeezed(ANode).Replace(';', '');
  if mText.StartsWith('begin') and mText.EndsWith('end') then
  begin
    mText := Copy(mText, 6, Length(mText) - 8);
  end;
  Result := (mText = 'exit') or mText.StartsWith('exit(') or mText.StartsWith('raise') or (mText = 'continue') or
    (mText = 'break');
end;

/// <summary>Ist AChild der then-Zweig eines if, das nur bei nicht leerem S gilt, bzw. der else-Zweig eines if,
/// das nur bei leerem S gilt?</summary>
function TFirstCharAddressScan.BranchGuards(AIf, AChild: TSyntaxNode; const ABase, ARoutine: string): Boolean;
begin
  Result := (AIf.Kind = TSyntaxKind.IfStatement) and (AIf.ChildCount > 1) and
    ((AIf[1] = AChild) and ConditionSays(AIf[0], ABase, ARoutine, True) or
    (AIf.ChildCount > 2) and (AIf[2] = AChild) and ConditionSays(AIf[0], ABase, ARoutine, False));
end;

/// <summary>Ist AStatement "SetLength(S, N)" mit einer Zahl N &gt; 0? S ist ABase in Squeezed-Form.</summary>
function TFirstCharAddressScan.SetsFixedLength(AStatement: TSyntaxNode; const ABase: string): Boolean;
var
  mCall: TSyntaxNode;
  mLength: Integer;
begin
  Result := False;
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mCall := AStatement[0];
  Result := (mCall.Kind = TSyntaxKind.Call) and (mCall.ChildCount = 3) and
    SameText(Squeezed(mCall[0]), 'setlength') and (Squeezed(mCall[1]) = ABase) and
    TryStrToInt(Squeezed(mCall[2]), mLength) and (mLength > 0);
end;

/// <summary>Steht im Block ABlock vor AChild ein "if S = '' then Exit;" oder "SetLength(S, 2);"?</summary>
function TFirstCharAddressScan.LeftBefore(ABlock, AChild: TSyntaxNode; const ABase, ARoutine: string): Boolean;
var
  mIndex: Integer;
  mStatement: TSyntaxNode;
begin
  Result := False;
  mIndex := 0;
  while not Result and (mIndex < ABlock.ChildCount) and (ABlock[mIndex] <> AChild) do
  begin
    mStatement := ABlock[mIndex];
    Result := (mStatement.Kind = TSyntaxKind.IfStatement) and (mStatement.ChildCount = 2) and
      Leaves(mStatement[1]) and ConditionSays(mStatement[0], ABase, ARoutine, False);
    Result := Result or SetsFixedLength(mStatement, ABase);
    Inc(mIndex);
  end;
end;

/// <summary>Steht ANode nur bei nicht leerem ABase: im then-Zweig von "if S &lt;&gt; '' then" bzw. hinter
/// "if S = '' then Exit;" (FP-Prüfung 28.10.2026, F12: SetLength(Result, Len); if Len &gt; 0 then … @Result[1]).
/// </summary>
function TFirstCharAddressScan.GuardedNonEmpty(ANode, ABase: TSyntaxNode): Boolean;
var
  mChild, mParent, mRoutineNode: TSyntaxNode;
  mBase, mRoutine: string;
begin
  Result := False;
  mBase := Squeezed(ABase);
  mRoutineNode := ANode.Parent;
  while (mRoutineNode <> nil) and (mRoutineNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    mRoutineNode := mRoutineNode.Parent;
  end;
  mRoutine := '';
  if mRoutineNode <> nil then
  begin
    mRoutine := Squeezed(mRoutineNode);
  end;
  mChild := ANode;
  mParent := ANode.Parent;
  while not Result and (mParent <> nil) and (mParent <> mRoutineNode) do
  begin
    Result := BranchGuards(mParent, mChild, mBase, mRoutine) or (mParent.Kind = TSyntaxKind.Block) and
      LeftBefore(mParent, mChild, mBase, mRoutine);
    mChild := mParent;
    mParent := mParent.Parent;
  end;
end;

procedure TFirstCharAddressScan.CheckAddress(ANode: TSyntaxNode);
var
  mBase, mCast, mReplaced: TSyntaxNode;
  mSymbol: TResolvedSymbol;
  mWidth: Integer;
  mPointer, mSafe, mMessage: string;
  mFixes: TArray<TRuleFix>;
begin
  if not IsFirstCharAddress(ANode, mBase, mSymbol, mWidth) or GuardedNonEmpty(ANode, mBase) then
  begin
    Exit;
  end;
  mPointer := 'PChar';
  if mWidth = 1 then
  begin
    mPointer := 'PAnsiChar';
  end;
  mCast := PointerCast(ANode);
  mReplaced := ANode;
  if mCast <> nil then
  begin
    mPointer := mCast[0].Name;
    mReplaced := mCast;
  end;
  mSafe := Format('%s(%s)', [mPointer, FScope.Text(mBase)]);
  mFixes := nil;
  if IsConstParameter(mSymbol) then
  begin
    mMessage := cTexts[TStringAddressText.EmptyRead].Fmt([FScope.Text(mBase), FScope.Text(ANode), mSafe]);
    mFixes := [TRuleFix.Create(cTexts[TStringAddressText.ReplaceWith].Fmt([mSafe]),
      [TTextEdit.Create(TTextRange.Create(mReplaced.StartPos, mReplaced.EndPos), mSafe)])];
  end
  else
  begin
    mMessage := cTexts[TStringAddressText.EmptyWrite].Fmt([FScope.Text(mBase), FScope.Text(ANode),
      mSafe, FScope.Text(mBase)]);
  end;
  FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, TRuleConfidence.High, mFixes);
end;

procedure TFirstCharAddressScan.Visit(ARoot: TSyntaxNode);
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AddressOf then
      begin
        CheckAddress(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TFirstCharAddressScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FScope := TTypedScope.Create(FContext);
  try
    Visit(FContext.Tree.Root);
  finally
    FScope.Free;
  end;
end;

procedure TFirstCharAddressRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TFirstCharAddressScan;
begin
  mScan := TFirstCharAddressScan.Create(AContext, AReport);
  mScan.Run;
end;

procedure RegisterStringAddressRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFirstCharAddressRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.StringAddress', cTexts);

end.
