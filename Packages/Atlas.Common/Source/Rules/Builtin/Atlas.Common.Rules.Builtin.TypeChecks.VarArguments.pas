unit Atlas.Common.Rules.Builtin.TypeChecks.VarArguments;

// Typprüfung invalid-var-argument (#1037), registriert mit den übrigen Typprüfungen (RegisterTypeCheckRules):
//   An einen var- oder out-Parameter geht eine Konstante, ein const-Parameter, eine Property oder ein
//   Funktionsergebnis (wie E2197), eine Konstante an ein offenes Array (wie E2192) oder ein Ausdruck (wie E2036);
//   ebenso @ vor einem Rechenausdruck wie @(mZahl + 1) (wie E2036, Cm.E2036, #1380). Slice an ein var- oder
//   out-Open-Array übersetzt dcc (Spring4D TArray.Sort<T>, IV1-IV4; dcc-Lauf vom 29.10.2026, #1328): Slice übergibt
//   den Speicher des Arrays. Nur bei eindeutiger Routine ohne Überladungen und ohne eingebaute Routinen (Inc, Move
//   ... nehmen mehr an). Ein String-Element (S[I]) an einen var-Zeichen-Parameter übersetzt dcc ebenfalls (E2354
//   gab es nur unter .NET; Cm.E2354, #1383). Korrektur: über eine lokale Variable übergeben, bei Properties mit
//   write mit Rückschreiben.

interface

uses
  Atlas.Common.Rules.Contract;

const
  InvalidVarArgumentRuleId = 'invalid-var-argument';

type
  TInvalidVarArgumentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.TypeChecks.Types;

type
  /// <summary>Art eines unzulässigen Arguments für einen var- bzw. out-Parameter.</summary>
  TVarArgumentKind = (None, StringElement, ConstantObject, OpenArrayConstant, SliceCall, Expression);

  /// <summary>Einordnung eines Arguments: Art, Nennung in der Meldung und ob die Korrektur den Wert zurückschreibt.
  /// </summary>
  TVarArgument = record
    Kind: TVarArgumentKind;
    Description: string;
    WriteBack: Boolean;
  end;

  /// <summary>Prüft die Argumente für var- und out-Parameter in einer Datei.</summary>
  TVarArgumentScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FResolver: TNameResolver;
    FFileName: string;
    FLocal: TUnitIndex;
    FLines: TArray<string>;
    FLineBreak: string;
    /// <summary>Typisierte Konstanten sind mit {$J+} beschreibbar.</summary>
    FWriteableConsts: Boolean;
    function Resolve(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
    function IsTypedConstant(const ASymbol: TResolvedSymbol): Boolean;
    function IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
    function IsConstantIdentifier(ANode: TSyntaxNode): Boolean;
    function IsConstantExpression(AExpression: TSyntaxNode): Boolean;
    procedure ClassifyExpression(AArgument: TSyntaxNode; AOpenArray: Boolean; var AResult: TVarArgument);
    function IsStringElement(AArgument: TSyntaxNode; const AParamType: string): Boolean;
    procedure ClassifyCall(AArgument: TSyntaxNode; AOpenArray: Boolean; var AResult: TVarArgument);
    procedure ClassifyConstant(const ASymbol: TResolvedSymbol; AOpenArray: Boolean; var AResult: TVarArgument);
    procedure ClassifySymbol(AArgument: TSyntaxNode; AOpenArray: Boolean; var AResult: TVarArgument);
    function Classify(AArgument: TSyntaxNode; const AParamType: string): TVarArgument;
    function FixHost(ACall: TSyntaxNode): TSyntaxNode;
    function KnownParamType(const AParamType: string): Boolean;
    function LocalVariableFix(ACall, AArgument: TSyntaxNode; const AParamType: string; AOut, AWriteBack: Boolean;
      out AFix: TRuleFix): Boolean;
    function CalledParams(ACall: TSyntaxNode; out AParams: TArray<TSignatureParameter>): Boolean;
    procedure CheckArgument(ACall: TSyntaxNode; AIndex: Integer; const AParam: TSignatureParameter);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AResolver: TNameResolver;
      const AFileName: string);
    procedure CheckCall(ACall: TSyntaxNode);
    procedure CheckAddress(AAddress: TSyntaxNode);
  end;

function ModifierWord(const AModifier: string): string;
var
  Words: TArray<string>;
begin
  Words := Trim(AModifier).Split([' ']);
  Result := '';
  if Length(Words) > 0 then
  begin
    Result := LowerCase(Words[High(Words)]);
  end;
end;

