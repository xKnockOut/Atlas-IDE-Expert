unit Atlas.Common.Rules.Builtin.IgnoredResult;

// ignored-result (#624): Ergebnis einer Funktion ohne Seiteneffekte als eigene Anweisung verworfen. Trim(S); ändert
// S nicht, S.Replace('a', 'b'); auch nicht. Gemeldet werden
//   - Standardroutinen aus Atlas.Common.Pascal.PureRoutines (Trim, Format, StringReplace, TPath.Combine …), auch
//     mit Unit davor (SysUtils.Trim). Löst die Namensauflösung den Namen auf eine Routine außerhalb der RTL auf
//     oder deklariert die Datei selbst eine Routine dieses Namens, schweigt die Regel (eigenes Trim mit
//     var-Parameter).
//   - Methoden von TStringHelper ohne Seiteneffekte (S.Trim, S.ToUpper, S.Replace(…)), nur wenn der Empfänger
//     sicher vom Typ string ist.
//   - Funktionen aus der Option pureFunctions (Name, Klasse.Name oder Unit.Name), ohne weitere Prüfung.
// In with-Blöcken schweigt die Regel: Dort kann der Name ein Mitglied des with-Objekts sein.
// Korrektur „Ergebnis zuweisen“: Liefert die Funktion denselben Typ wie ihr erstes Argument bzw. der Empfänger
// (Trim, StringReplace, Copy, S.Replace …) und ist dieses zuweisbar, wird daraus S := Trim(S). Sonst eine neue
// Inline-Variable (var Ergebnis := …), wenn die Anweisung direkt in einem Block steht und die eingestellte
// Delphi-Version Inline-Variablen kennt (ab 10.3, #109).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cIgnoredResultRuleId = 'ignored-result';

type
  TIgnoredResultRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet ignored-result in ARegistry an.</summary>
procedure RegisterIgnoredResultRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TIgnoredResultText = (Title, Message, AssignTo, NewVariable, VariableName);

const
  cTexts: array[TIgnoredResultText] of TAtlasText = (
    (De: 'Ergebnis einer Funktion ohne Seiteneffekte verworfen';
     En: 'Result of a function without side effects discarded'),
    (De: 'Das Ergebnis von %s wird verworfen: Die Funktion hat keine Seiteneffekte, der Aufruf bewirkt nichts.';
     En: 'The result of %s is discarded: the function has no side effects, so the call does nothing.'),
    (De: 'Ergebnis zuweisen: %s := …'; En: 'Assign the result: %s := …'),
    (De: 'Ergebnis zuweisen: var %s := …'; En: 'Assign the result: var %s := …'),
    // Name der neuen Inline-Variablen; das Präfix lokaler Variablen setzt die Namensregel davor.
    (De: 'Ergebnis'; En: 'Value'));

{$SCOPEDENUMS OFF}

const
  // Standardroutinen, die denselben Typ liefern wie ihr erstes Argument: Zurückschreiben ist gemeint.
  cSameTypeRoutines: array[0..24] of string = ('Trim', 'TrimLeft', 'TrimRight', 'LowerCase', 'UpperCase',
    'AnsiLowerCase', 'AnsiUpperCase', 'StringReplace', 'Copy', 'QuotedStr', 'AnsiQuotedStr',
    'IncludeTrailingPathDelimiter', 'ExcludeTrailingPathDelimiter', 'IncludeTrailingBackslash',
    'ExcludeTrailingBackslash', 'ChangeFileExt', 'ChangeFilePath', 'AdjustLineBreaks', 'LeftStr', 'RightStr',
    'MidStr', 'ReplaceStr', 'ReplaceText', 'AnsiReplaceStr', 'AnsiReplaceText');
  // Methoden von TStringHelper, die wieder einen string liefern.
  cSameTypeMembers: array[0..16] of string = ('Trim', 'TrimLeft', 'TrimRight', 'TrimStart', 'TrimEnd', 'ToUpper',
    'ToLower', 'ToUpperInvariant', 'ToLowerInvariant', 'Replace', 'Substring', 'PadLeft', 'PadRight', 'Insert',
    'Remove', 'QuotedString', 'DeQuotedString');
  // Typnamen, für die TStringHelper gilt (TCaption nicht, siehe caption-string-helper).
  cStringTypes: array[0..1] of string = ('string', 'UnicodeString');

