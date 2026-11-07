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
  cInvalidVarArgumentRuleId = 'invalid-var-argument';

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
  Atlas.Common.Rules.Builtin.TypeChecks.Types,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeChecksVarArgumentsText = (NotVariable, ConstantOpenArray, Expression, ConstantExpression, ResultOf, Constant,
    TypedConstant, PropertyArg, ConstParameter, ValueArg, ViaLocal, AddressNeedsVariable, Title);

const
  cTexts: array[TTypeChecksVarArgumentsText] of TAtlasText = (
    (De: '%s ist keine Variable und kann nicht an einen %s-Parameter übergeben werden (wie E2197).';
     En: '%s is not a variable and cannot be passed to a %s parameter (like E2197).'),
    (De: 'Eine Konstante kann nicht als offenes Array an einen %s-Parameter übergeben werden (wie E2192).';
     En: 'A constant cannot be passed as open array to a %s parameter (like E2192).'),
    (De: 'An einen %s-Parameter muss eine Variable übergeben werden, kein Ausdruck (wie E2036).';
     En: 'A variable must be passed to a %s parameter, not an expression (like E2036).'),
    (De: 'Der konstante Ausdruck %s'; En: 'The constant expression %s'),
    (De: 'Das Ergebnis von %s'; En: 'The result of %s'),
    (De: 'Die Konstante %s'; En: 'The constant %s'),
    (De: 'Die typisierte Konstante %s'; En: 'The typed constant %s'),
    (De: 'Die Eigenschaft %s'; En: 'The property %s'),
    (De: 'Der const-Parameter %s'; En: 'The const parameter %s'),
    (De: 'Der Wert %s'; En: 'The value %s'),
    (De: 'Über eine lokale Variable %s übergeben'; En: 'Pass via a local variable %s'),
    (De: '@ braucht eine Variable; %s ist ein Ausdruck ohne Adresse (wie E2036).';
     En: '@ needs a variable; %s is an expression without address (like E2036).'),
    (De: 'Ungültiges Argument für einen var- oder out-Parameter'; En: 'Invalid argument for a var or out parameter'));

{$SCOPEDENUMS OFF}

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
  mWords: TArray<string>;
begin
  mWords := Trim(AModifier).Split([' ']);
  Result := '';
  if Length(mWords) > 0 then
  begin
    Result := LowerCase(mWords[High(mWords)]);
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
      AMessage := cTexts[TTypeChecksVarArgumentsText.NotVariable].Fmt([ADescription, AModifier]);
    TVarArgumentKind.OpenArrayConstant:
      AMessage := cTexts[TTypeChecksVarArgumentsText.ConstantOpenArray].Fmt([AModifier]);
    TVarArgumentKind.Expression:
      AMessage := cTexts[TTypeChecksVarArgumentsText.Expression].Fmt([AModifier]);
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
  mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := FResolver.NodeType(FContext.Tree, FFileName, ANode, ASymbol, mTypeInfo, mTypeFound);
end;

function TVarArgumentScan.IsTypedConstant(const ASymbol: TResolvedSymbol): Boolean;
var
  mDecl: TSyntaxNode;
  mColon, mEqual: Integer;
begin
  // Typisierte Konstante? Aus dem Kopf im Index ("C: Integer = 2") bzw. dem Baum.
  if (ASymbol.Kind <> TResolvedKind.Local) and (ASymbol.TypeName <> '') then
  begin
    Exit(True);
  end;
  if ASymbol.Signature <> '' then
  begin
    mColon := Pos(':', ASymbol.Signature);
    mEqual := Pos('=', ASymbol.Signature);
    Exit((mColon > 0) and ((mEqual = 0) or (mColon < mEqual)));
  end;
  Result := False;
  if (ASymbol.Kind = TResolvedKind.Local) and (FContext.Tree <> nil) then
  begin
    mDecl := DeclarationAt(FContext.Tree.Root, ASymbol.SelectionRange.StartPos);
    Result := (mDecl <> nil) and (mDecl.Kind = TSyntaxKind.ConstDecl) and (NodeTypeText(FContext.Text, mDecl) <> '');
  end;
