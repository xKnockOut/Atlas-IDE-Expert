unit Atlas.Common.Rules.Builtin.TypeChecks.Types;

// Gemeinsame Hilfen der Typprüfungen (TypeChecks, TypeChecks.Hresult, TypeChecks.VarArguments, StringConversions):
// deklarierte Typen als Text, dynamische Arrays und prozedurale Typen über Aliase, Parameter einer Routine aus Index
// oder Baum, Knoten in Pre-Order.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature;

/// <summary>Dateiname für die Namensauflösung wie in den übrigen Regeln.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
/// <summary>Quelltext von ANode.</summary>
function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
/// <summary>Typtext ohne Leerzeichen vor spitzen Klammern ("TArray &lt;Integer&gt;" aus dem Index).</summary>
function NormalizedType(const AText: string): string;
/// <summary>Typ der Deklaration ANode (Variable, Parameter, Feld, Typ) als Quelltext; '' ohne.</summary>
function NodeTypeText(const AText: string; ANode: TSyntaxNode): string;
/// <summary>Alle Knoten unter ARoot (samt ARoot) in der Reihenfolge eines rekursiven Laufs, aber über einen
/// eigenen Stapel: Ausdrucksketten können sehr tief sein.</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
/// <summary>Innerste Deklaration (Variable, Parameter, Feld, Typ, Konstante) um APosition; nil ohne.</summary>
function DeclarationAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
/// <summary>Deklarierter Typ von ASymbol als Quelltext ("TArray&lt;Double&gt;", "array of Integer"); bei Aliasen
/// der Typ hinter "=". Aus TypeName, sonst aus dem Kopf des Index, sonst aus der Deklaration im Baum (lokale
/// Namen). '' wenn unbekannt.</summary>
function DeclaredTypeText(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
/// <summary>Steht der Typtext selbst für ein dynamisches Array (array of T, TArray&lt;T&gt;)? array of const
/// ist ein offenes Array.</summary>
function IsDynamicArrayText(const AText: string): Boolean;
/// <summary>Ist der Typtext ATypeName, so wie er in AFromUnit steht, ein dynamisches Array? Aliase werden
/// verfolgt (TWerte = array of Double; TListe = TWerte). False, wenn es nicht sicher feststeht.</summary>
function IsDynamicArrayType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
/// <summary>Ist der Typtext, so wie er in AFromUnit steht, ein prozeduraler Typ ohne of object und ohne
/// reference to (procedure(...), function(...): T bzw. ein Alias darauf)? False, wenn es nicht sicher feststeht.
/// </summary>
function IsPlainProcedureType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
/// <summary>Parameter der Routine ASymbol in Reihenfolge, je Name ein Eintrag: aus dem Kopf im Index bzw. für
/// lokale Routinen aus dem Baum (auch für string-conversion, #1377). False bei Überladungen (auch mit overload im
/// Kopf) oder unbekanntem Kopf.</summary>
function RoutineParams(const AContext: TRuleContext; const ASymbol: TResolvedSymbol;
  out AParams: TArray<TSignatureParameter>): Boolean;
/// <summary>Unit, in der ein aufgelöstes Symbol steht (bei lokalen Namen die geprüfte Datei).</summary>
function SymbolUnit(AResolver: TNameResolver; const ALocal: TUnitIndex; const ASymbol: TResolvedSymbol;
  out AUnit: TUnitIndex): Boolean;
/// <summary>Ist ACallee ein Aufruf der eingebauten Routine AName (nicht überdeckt von einer eigenen
/// Deklaration gleichen Namens)?</summary>
function IsIntrinsicCall(AResolver: TNameResolver; const AContext: TRuleContext; const AFileName: string;
  ACallee: TSyntaxNode; const AName: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  // Dynamische Arrays der RTL, auch wenn ihre Unit nicht im Index steht.
  cRtlDynamicArrays: array[0..9] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TStringArray',
    'TObjectDynArray', 'TWordDynArray', 'TCardinalDynArray', 'TInt64DynArray', 'TDoubleDynArray',
    'TBooleanDynArray');
  cMaxAliasDepth = 16;
  // Prozedurale Typen der RTL ohne of object, auch wenn ihre Unit nicht im Index steht.
  cRtlPlainProcedureTypes: array[0..3] of string = ('TListSortCompare', 'TStringListSortCompare',
    'TThreadFunc', 'TFarProc');

type
  TSyntaxKinds = set of TSyntaxKind;

/// <summary>Dateiname für die Namensauflösung wie in den übrigen Regeln.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Typtext ohne Leerzeichen vor spitzen Klammern ("TArray &lt;Integer&gt;" aus dem Index).</summary>
function NormalizedType(const AText: string): string;
begin
  Result := Trim(AText).Replace(' <', '<').Replace('< ', '<').Replace(' >', '>');
end;

/// <summary>Typ der Deklaration ANode (Variable, Parameter, Feld, Typ) als Quelltext; '' ohne.</summary>
function NodeTypeText(const AText: string; ANode: TSyntaxNode): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
      TSyntaxKind.FileType] then
    begin
      Exit(Trim(Copy(AText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset)));
    end;
  end;