type
  /// <summary>Aufruf einer Anweisung, zerlegt: Name, Empfänger (S bei S.Trim, TPath bei TPath.Combine) bzw. nil
  /// und erstes Argument bzw. nil.</summary>
  TIgnoredCall = record
    Expression: TSyntaxNode;
    Callee: TSyntaxNode;
    Receiver: TSyntaxNode;
    FirstArgument: TSyntaxNode;
    Name: string;
  end;

  /// <summary>Eine Prüfung einer Datei.</summary>
  TIgnoredResultCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    FTypes: TExpressionTypes;
    FExtra: TArray<string>;
    FDeclared: TArray<string>;
    function Text(ANode: TSyntaxNode): string;
    function Raw(ANode: TSyntaxNode): string;
    function Split(AExpression: TSyntaxNode; out ACall: TIgnoredCall): Boolean;
    function IsExtra(const ACall: TIgnoredCall): Boolean;
    function IsRtlRoutine(const ACall: TIgnoredCall): Boolean;
    function IsStringReceiver(ANode: TSyntaxNode): Boolean;
    function InWith(ANode: TSyntaxNode): Boolean;
    function SameType(const ACall: TIgnoredCall): Boolean;
    function FreeName: string;
    function Fixes(AStatement: TSyntaxNode; const ACall: TIgnoredCall): TArray<TRuleFix>;
    procedure CollectDeclared(ARoot: TSyntaxNode);
    procedure Inspect(AStatement: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TIgnoredResultCheck }

constructor TIgnoredResultCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TExpressionTypeOptions;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FExtra := TRuleOptions.Strings(AContext.Options, 'pureFunctions', nil);
  FScope := TTypedScope.Create(AContext);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  FTypes := TExpressionTypes.Create(FScope.Resolver, AContext.Tree, FScope.FileName, AContext.Text, AContext.Index,
    mOptions);
end;

destructor TIgnoredResultCheck.Destroy;
begin
  FTypes.Free;
  FScope.Free;
  inherited;
end;

function TIgnoredResultCheck.Text(ANode: TSyntaxNode): string;
begin
  Result := FScope.Text(ANode);
end;