end;

function TVarArgumentScan.IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
var
  mDecl: TSyntaxNode;
begin
  // Lokaler const- bzw. constref-Parameter?
  Result := False;
  if (ASymbol.Kind <> TResolvedKind.Local) or not ASymbol.IsParameter then
  begin
    Exit;
  end;
  mDecl := DeclarationAt(FContext.Tree.Root, ASymbol.SelectionRange.StartPos);
  Result := (mDecl <> nil) and (mDecl.Kind = TSyntaxKind.Parameter) and
    (mDecl.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam]);
end;

function TVarArgumentScan.IsConstantIdentifier(ANode: TSyntaxNode): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  // Untypisierte Konstante oder Aufzählungswert.
  Result := Resolve(ANode, mSymbol) and (mSymbol.SymbolKind in [TIndexSymbolKind.Constant,
    TIndexSymbolKind.EnumMember]) and not IsTypedConstant(mSymbol);
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
    AResult.Description := cTexts[TTypeChecksVarArgumentsText.ConstantExpression].Fmt([AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end
  else if AArgument.Kind <> TSyntaxKind.ParenExpr then
  begin
    AResult.Kind := TVarArgumentKind.Expression;
  end;
end;

function TVarArgumentScan.IsStringElement(AArgument: TSyntaxNode; const AParamType: string): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  // S[I] mit S vom Typ string an einen Zeichen-Parameter: übersetzt dcc (#1383), erkannt nur, damit das Element
  // nicht als Ausdruck gilt.
  Result := (AArgument.ChildCount = 2) and MatchText(AParamType, ['Char', 'WideChar', 'AnsiChar']) and
    (AArgument[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]);
  Result := Result and Resolve(AArgument[0], mSymbol) and
    (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) and
    IsStringText(DeclaredTypeText(FContext, mSymbol));
end;

procedure TVarArgumentScan.ClassifyCall(AArgument: TSyntaxNode; AOpenArray: Boolean;
  var AResult: TVarArgument);
var
  mSymbol: TResolvedSymbol;
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
  else if Resolve(AArgument[0], mSymbol) and not mSymbol.IsType and
    (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (mSymbol.TypeName <> '') then
  begin
    // Aufruf einer Funktion (keine Typumwandlung): ihr Ergebnis ist keine Variable.
    AResult.Description := cTexts[TTypeChecksVarArgumentsText.ResultOf].Fmt([NodeText(FContext, AArgument[0])]);
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
    AResult.Description := cTexts[TTypeChecksVarArgumentsText.Constant].Fmt([AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end
  else if not FWriteableConsts and (ASymbol.SymbolKind = TIndexSymbolKind.Constant) then
  begin
    AResult.Description := cTexts[TTypeChecksVarArgumentsText.TypedConstant].Fmt([AResult.Description]);
    AResult.Kind := TVarArgumentKind.ConstantObject;
  end;
end;

procedure TVarArgumentScan.ClassifySymbol(AArgument: TSyntaxNode; AOpenArray: Boolean;
  var AResult: TVarArgument);
var
  mSymbol: TResolvedSymbol;
begin
  if not Resolve(AArgument, mSymbol) then
  begin
    Exit;
  end;
  case mSymbol.SymbolKind of
    TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember:
      ClassifyConstant(mSymbol, AOpenArray, AResult);
    TIndexSymbolKind.Property_:
      begin
        AResult.Description := cTexts[TTypeChecksVarArgumentsText.PropertyArg].Fmt([AResult.Description]);
        AResult.WriteBack := ContainsText(' ' + mSymbol.Signature.Replace(';', ' ') + ' ', ' write ');
        AResult.Kind := TVarArgumentKind.ConstantObject;
      end;
    TIndexSymbolKind.Variable:
      if IsConstParameter(mSymbol) then
      begin
        AResult.Description := cTexts[TTypeChecksVarArgumentsText.ConstParameter].Fmt([AResult.Description]);
        AResult.Kind := TVarArgumentKind.ConstantObject;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TVarArgumentScan.Classify(AArgument: TSyntaxNode; const AParamType: string): TVarArgument;
var
  mOpenArray: Boolean;
begin
  // Was ist AArgument für einen var- bzw. out-Parameter vom Typ AParamType?
  Result := Default(TVarArgument);
  Result.Description := NodeText(FContext, AArgument);
  mOpenArray := StartsText('array of ', AParamType) and not SameText(NormalizedType(AParamType), 'array of const');
  case AArgument.Kind of
    TSyntaxKind.Literal:
      if mOpenArray then
      begin
        Result.Kind := TVarArgumentKind.OpenArrayConstant;
      end
      else
      begin
        Result.Description := cTexts[TTypeChecksVarArgumentsText.ValueArg].Fmt([Result.Description]);
        Result.Kind := TVarArgumentKind.ConstantObject;
      end;
    TSyntaxKind.SetConstructor:
      if mOpenArray then
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
      ClassifyExpression(AArgument, mOpenArray, Result);
    TSyntaxKind.IndexAccess:
      if IsStringElement(AArgument, AParamType) then
      begin
        Result.Kind := TVarArgumentKind.StringElement;
      end;
    TSyntaxKind.Call:
      ClassifyCall(AArgument, mOpenArray, Result);
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      ClassifySymbol(AArgument, mOpenArray, Result);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TVarArgumentScan.FixHost(ACall: TSyntaxNode): TSyntaxNode;
var
  mHost: TSyntaxNode;
  mFits: Boolean;
  mRest: string;
begin
  // Anweisung um ACall, vor die die Korrektur ihre Zeilen setzt: ein Aufruf oder X := Aufruf, allein in einer
  // Zeile einer Anweisungsliste; nil sonst.
  Result := nil;
  mHost := ACall.Parent;
  if mHost = nil then
  begin
    Exit;
  end;
  mFits := (mHost.Kind = TSyntaxKind.CallStatement) or
    ((mHost.Kind = TSyntaxKind.AssignStatement) and (mHost.ChildCount = 2) and (mHost[1] = ACall));
  mFits := mFits and TRoutineBody.InList(mHost) and (mHost.StartPos.Line = mHost.EndPos.Line);
  mFits := mFits and (mHost.EndPos.Line <= High(FLines));
  if not mFits then
  begin
    Exit;
  end;
  mRest := Trim(Copy(FLines[mHost.EndPos.Line], mHost.EndPos.Character + 1, MaxInt));
  if (mRest = '') or (mRest = ';') then
  begin
    Result := mHost;
  end;
end;

function TVarArgumentScan.KnownParamType(const AParamType: string): Boolean;
var
  mTypeSymbol: TResolvedSymbol;
begin
  Result := (AParamType <> '') and not StartsText('array of', AParamType);
  Result := Result and (TResolverText.IsBuiltinTypeName(AParamType) or
    FResolver.ResolveTypeFrom(FLocal, AParamType, mTypeSymbol));
end;

function TVarArgumentScan.LocalVariableFix(ACall, AArgument: TSyntaxNode; const AParamType: string; AOut,
  AWriteBack: Boolean; out AFix: TRuleFix): Boolean;
var
  mHost, mRoutine: TSyntaxNode;
  mName, mArgument, mIndent: string;
  mEdits: TArray<TTextEdit>;
  mLine: Integer;
begin
  // Korrektur: das Argument über eine lokale Variable vom Typ des Parameters übergeben, bei String-Elementen und
  // beschreibbaren Eigenschaften mit Rückschreiben.
  Result := False;
  mHost := FixHost(ACall);
  if mHost = nil then
  begin
    Exit;
  end;
  mRoutine := TRoutineBody.RoutineAt(FContext.Tree, mHost.StartOffset);
  if (mRoutine = nil) or not KnownParamType(AParamType) then
  begin
    Exit;
  end;
  mName := TRoutineBody.UniqueName(FContext.Tree.Tokens, 'Wert');
  mArgument := NodeText(FContext, AArgument);
  mIndent := TTextLines.IndentOf(FLines[mHost.StartPos.Line]);
  mEdits := [TRoutineBody.AddVariable(FContext.Text, mRoutine, mName, AParamType, FContext.Formatting)];
  if not AOut then
  begin
    mEdits := mEdits + [TRoutineBody.InsertBefore(FContext.Text, mHost, mName + ' := ' + mArgument + ';')];
  end;
  mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), mName)];
  if AWriteBack then
  begin
    mLine := mHost.EndPos.Line;
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mLine, Length(FLines[mLine]), mLine, Length(FLines[mLine])),
      FLineBreak + mIndent + mArgument + ' := ' + mName + ';')];
  end;
  AFix := TRuleFix.Create(cTexts[TTypeChecksVarArgumentsText.ViaLocal].Fmt([mName]), mEdits);
  Result := True;