function IsStringText(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String', 'System.string', 'System.UnicodeString', 'System.AnsiString', 'System.WideString']);
end;

/// <summary>Meldung zur Art AKind; False bei Arten, die dcc übersetzt bzw. die keine Meldung bekommen.</summary>
function ArgumentMessage(AKind: TVarArgumentKind; const ADescription, AModifier: string;
  out AMessage: string): Boolean;
begin
  Result := True;
  case AKind of
    TVarArgumentKind.ConstantObject:
      AMessage := Format('%s ist keine Variable und kann nicht an einen %s-Parameter übergeben werden (wie E2197).',
        [ADescription, AModifier]);
    TVarArgumentKind.OpenArrayConstant:
      AMessage := Format('Eine Konstante kann nicht als offenes Array an einen %s-Parameter übergeben werden ' +
        '(wie E2192).', [AModifier]);
    TVarArgumentKind.Expression:
      AMessage := Format('An einen %s-Parameter muss eine Variable übergeben werden, kein Ausdruck (wie E2036).',
        [AModifier]);
  else
    // String-Element und Slice an var und out übersetzt dcc (#1383, IV1-IV4); erkannt nur, damit sie nicht als
    // Ausdruck bzw. Funktionsergebnis gelten.
    AMessage := '';
    Result := False;
  end;
end;

{ TVarArgumentScan }

constructor TVarArgumentScan.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver; const AFileName: string);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FFileName := AFileName;
  FLocal := AResolver.ExtractedUnit(AContext.Tree, AFileName);
  FWriteableConsts := ContainsText(AContext.Text, '{$J+') or ContainsText(AContext.Text, '{$WRITEABLECONST ON') or
    ContainsText(AContext.Text, ',J+');
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  if FLineBreak = '' then
  begin
    FLineBreak := sLineBreak;
  end;
end;

function TVarArgumentScan.Resolve(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
var
  TypeInfo: TResolvedSymbol;
  TypeFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, TypeInfo, TypeFound);
end;

function TVarArgumentScan.IsTypedConstant(const ASymbol: TResolvedSymbol): Boolean;
var
  Decl: TSyntaxNode;
  Colon, Equal: Integer;
begin
  // Typisierte Konstante? Aus dem Kopf im Index ("C: Integer = 2") bzw. dem Baum.
  if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.TypeName <> '') then
  begin
    Exit(True);
  end;
  if ASymbol.Signature <> '' then
  begin
    Colon := Pos(':', ASymbol.Signature);
    Equal := Pos('=', ASymbol.Signature);
    Exit((Colon > 0) and ((Equal = 0) or (Colon < Equal)));
  end;
  Result := False;
  if (ASymbol.Kind = TResolvedKind.Local) and (FContext.Tree <> nil) then
  begin
    Decl := DeclarationAt(FContext.Tree.Root, ASymbol.SelectionRange.StartPos);
    Result := (Decl <> nil) and (Decl.Kind = TSyntaxKind.ConstDecl) and (NodeTypeText(FContext.Text, Decl) <> '');
  end;
end;

function TVarArgumentScan.IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
var
  Decl: TSyntaxNode;
begin
  // Lokaler const- bzw. constref-Parameter?
  Result := False;
  if (ASymbol.Kind <> TResolvedKind.Local) or not ASymbol.IsParameter then
  begin
    Exit;
  end;
  Decl := DeclarationAt(FContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  Result := (Decl <> nil) and (Decl.Kind = TSyntaxKind.Parameter) and
    (Decl.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam]);
end;

function TVarArgumentScan.IsConstantIdentifier(ANode: TSyntaxNode): Boolean;
var
  Symbol: TResolvedSymbol;
begin
  // Untypisierte Konstante oder Aufzählungswert.
  Result := Resolve(ANode, Symbol) and (Symbol.SymbolKind in [TIndexSymbolKind.Constant,
    TIndexSymbolKind.EnumMember]) and not IsTypedConstant(Symbol);
end;

function TVarArgumentScan.IsConstantExpression(AExpression: TSyntaxNode): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Besteht AExpression nur aus Literalen, untypisierten Konstanten und Aufzählungswerten (cGrenze + 1)? Dann meldet
  // dcc E2197 statt E2036 (VG3, #1382).
  Result := True;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AExpression);
    while Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      case mNode.Kind of
        TSyntaxKind.Literal:
          Continue;
        TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr:
          Result := not MatchText(mNode.Name, ['as', 'is']) and (mNode.ChildCount > 0);
        TSyntaxKind.Identifier:
          Result := IsConstantIdentifier(mNode);
      else
        Result := False;
      end;
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TVarArgumentScan.ClassifyExpression(AArgument: TSyntaxNode; AOpenArray: Boolean;
  var AResult: TVarArgument);