end;

/// <summary>Alle Knoten unter ARoot (samt ARoot) in der Reihenfolge eines rekursiven Laufs, aber über einen
/// eigenen Stapel: Ausdrucksketten können sehr tief sein.</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  mNodes := TList<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mNodes.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
    mPending.Free;
  end;
end;

/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((ANode.EndPos.Line > APosition.Line) or
    ((ANode.EndPos.Line = APosition.Line) and (ANode.EndPos.Character >= APosition.Character)));
end;

/// <summary>Letzter Knoten der Arten AKinds in Pre-Order, der APosition umfasst; nil ohne. Teilbäume mit
/// bekanntem Bereich, der APosition nicht umfasst, überspringt die Suche: Vorher lief jede Abfrage über alle
/// Knoten der Datei (PreOrder), je Aufruf bzw. Deklaration, also quadratisch in der Länge der Unit.</summary>
function LastCovering(ARoot: TSyntaxNode; const APosition: TTextPosition; const AKinds: TSyntaxKinds): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mEndKnown: Boolean;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  // Eigener Stapel: Ausdrucksketten können sehr tief sein.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mEndKnown := (mNode.EndPos.Line > 0) or (mNode.EndPos.Character > 0);
      if mEndKnown and not Covers(mNode, APosition) then
      begin
        Continue;
      end;
      if (mNode.Kind in AKinds) and Covers(mNode, APosition) then
      begin
        Result := mNode;
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

/// <summary>Innerste Deklaration (Variable, Parameter, Feld, Typ, Konstante) um APosition; nil ohne.</summary>
function DeclarationAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
begin
  // Pre-Order: Der letzte Treffer ist der innerste.
  Result := LastCovering(ARoot, APosition, [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field,
    TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar]);
end;