end;

function TVarArgumentScan.CalledParams(ACall: TSyntaxNode; out AParams: TArray<TSignatureParameter>): Boolean;
var
  mSymbol: TResolvedSymbol;
  mArgCount: Integer;
begin
  AParams := nil;
  Result := (ACall.ChildCount >= 2) and (ACall[0].Kind <> TSyntaxKind.InheritedExpr) and Resolve(ACall, mSymbol);
  Result := Result and not mSymbol.IsType and
    (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]);
  Result := Result and RoutineParams(FContext, mSymbol, AParams);
  if not Result or (mSymbol.Signature = '') then
  begin
    Exit;
  end;
  // Passt die Zahl der Argumente nicht zum Kopf, ist es eine andere Routine (bzw. ein anderer Fehler).
  mArgCount := ACall.ChildCount - 1;
  Result := (mArgCount >= mSymbol.MinArgs) and (mArgCount <= mSymbol.MaxArgs);
end;

procedure TVarArgumentScan.CheckArgument(ACall: TSyntaxNode; AIndex: Integer; const AParam: TSignatureParameter);
var
  mModifier, mMessage, mParamType: string;
  mArgument: TSyntaxNode;
  mFound: TVarArgument;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mModifier := ModifierWord(AParam.Modifier);
  if (mModifier <> 'var') and (mModifier <> 'out') then
  begin
    Exit;
  end;
  mArgument := ACall[AIndex];
  mParamType := NormalizedType(AParam.TypeName);
  mFound := Classify(mArgument, mParamType);
  if not ArgumentMessage(mFound.Kind, mFound.Description, mModifier, mMessage) then
  begin
    Exit;
  end;
  mFixes := nil;
  if (mFound.Kind in [TVarArgumentKind.ConstantObject, TVarArgumentKind.Expression]) and
    LocalVariableFix(ACall, mArgument, mParamType, mModifier = 'out', mFound.WriteBack, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos), mMessage, TRuleConfidence.High, mFixes);