function TIgnoredResultCheck.Raw(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TIgnoredResultCheck.Split(AExpression: TSyntaxNode; out ACall: TIgnoredCall): Boolean;
begin
  ACall := Default(TIgnoredCall);
  ACall.Expression := AExpression;
  if (AExpression.Kind = TSyntaxKind.Call) and (AExpression.ChildCount >= 1) then
  begin
    ACall.Callee := AExpression[0];
    if AExpression.ChildCount >= 2 then
    begin
      ACall.FirstArgument := AExpression[1];
    end;
  end
  else if AExpression.Kind = TSyntaxKind.MemberAccess then
  begin
    // S.Trim; ohne Klammern
    ACall.Callee := AExpression;
  end
  else
  begin
    Exit(False);
  end;
  if ACall.Callee.Kind = TSyntaxKind.MemberAccess then
  begin
    if ACall.Callee.ChildCount <> 1 then
    begin
      // Generische Argumente (TArray.Map<T>)
      Exit(False);
    end;
    ACall.Receiver := ACall.Callee[0];
  end
  else if ACall.Callee.Kind <> TSyntaxKind.Identifier then
  begin
    Exit(False);
  end;
  ACall.Name := ACall.Callee.Name;
  Result := ACall.Name <> '';
end;

function TIgnoredResultCheck.IsExtra(const ACall: TIgnoredCall): Boolean;
var
  mEntry, mText: string;
  mSymbol: TResolvedSymbol;
begin
  if FExtra = nil then
  begin
    Exit(False);
  end;
  mText := Text(ACall.Callee);
  for mEntry in FExtra do
  begin
    if SameText(mEntry, mText) then
    begin
      Exit(True);
    end;
  end;
  // Unit.Name: Unit der aufgelösten Deklaration.
  mSymbol := FScope.Resolver.Resolve(FContext.Tree, FScope.FileName, ACall.Callee.StartPos);
  if (mSymbol.Kind = TResolvedKind.Symbol) and (mSymbol.UnitName <> '') then
  begin
    for mEntry in FExtra do
    begin
      if SameText(mEntry, mSymbol.UnitName + '.' + ACall.Name) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TIgnoredResultCheck.IsRtlRoutine(const ACall: TIgnoredCall): Boolean;
var
  mReceiver: string;
  mSymbol: TResolvedSymbol;
begin
  if ACall.Receiver <> nil then
  begin
    mReceiver := Text(ACall.Receiver);
    // string.Join, TPath.Combine; SysUtils.Trim bzw. System.SysUtils.Trim
    if TPureRoutines.IsPure(mReceiver + '.' + ACall.Name) then
    begin
      Exit(True);
    end;
    Exit(TPureRoutines.IsRtlUnit(mReceiver) and TPureRoutines.IsPure(ACall.Name) and (Pos('.', ACall.Name) = 0));
  end;
  if not TPureRoutines.IsPure(ACall.Name) or MatchText(ACall.Name, FDeclared) then
  begin
    Exit(False);
  end;
  // Eigene Routine gleichen Namens (auch aus einer anderen Unit des Projekts) geht vor.
  mSymbol := FScope.Resolver.Resolve(FContext.Tree, FScope.FileName, ACall.Callee.StartPos);
  case mSymbol.Kind of
    TResolvedKind.Local:
      Result := False;
    TResolvedKind.Symbol:
      Result := TPureRoutines.IsRtlUnit(mSymbol.UnitName);
  else
    Result := True;
  end;
end;

function TIgnoredResultCheck.IsStringReceiver(ANode: TSyntaxNode): Boolean;
var
  mInfo: TExpressionTypeInfo;
  mType: string;
  mDot: Integer;
begin
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    Exit(StartsStr('''', Raw(ANode)) or StartsStr('#', Raw(ANode)));
  end;
  mInfo := FTypes.Describe(ANode);
  if not mInfo.Found then
  begin
    Exit(False);
  end;
  mType := mInfo.TypeName;
  mDot := LastDelimiter('.', mType);
  mType := Copy(mType, mDot + 1, MaxInt);
  Result := MatchText(mType, cStringTypes) or (mInfo.BaseName <> '') and MatchText(mInfo.BaseName, cStringTypes) and
    not SameText(mType, 'TCaption');
end;

function TIgnoredResultCheck.InWith(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.WithStatement then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

function TIgnoredResultCheck.SameType(const ACall: TIgnoredCall): Boolean;
begin
  if ACall.Receiver <> nil then
  begin
    Result := MatchText(ACall.Name, cSameTypeMembers) and TPureRoutines.IsPureStringMember(ACall.Name);
  end
  else
  begin
    Result := MatchText(ACall.Name, cSameTypeRoutines);
  end;
end;

function TIgnoredResultCheck.FreeName: string;
var
  mBase: string;
  mNumber: Integer;
  mToken: TPascalToken;
  mTaken: Boolean;
begin
  mBase := FContext.NewNames.Local(cTexts[TIgnoredResultText.VariableName].Text);
  Result := mBase;
  mNumber := 1;
  repeat
    mTaken := False;
    for mToken in FContext.Tree.Tokens do
    begin
      if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, Result) then
      begin
        mTaken := True;
        Break;
      end;
    end;
    if mTaken then
    begin
      Inc(mNumber);
      Result := mBase + IntToStr(mNumber);
    end;
  until not mTaken;
end;

function TIgnoredResultCheck.Fixes(AStatement: TSyntaxNode; const ACall: TIgnoredCall): TArray<TRuleFix>;
var
  mTarget: TSyntaxNode;
  mTargetText, mName: string;
  mAt: TTextRange;
begin
  Result := nil;
  mAt := TTextRange.Create(ACall.Expression.StartPos, ACall.Expression.StartPos);
  if ACall.Receiver <> nil then
  begin
    mTarget := ACall.Receiver;
  end
  else
  begin
    mTarget := ACall.FirstArgument;
  end;
  if (mTarget <> nil) and SameType(ACall) and (mTarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) then
  begin
    mTargetText := Raw(mTarget);
    Result := [TRuleFix.Create(cTexts[TIgnoredResultText.AssignTo].Fmt([Text(mTarget)]),
      [TRuleEdit.Create(mAt, mTargetText + ' := ')])];
    Exit;
  end;
  if (AStatement.Parent <> nil) and (AStatement.Parent.Kind = TSyntaxKind.Block) and
    TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, FContext.DelphiVersion) then
  begin
    mName := FreeName;
    Result := [TRuleFix.Create(cTexts[TIgnoredResultText.NewVariable].Fmt([mName]),
      [TRuleEdit.Create(mAt, 'var ' + mName + ' := ')])];
  end;
end;

procedure TIgnoredResultCheck.CollectDeclared(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  FDeclared := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
      begin
        // TKlasse.Trim im implementation-Teil zählt als Trim.
        mName := mNode.Name;
        mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
        if (mName <> '') and TPureRoutines.IsPure(mName) then
        begin
          FDeclared := FDeclared + [mName];
        end;
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

procedure TIgnoredResultCheck.Inspect(AStatement: TSyntaxNode);
var
  mExpression: TSyntaxNode;
  mCall: TIgnoredCall;
  mReport: Boolean;
begin
  mExpression := Unwrapped(AStatement[0]);
  if (mExpression = nil) or not Split(mExpression, mCall) or InWith(AStatement) then
  begin
    Exit;
  end;
  mReport := IsExtra(mCall) or IsRtlRoutine(mCall);
  if not mReport and (mCall.Receiver <> nil) and TPureRoutines.IsPureStringMember(mCall.Name) then
  begin
    mReport := IsStringReceiver(mCall.Receiver);
  end;
  if mReport then
  begin
    FReport.Add(TTextRange.Create(mExpression.StartPos, mExpression.EndPos),
      cTexts[TIgnoredResultText.Message].Fmt([Text(mCall.Callee)]), TRuleConfidence.High,
      Fixes(AStatement, mCall));
  end;
end;

procedure TIgnoredResultCheck.Run;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  CollectDeclared(FContext.Tree.Root);
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) then
      begin
        Inspect(mNode);
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

{ TIgnoredResultRule }

function TIgnoredResultRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cIgnoredResultRuleId, TRuleSeverity.Warning,
    cTexts[TIgnoredResultText.Title].Text);
end;

procedure TIgnoredResultRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TIgnoredResultCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TIgnoredResultCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterIgnoredResultRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TIgnoredResultRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.IgnoredResult', cTexts);

end.