begin
  // "X as TFoo" ist eine Typumwandlung; der Compiler meldet sie anders. Ein konstanter Ausdruck ist für dcc ein
  // konstantes Objekt (E2197), sonst fehlt die Variable (E2036).
  if (AArgument.Kind = TSyntaxKind.BinaryExpr) and SameText(AArgument.Name, 'as') then
  begin
    Exit;
  end;
  if not AOpenArray and IsConstantExpression(AArgument) then
  begin
    AResult.Description := Format('Der konstante Ausdruck %s', [AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end
  else if AArgument.Kind <> TSyntaxKind.ParenExpr then
  begin
    AResult.Kind := TVarArgumentKind.Expression;
  end;
end;

function TVarArgumentScan.IsStringElement(AArgument: TSyntaxNode; const AParamType: string): Boolean;
var
  Symbol: TResolvedSymbol;
begin
  // S[I] mit S vom Typ string an einen Zeichen-Parameter: übersetzt dcc (#1383), erkannt nur, damit das Element
  // nicht als Ausdruck gilt.
  Result := (AArgument.ChildCount = 2) and MatchText(AParamType, ['Char', 'WideChar', 'AnsiChar']) and
    (AArgument[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
  Result := Result and Resolve(AArgument[0], Symbol) and
    (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) and
    IsStringText(DeclaredTypeText(FContext, Symbol));
end;

procedure TVarArgumentScan.ClassifyCall(AArgument: TSyntaxNode; AOpenArray: Boolean;
  var AResult: TVarArgument);
var
  Symbol: TResolvedSymbol;
begin
  if AArgument.ChildCount = 0 then
  begin
    Exit;
  end;
  if (AArgument[0].Kind = TSyntaxKind.Identifier) and SameText(AArgument[0].Name, 'Slice') and AOpenArray and
    IsIntrinsicCall(FResolver, FContext, FFileName, AArgument[0], 'Slice') then
  begin
    AResult.Kind := TVarArgumentKind.SliceCall;
  end
  else if Resolve(AArgument[0], Symbol) and not Symbol.IsType and
    (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (Symbol.TypeName <> '') then
  begin
    // Aufruf einer Funktion (keine Typumwandlung): ihr Ergebnis ist keine Variable.
    AResult.Description := Format('Das Ergebnis von %s', [NodeText(FContext, AArgument[0])]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end;
end;

procedure TVarArgumentScan.ClassifyConstant(const ASymbol: TResolvedSymbol; AOpenArray: Boolean;
  var AResult: TVarArgument);
begin
  if not IsTypedConstant(ASymbol) then
  begin
    if AOpenArray then
    begin
      AResult.Kind := TVarArgumentKind.OpenArrayConstant;
      Exit;
    end;
    AResult.Description := Format('Die Konstante %s', [AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end
  else if not FWriteableConsts and (ASymbol.SymbolKind = TIndexSymbolKind.Constant) then
  begin
    AResult.Description := Format('Die typisierte Konstante %s', [AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end;
end;

procedure TVarArgumentScan.ClassifySymbol(AArgument: TSyntaxNode; AOpenArray: Boolean;
  var AResult: TVarArgument);
var
  Symbol: TResolvedSymbol;
begin
  if not Resolve(AArgument, Symbol) then
  begin
    Exit;
  end;
  case Symbol.SymbolKind of
    TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember:
      ClassifyConstant(Symbol, AOpenArray, AResult);
    TIndexSymbolKind.Property_:
      begin
        AResult.Description := Format('Die Eigenschaft %s', [AResult.Description]);
        AResult.WriteBack := ContainsText(' ' + Symbol.Signature.Replace(';', ' ') + ' ', ' write ');
        AResult.Kind := TVarArgumentKind.ConstantObject;
      end;
    TIndexSymbolKind.Variable:
      if IsConstParameter(Symbol) then
      begin
        AResult.Description := Format('Der const-Parameter %s', [AResult.Description]);
        AResult.Kind := TVarArgumentKind.ConstantObject;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TVarArgumentScan.Classify(AArgument: TSyntaxNode; const AParamType: string): TVarArgument;
var
  OpenArray: Boolean;
begin
  // Was ist AArgument für einen var- bzw. out-Parameter vom Typ AParamType?
  Result := Default(TVarArgument);
  Result.Description := NodeText(FContext, AArgument);
  OpenArray := StartsText('array of ', AParamType) and not SameText(NormalizedType(AParamType), 'array of const');
  case AArgument.Kind of
    TSyntaxKind.Literal:
      if OpenArray then
      begin
        Result.Kind := TVarArgumentKind.OpenArrayConstant;
      end
      else
      begin
        Result.Description := Format('Der Wert %s', [Result.Description]);
        Result.Kind := TVarArgumentKind.ConstantObject;
      end;
    TSyntaxKind.SetConstructor:
      if OpenArray then
      begin
        Result.Kind := TVarArgumentKind.OpenArrayConstant;
      end
      else
      begin
        Result.Kind := TVarArgumentKind.Expression;
      end;
    TSyntaxKind.AddressOf:
      Result.Kind := TVarArgumentKind.Expression;
    TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr, TSyntaxKind.ParenExpr:
      ClassifyExpression(AArgument, OpenArray, Result);
    TSyntaxKind.IndexAccess:
      if IsStringElement(AArgument, AParamType) then
      begin
        Result.Kind := TVarArgumentKind.StringElement;
      end;
    TSyntaxKind.Call:
      ClassifyCall(AArgument, OpenArray, Result);
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      ClassifySymbol(AArgument, OpenArray, Result);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TVarArgumentScan.FixHost(ACall: TSyntaxNode): TSyntaxNode;
var
  Host: TSyntaxNode;
  Fits: Boolean;
  Rest: string;
begin
  // Anweisung um ACall, vor die die Korrektur ihre Zeilen setzt: ein Aufruf oder X := Aufruf, allein in einer
  // Zeile einer Anweisungsliste; nil sonst.
  Result := nil;
  Host := ACall.Parent;
  if Host = nil then
  begin
    Exit;
  end;
  Fits := (Host.Kind = TSyntaxKind.CallStatement) or
    ((Host.Kind = TSyntaxKind.AssignStatement) and (Host.ChildCount = 2) and (Host[1] = ACall));
  Fits := Fits and TRoutineBody.InList(Host) and (Host.StartPos.Line = Host.EndPos.Line);
  Fits := Fits and (Host.EndPos.Line <= High(FLines));
  if not Fits then
  begin
    Exit;
  end;
  Rest := Trim(Copy(FLines[Host.EndPos.Line], Host.EndPos.Character + 1, MaxInt));
  if (Rest = '') or (Rest = ';') then
  begin
    Result := Host;
  end;
end;

function TVarArgumentScan.KnownParamType(const AParamType: string): Boolean;
var
  TypeSymbol: TResolvedSymbol;
begin
  Result := (AParamType <> '') and not StartsText('array of', AParamType);
  Result := Result and (TResolverText.IsBuiltinTypeName(AParamType) or
    FResolver.ResolveTypeFrom(FLocal, AParamType, TypeSymbol));
end;

function TVarArgumentScan.LocalVariableFix(ACall, AArgument: TSyntaxNode; const AParamType: string; AOut,
  AWriteBack: Boolean; out AFix: TRuleFix): Boolean;
var
  Host, Routine: TSyntaxNode;
  Name, Argument, Indent: string;
  Edits: TArray<TTextEdit>;
  Line: Integer;
begin
  // Korrektur: das Argument über eine lokale Variable vom Typ des Parameters übergeben, bei String-Elementen und
  // beschreibbaren Eigenschaften mit Rückschreiben.
  Result := False;
  Host := FixHost(ACall);
  if Host = nil then
  begin
    Exit;
  end;
  Routine := TRoutineBody.RoutineAt(FContext.Tree, Host.StartOffset);
  if (Routine = nil) or not KnownParamType(AParamType) then
  begin
    Exit;
  end;
  Name := TRoutineBody.UniqueName(FContext.Tree.Tokens, 'Wert');
  Argument := NodeText(FContext, AArgument);
  Indent := TTextLines.IndentOf(FLines[Host.StartPos.Line]);
  Edits := [TRoutineBody.AddVariable(FContext.Text, Routine, Name, AParamType, FContext.Formatting)];
  if not AOut then
  begin
    Edits := Edits + [TRoutineBody.InsertBefore(FContext.Text, Host, Name + ' := ' + Argument + ';')];
  end;
  Edits := Edits + [TTextEdit.Create(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Name)];
  if AWriteBack then
  begin
    Line := Host.EndPos.Line;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Line, Length(FLines[Line]), Line, Length(FLines[Line])),
      FLineBreak + Indent + Argument + ' := ' + Name + ';')];
  end;
  AFix := TRuleFix.Create(Format('Über eine lokale Variable %s übergeben', [Name]), Edits);
  Result := True;
end;

function TVarArgumentScan.CalledParams(ACall: TSyntaxNode; out AParams: TArray<TSignatureParameter>): Boolean;
var
  Symbol: TResolvedSymbol;
  ArgCount: Integer;
begin
  AParams := nil;
  Result := (ACall.ChildCount >= 2) and (ACall[0].Kind <> TSyntaxKind.InheritedExpr) and Resolve(ACall, Symbol);
  Result := Result and not Symbol.IsType and
    (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]);
  Result := Result and RoutineParams(FContext, Symbol, AParams);
  if not Result or (Symbol.Signature = '') then
  begin
    Exit;
  end;
  // Passt die Zahl der Argumente nicht zum Kopf, ist es eine andere Routine (bzw. ein anderer Fehler).
  ArgCount := ACall.ChildCount - 1;
  Result := (ArgCount >= Symbol.MinArgs) and (ArgCount <= Symbol.MaxArgs);
end;

procedure TVarArgumentScan.CheckArgument(ACall: TSyntaxNode; AIndex: Integer; const AParam: TSignatureParameter);
var
  Modifier, Message, ParamType: string;
  Argument: TSyntaxNode;
  Found: TVarArgument;
  Fix: TRuleFix;
  Fixes: TArray<TRuleFix>;
begin
  Modifier := ModifierWord(AParam.Modifier);
  if (Modifier <> 'var') and (Modifier <> 'out') then
  begin
    Exit;
  end;
  Argument := ACall[AIndex];
  ParamType := NormalizedType(AParam.TypeName);
  Found := Classify(Argument, ParamType);
  if not ArgumentMessage(Found.Kind, Found.Description, Modifier, Message) then
  begin
    Exit;
  end;
  Fixes := nil;
  if (Found.Kind in [TVarArgumentKind.ConstantObject, TVarArgumentKind.Expression]) and
    LocalVariableFix(ACall, Argument, ParamType, Modifier = 'out', Found.WriteBack, Fix) then
  begin
    Fixes := [Fix];
  end;
  FReport.Add(TTextRange.Create(Argument.StartPos, Argument.EndPos), Message, TRuleConfidence.High, Fixes);
end;

procedure TVarArgumentScan.CheckCall(ACall: TSyntaxNode);
var
  Params: TArray<TSignatureParameter>;
  Index: Integer;
begin
  if not CalledParams(ACall, Params) then
  begin
    Exit;
  end;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    if Index > Length(Params) then
    begin
      Break;
    end;
    CheckArgument(ACall, Index, Params[Index - 1]);
  end;
end;

procedure TVarArgumentScan.CheckAddress(AAddress: TSyntaxNode);
var
  mInner: TSyntaxNode;
begin
  // E2036 (#1380): @ vor einem Rechenausdruck; die Adresse gibt es nur von Variablen.
  if AAddress.ChildCount <> 1 then
  begin
    Exit;
  end;
  mInner := AAddress[0];
  while (mInner.Kind = TSyntaxKind.ParenExpr) and (mInner.ChildCount = 1) do
  begin
    mInner := mInner[0];
  end;
  if (mInner.Kind = TSyntaxKind.BinaryExpr) and MatchText(mInner.Name, ['+', '-', '*', '/', 'div', 'mod', 'and',
    'or', 'xor', 'shl', 'shr']) then
  begin
    FReport.Add(TTextRange.Create(AAddress.StartPos, AAddress.EndPos), Format('@ braucht eine Variable; %s ist ' +
      'ein Ausdruck ohne Adresse (wie E2036).', [NodeText(FContext, AAddress[0])]), TRuleConfidence.High);
  end;
end;

{ TInvalidVarArgumentRule }

function TInvalidVarArgumentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InvalidVarArgumentRuleId, TRuleSeverity.Error,
    'Ungültiges Argument für einen var- oder out-Parameter');
end;

procedure TInvalidVarArgumentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Node: TSyntaxNode;
  Scan: TVarArgumentScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Scan := TVarArgumentScan.Create(AContext, AReport, Resolver, FileName);
    try
      for Node in PreOrder(AContext.Tree.Root) do
      begin
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 1) then
        begin
          Scan.CheckCall(Node);
        end
        else if Node.Kind = TSyntaxKind.AddressOf then
        begin
          Scan.CheckAddress(Node);
        end;
      end;
    finally
      Scan.Free;
    end;
  finally
    Resolver.UnpinTree;
  end;
end;

end.