end;

procedure TVarArgumentScan.CheckCall(ACall: TSyntaxNode);
var
  mParams: TArray<TSignatureParameter>;
  mIndex: Integer;
begin
  if not CalledParams(ACall, mParams) then
  begin
    Exit;
  end;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    if mIndex > Length(mParams) then
    begin
      Break;
    end;
    CheckArgument(ACall, mIndex, mParams[mIndex - 1]);
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
    FReport.Add(TTextRange.Create(AAddress.StartPos, AAddress.EndPos),
      cTexts[TTypeChecksVarArgumentsText.AddressNeedsVariable].Fmt([NodeText(FContext, AAddress[0])]),
      TRuleConfidence.High);
  end;
end;

{ TInvalidVarArgumentRule }

function TInvalidVarArgumentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInvalidVarArgumentRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksVarArgumentsText.Title].Text);
end;

procedure TInvalidVarArgumentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mNode: TSyntaxNode;
  mScan: TVarArgumentScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mScan := TVarArgumentScan.Create(AContext, AReport, mResolver, mFileName);
    try
      for mNode in PreOrder(AContext.Tree.Root) do
      begin
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 1) then
        begin
          mScan.CheckCall(mNode);
        end
        else if mNode.Kind = TSyntaxKind.AddressOf then
        begin
          mScan.CheckAddress(mNode);
        end;
      end;
    finally
      mScan.Free;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeChecks.VarArguments', cTexts);

end.