/// <summary>Typ hinter dem ersten ':' bzw. '=' auf oberster Klammerebene einer Signatur ("Werte: array of Double"
/// bzw. "TWerte = array of Double"), bis vor ';'; '' ohne.</summary>
function TypeAfterSeparator(const ASignature: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(ASignature) do
  begin
    if CharInSet(ASignature[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(ASignature[mIndex], [')', ']', '>']) then
    begin
      Dec(mDepth);
    end
    else if CharInSet(ASignature[mIndex], [':', '=']) and (mDepth = 0) then
    begin
      Result := Copy(ASignature, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  if Pos(';', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos(';', Result) - 1);
  end;
  if Result <> '' then
  begin
    Result := NormalizedType(Result);
  end;
end;

/// <summary>Typ der lokalen Deklaration von ASymbol aus dem Baum; '' ohne.</summary>
function LocalDeclaredType(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
var
  mDecl: TSyntaxNode;
begin
  Result := '';
  if (ASymbol.Kind <> TResolvedKind.Local) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mDecl := DeclarationAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  if mDecl <> nil then
  begin
    Result := NormalizedType(NodeTypeText(AContext.Text, mDecl));
  end;
end;

function DeclaredTypeText(const AContext: TRuleContext; const ASymbol: TResolvedSymbol): string;
begin
  if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
    if ASymbol.TypeArgs <> '' then
    begin
      Result := Result + '<' + ASymbol.TypeArgs + '>';
    end;
    Result := NormalizedType(Result);
  end
  else if ASymbol.Signature <> '' then
  begin
    Result := TypeAfterSeparator(ASymbol.Signature);
  end
  else
  begin
    Result := LocalDeclaredType(AContext, ASymbol);
  end;
end;

/// <summary>Steht der Typtext selbst für ein dynamisches Array (array of T, TArray&lt;T&gt;)? array of const
/// ist ein offenes Array.</summary>
function IsDynamicArrayText(const AText: string): Boolean;
var
  mText: string;
begin
  mText := NormalizedType(AText);
  Result := (StartsText('array of ', mText) and not SameText(mText, 'array of const')) or
    StartsText('TArray<', mText) or StartsText('System.TArray<', mText);
end;

/// <summary>Ist der Typtext ATypeName, so wie er in AFromUnit steht, ein dynamisches Array? Aliase werden
/// verfolgt (TWerte = array of Double; TListe = TWerte). False, wenn es nicht sicher feststeht.</summary>
function IsDynamicArrayType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
var
  mName: string;
  mCurrent: TResolvedSymbol;
  mFromUnit: TUnitIndex;
  mDepth: Integer;
begin
  mName := NormalizedType(ATypeName);
  mFromUnit := AFromUnit;
  for mDepth := 0 to cMaxAliasDepth do
  begin
    if IsDynamicArrayText(mName) then
    begin
      Exit(True);
    end;
    if (mName = '') or (Pos(' ', mName) > 0) or (Pos('<', mName) > 0) or (Pos('^', mName) > 0) then
    begin
      Exit(False);
    end;
    if not AResolver.ResolveTypeFrom(mFromUnit, mName, mCurrent) then
    begin
      // Ohne Deklaration im Index: nur die bekannten Arrays der RTL.
      Exit(MatchText(mName, cRtlDynamicArrays) or MatchText(Copy(mName, LastDelimiter('.', mName) + 1, MaxInt),
        cRtlDynamicArrays));
    end;
    if mCurrent.Builtin or (mCurrent.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(mCurrent, mFromUnit) then
    begin
      Exit(False);
    end;
    mName := DeclaredTypeText(AContext, mCurrent);
  end;
  Result := False;
end;

/// <summary>Ist der Typtext, so wie er in AFromUnit steht, ein prozeduraler Typ ohne of object und ohne
/// reference to (procedure(...), function(...): T bzw. ein Alias darauf)? False, wenn es nicht sicher feststeht.
/// </summary>
function IsPlainProcedureType(AResolver: TNameResolver; const AContext: TRuleContext; const AFromUnit: TUnitIndex;
  const ATypeName: string): Boolean;
var
  mName: string;
  mCurrent: TResolvedSymbol;
  mFromUnit: TUnitIndex;
  mDepth: Integer;
begin
  mName := NormalizedType(ATypeName);
  mFromUnit := AFromUnit;
  for mDepth := 0 to cMaxAliasDepth do
  begin
    if StartsText('procedure', mName) or StartsText('function', mName) then
    begin
      Exit(not ContainsText(mName, ' of object'));
    end;
    if (mName = '') or (Pos(' ', mName) > 0) or (Pos('<', mName) > 0) or (Pos('^', mName) > 0) then
    begin
      Exit(False);
    end;
    if not AResolver.ResolveTypeFrom(mFromUnit, mName, mCurrent) then
    begin
      Exit(MatchText(Copy(mName, LastDelimiter('.', mName) + 1, MaxInt), cRtlPlainProcedureTypes));
    end;
    if mCurrent.Builtin or (mCurrent.SymbolKind <> TIndexSymbolKind.TypeAlias) or
      not AResolver.DeclaringUnit(mCurrent, mFromUnit) then
    begin
      Exit(False);
    end;
    mName := DeclaredTypeText(AContext, mCurrent);
  end;
  Result := False;
end;

/// <summary>Index der Klammer, die die Klammer an AOpen schließt; 0 ohne.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
end;

/// <summary>Parameter aus dem Kopf ASignature des Index; False, wenn die Klammer nicht schließt oder overload im
/// Kopf steht.</summary>
function SignatureParams(const ASignature: string; out AParams: TArray<TSignatureParameter>): Boolean;
var
  mOpen, mClose: Integer;
begin
  AParams := nil;
  mOpen := Pos('(', ASignature);
  if mOpen = 0 then
  begin
    Exit(True);
  end;
  mClose := ClosingParen(ASignature, mOpen);
  // Überladungen aus anderen Units kennt die Namensauflösung nicht immer (Overloads leer); die Direktive
  // im Kopf zeigt sie sicher an.
  Result := (mClose > 0) and not MatchText('overload', SplitString(LowerCase(Copy(ASignature, mClose + 1, MaxInt)),
    ' ;'));
  if Result then
  begin
    AParams := TChangeSignature.ParseParameters(Copy(ASignature, mOpen + 1, mClose - mOpen - 1));
  end;
end;

/// <summary>Kopf der lokalen Routine, deren Name an APosition steht; nil ohne.</summary>
function HeaderAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
begin
  Result := LastCovering(ARoot, APosition, [TSyntaxKind.RoutineHeader]);
end;

function ModifierText(AModifier: TParameterModifier): string;
begin
  case AModifier of
    TParameterModifier.ConstParam:
      Result := 'const';
    TParameterModifier.VarParam:
      Result := 'var';
    TParameterModifier.OutParam:
      Result := 'out';
    TParameterModifier.ConstRefParam:
      Result := 'constref';
  else
    Result := '';
  end;
end;

/// <summary>Parameter aus dem Kopf AHeader im Baum, je Name ein Eintrag.</summary>
function HeaderParams(const AText: string; AHeader: TSyntaxNode): TArray<TSignatureParameter>;
var
  mParameters, mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mParameter: TSignatureParameter;
begin
  Result := nil;
  mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    mNode := mParameters[mIndex];
    if mNode.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    for mName in mNode.Name.Split([',']) do
    begin
      mParameter := Default(TSignatureParameter);
      mParameter.Name := Trim(mName);
      mParameter.Group := mIndex;
      mParameter.TypeName := NodeTypeText(AText, mNode);
      mParameter.Modifier := ModifierText(mNode.Modifier);
      Result := Result + [mParameter];
    end;
  end;
end;

function RoutineParams(const AContext: TRuleContext; const ASymbol: TResolvedSymbol;
  out AParams: TArray<TSignatureParameter>): Boolean;
var
  mHeader: TSyntaxNode;
begin
  AParams := nil;
  Result := False;
  if (Length(ASymbol.Overloads) > 0) or (Length(ASymbol.VariantParams) > 1) then
  begin
    Exit;
  end;
  if ASymbol.Signature <> '' then
  begin
    Exit(SignatureParams(ASymbol.Signature, AParams));
  end;
  if (ASymbol.Kind <> TResolvedKind.Local) or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  mHeader := HeaderAt(AContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  Result := mHeader <> nil;
  if Result then
  begin
    AParams := HeaderParams(AContext.Text, mHeader);
  end;
end;

/// <summary>Unit, in der ein aufgelöstes Symbol steht (bei lokalen Namen die geprüfte Datei).</summary>
function SymbolUnit(AResolver: TNameResolver; const ALocal: TUnitIndex; const ASymbol: TResolvedSymbol;
  out AUnit: TUnitIndex): Boolean;
begin
  if ASymbol.Kind = TResolvedKind.Local then
  begin
    AUnit := ALocal;
    Exit(True);
  end;
  Result := AResolver.DeclaringUnit(ASymbol, AUnit);
end;

/// <summary>Ist ACallee ein Aufruf der eingebauten Routine AName (nicht überdeckt von einer eigenen
/// Deklaration gleichen Namens)?</summary>
function IsIntrinsicCall(AResolver: TNameResolver; const AContext: TRuleContext; const AFileName: string;
  ACallee: TSyntaxNode; const AName: string): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := False;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.Identifier) or not SameText(ACallee.Name, AName) then
  begin
    Exit;
  end;
  if not AResolver.NodeType(AContext.Tree, AFileName, ACallee, mSymbol, mTypeInfo, mTypeFound) then
  begin
    Exit(True);
  end;
  Result := mSymbol.Builtin or SameText(mSymbol.UnitName, 'System');
end;

end.
