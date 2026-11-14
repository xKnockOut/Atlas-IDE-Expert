unit Atlas.Common.Rules.Builtin.CompilerTraps;

// Fallen, die erst dcc meldet (#1345, Gruppe Compiler vorab); FPC übersetzt die Fälle oft:
//   exit-array-literal         Exit([...]) in einer Funktion mit dynamischem Array als Ergebnis: Delphi liest
//                              [...] dort als Menge (wie E2001 bzw. E2010). Korrektur: Result := [...]; Exit;
//   caption-string-helper      Methode von TStringHelper auf einem Ausdruck vom Typ TCaption (Caption, Text von
//                              Steuerelementen). TCaption ist ein eigener String-Typ (type string), der Helfer
//                              gilt nicht (wie E2018). Korrektur: string(...) darum.
//   uses-order-hides-type      Winapi.Windows steht in uses hinter Vcl.Graphics bzw. FMX.Graphics, und die Unit
//                              nennt TBitmap: Gemeint ist dann der Record aus Winapi.Windows (wie E2003 bei
//                              TBitmap.Create). interface- und implementation-uses zählen zusammen, gezählt wird
//                              TBitmap aber nur hinter dem Windows-Eintrag. Korrektur nur,
//                              wenn beide in derselben Liste stehen: Winapi.Windows davor stellen.
//   interface-uses-missing     Ein Name im interface-Teil kommt aus einer Unit, die nur im uses des
//                              implementation-Teils steht (wie E2003). Gemeldet wird nur, was die Namensauflösung
//                              sicher einer solchen Unit zuordnet. Korrektur: Unit ins interface-uses verschieben.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cExitArrayLiteralRuleId = 'exit-array-literal';
  cCaptionStringHelperRuleId = 'caption-string-helper';
  cUsesOrderHidesTypeRuleId = 'uses-order-hides-type';
  cInterfaceUsesMissingRuleId = 'interface-uses-missing';

type
  TExitArrayLiteralRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCaptionStringHelperRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUsesOrderHidesTypeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceUsesMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die vier Regeln in ARegistry an.</summary>
procedure RegisterCompilerTrapRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTrapText = (ExitTitle, ExitMessage, ExitFix, CaptionTitle, CaptionMessage, CaptionFix, OrderTitle, OrderMessage,
    OrderFix, InterfaceTitle, InterfaceMessage, InterfaceFix);

const
  cTexts: array[TTrapText] of TAtlasText = (
    (De: 'Exit mit Array-Literal'; En: 'Exit with array literal'),
    (De: 'Exit(%s): Delphi liest [...] hier als Menge, nicht als %s (wie E2001 bzw. E2010). Erst Result zuweisen, ' +
      'dann Exit.';
     En: 'Exit(%s): Delphi reads [...] here as a set, not as %s (like E2001 or E2010). Assign Result first, then ' +
      'Exit.'),
    (De: 'Result := [...]; Exit; schreiben'; En: 'Write Result := [...]; Exit;'),
    (De: 'String-Helfer auf TCaption'; En: 'String helper on TCaption'),
    (De: '%s ist vom Typ %s, einem eigenen String-Typ: %s aus TStringHelper gilt dafür nicht (wie E2018). ' +
      'string(...) darum setzen.';
     En: '%s is of type %s, a distinct string type: %s from TStringHelper does not apply to it (like E2018). ' +
      'Wrap it in string(...).'),
    (De: 'string(...) darum setzen'; En: 'Wrap in string(...)'),
    (De: 'Unit verdeckt einen Typ'; En: 'Unit hides a type'),
    (De: '%s steht in uses hinter %s: TBitmap meint hier den Record aus %0:s, TBitmap.Create und die Methoden ' +
      'scheitern (wie E2003). %0:s vor %1:s einbinden.';
     En: '%s comes after %s in uses: TBitmap here means the record from %0:s, TBitmap.Create and the methods fail ' +
      '(like E2003). Use %0:s before %1:s.'),
    (De: '%s vor %s stellen'; En: 'Move %s before %s'),
    (De: 'Unit nur im uses des implementation-Teils'; En: 'Unit only in the uses of the implementation section'),
    (De: '%s kommt aus %s, die nur im uses des implementation-Teils steht; im interface-Teil ist der Name ' +
      'unbekannt (wie E2003).';
     En: '%s comes from %s, which is only in the uses of the implementation section; the name is unknown in the ' +
      'interface section (like E2003).'),
    (De: '%s ins uses des interface-Teils verschieben'; En: 'Move %s to the uses of the interface section'));

{$SCOPEDENUMS OFF}

const
  // Methoden und Properties von TStringHelper (System.SysUtils), die auf einem String-Ausdruck stehen.
  cStringHelperMembers: array[0..44] of string = ('Chars', 'CompareTo', 'Contains', 'CountChar', 'DeQuotedString',
    'EndsText', 'EndsWith', 'Equals', 'Format', 'GetHashCode', 'IndexOf', 'IndexOfAny', 'IndexOfAnyUnquoted',
    'Insert', 'IsDelimiter', 'IsEmpty', 'IsNullOrEmpty', 'IsNullOrWhiteSpace', 'LastDelimiter', 'LastIndexOf',
    'LastIndexOfAny', 'Length', 'PadLeft', 'PadRight', 'QuotedString', 'Remove', 'Replace', 'Split', 'StartsWith',
    'Substring', 'ToBoolean', 'ToCharArray', 'ToDouble', 'ToExtended', 'ToInt64', 'ToInteger', 'ToLower',
    'ToLowerInvariant', 'ToSingle', 'ToUpper', 'ToUpperInvariant', 'Trim', 'TrimEnd', 'TrimLeft', 'TrimRight');
  // Eigene String-Typen (type string) der RTL bzw. VCL, für die TStringHelper nicht gilt.
  cDistinctStringTypes: array[0..0] of string = ('TCaption');
  // Bekannte Typen dynamischer Arrays aus System und System.Types.
  cDynamicArrayTypes: array[0..5] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray',
    'TInt64DynArray', 'TDoubleDynArray', 'TBooleanDynArray');
  cWindowsUnits: array[0..1] of string = ('Winapi.Windows', 'Windows');
  cGraphicsUnits: array[0..2] of string = ('Vcl.Graphics', 'FMX.Graphics', 'Graphics');

/// <summary>Name ohne Unit-Vorsatz: System.TArray&lt;T&gt; ergibt TArray&lt;T&gt;.</summary>
function WithoutUnit(const AName: string): string;
var
  mBracket, mDot: Integer;
begin
  mBracket := Pos('<', AName);
  if mBracket = 0 then
  begin
    mBracket := Length(AName) + 1;
  end;
  mDot := LastDelimiter('.', Copy(AName, 1, mBracket - 1));
  Result := Copy(AName, mDot + 1, MaxInt);
end;

/// <summary>Steht vor dem Token AIndex (ohne Kommentare) ein Punkt?</summary>
function AfterDot(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  mBefore := AIndex - 1;
  while (mBefore >= 0) and (ATokens[mBefore].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mBefore);
  end;
  Result := (mBefore >= 0) and ATokens[mBefore].IsSymbol('.');
end;

/// <summary>Liegt APosition zwischen AFrom und ATo?</summary>
function InRange(const APosition, AFrom, ATo: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > AFrom.Line) or (APosition.Line = AFrom.Line) and
    (APosition.Character >= AFrom.Character)) and ((APosition.Line < ATo.Line) or (APosition.Line = ATo.Line) and
    (APosition.Character <= ATo.Character));
end;

{ TExitArrayLiteralRule }

function TExitArrayLiteralRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cExitArrayLiteralRuleId, TRuleSeverity.Error, cTexts[TTrapText.ExitTitle].Text);
end;

/// <summary>Ergebnistyp der Routine ARoutine wie im Quelltext; '' ohne.</summary>
function ResultTypeText(const AText: string; ARoutine: TSyntaxNode): string;
var
  mHeader, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    mChild := mHeader[mIndex];
    if mChild.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType] then
    begin
      Exit(Trim(Copy(AText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset)));
    end;
  end;
end;

/// <summary>Ist ATypeText ein dynamisches Array: TArray&lt;T&gt;, array of T, ein bekannter Typ wie TBytes oder ein
/// Typ der Datei, der so deklariert ist?</summary>
function IsDynamicArrayType(const AContext: TRuleContext; const ATypeText: string): Boolean;
var
  mType: string;
  mFound: Boolean;
begin
  mType := StringReplace(ATypeText, ' ', '', [rfReplaceAll]);
  Result := StartsText('TArray<', WithoutUnit(mType)) or StartsText('arrayof', mType) or
    MatchText(WithoutUnit(mType), cDynamicArrayTypes);
  if Result or not IsValidIdent(mType) then
  begin
    Exit;
  end;
  mFound := False;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mTarget: TSyntaxNode;
      mText: string;
    begin
      Result := not mFound;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, mType) then
      begin
        mTarget := ANode.FindChild(TSyntaxKind.TypeReference);
        if mTarget = nil then
        begin
          mTarget := ANode.FindChild(TSyntaxKind.ArrayType);
        end;
        if mTarget <> nil then
        begin
          mText := StringReplace(Copy(AContext.Text, mTarget.StartOffset + 1, mTarget.EndOffset -
            mTarget.StartOffset), ' ', '', [rfReplaceAll]);
          mFound := StartsText('TArray<', WithoutUnit(mText)) or StartsText('arrayof', mText);
        end;
      end;
    end);
  Result := mFound;
end;

/// <summary>Routine, deren Rumpf ANode enthält; nil in anonymen Methoden.</summary>
function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    Result := Result.Parent;
  end;
  if (Result <> nil) and (Result.Kind = TSyntaxKind.AnonymousMethod) then
  begin
    Result := nil;
  end;
end;

/// <summary>Das Array-Literal von Exit([...]), wenn ANode diese Anweisung ist; sonst nil.</summary>
function ExitSetLiteral(ANode: TSyntaxNode): TSyntaxNode;
var
  mCall: TSyntaxNode;
begin
  Result := nil;
  if (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount <> 1) then
  begin
    Exit;
  end;
  mCall := ANode[0];
  if (mCall.Kind <> TSyntaxKind.Call) or (mCall.ChildCount <> 2) or (mCall[0].Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  if SameText(mCall[0].Name, 'Exit') and (mCall[1].Kind = TSyntaxKind.SetConstructor) and
    (mCall[1].ChildCount > 0) then
  begin
    Result := mCall[1];
  end;
end;

/// <summary>Korrektur der Anweisung AStatement zu Result := ALiteralText; Exit, außerhalb eines Blocks mit
/// begin/end darum.</summary>
function ExitArrayFix(AStatement: TSyntaxNode; const ALiteralText: string): TRuleFix;
var
  mText: string;
begin
  mText := 'Result := ' + ALiteralText + ';' + ' Exit';
  if (AStatement.Parent = nil) or (AStatement.Parent.Kind <> TSyntaxKind.Block) then
  begin
    mText := 'begin ' + mText + '; end';
  end;
  Result := TRuleFix.Create(cTexts[TTrapText.ExitFix].Text, [TTextEdit.Create(TTextRange.Create(AStatement.StartPos,
    AStatement.EndPos), mText)], True);
end;

procedure TExitArrayLiteralRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Exit') then
  begin
    Exit;
  end;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mCall, mLiteral, mRoutine: TSyntaxNode;
      mType, mLiteralText: string;
      mFix: TRuleFix;
    begin
      Result := True;
      mLiteral := ExitSetLiteral(ANode);
      mRoutine := nil;
      if mLiteral <> nil then
      begin
        mRoutine := EnclosingRoutine(ANode);
      end;
      if mRoutine = nil then
      begin
        Exit;
      end;
      mType := ResultTypeText(AContext.Text, mRoutine);
      if (mType = '') or not IsDynamicArrayType(AContext, mType) then
      begin
        Exit;
      end;
      mCall := ANode[0];
      mLiteralText := Copy(AContext.Text, mLiteral.StartOffset + 1, mLiteral.EndOffset - mLiteral.StartOffset);
      mFix := ExitArrayFix(ANode, mLiteralText);
      AReport.Add(TTextRange.Create(mCall.StartPos, mCall.EndPos), cTexts[TTrapText.ExitMessage].Fmt(
        [mLiteralText, mType]), TRuleConfidence.High, [mFix]);
    end);
end;

{ TCaptionStringHelperRule }

function TCaptionStringHelperRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCaptionStringHelperRuleId, TRuleSeverity.Error,
    cTexts[TTrapText.CaptionTitle].Text);
end;

procedure TCaptionStringHelperRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mTypes: TExpressionTypes;
  mOptions: TExpressionTypeOptions;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
  begin
    Exit;
  end;
  mScope := TTypedScope.Create(AContext);
  try
    mOptions := TExpressionTypeOptions.Default;
    mOptions.Conversions := False;
    mOptions.ConstValue := False;
    mTypes := TExpressionTypes.Create(mScope.Resolver, AContext.Tree, mScope.FileName, AContext.Text, AContext.Index,
      mOptions);
    try
      AContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        var
          mReceiver: TSyntaxNode;
          mInfo: TExpressionTypeInfo;
          mType, mText: string;
          mFix: TRuleFix;
        begin
          Result := True;
          if (ANode.Kind <> TSyntaxKind.MemberAccess) or (ANode.ChildCount < 1) or
            not MatchText(ANode.Name, cStringHelperMembers) then
          begin
            Exit;
          end;
          mReceiver := ANode[0];
          mInfo := mTypes.Describe(mReceiver);
          mType := WithoutUnit(mInfo.TypeName);
          if not mInfo.Found or not MatchText(mType, cDistinctStringTypes) then
          begin
            Exit;
          end;
          mText := mScope.Text(mReceiver);
          mFix := TRuleFix.Create(cTexts[TTrapText.CaptionFix].Text, [TTextEdit.Create(TTextRange.Create(
            mReceiver.StartPos, mReceiver.EndPos), 'string(' + mText + ')')], True);
          AReport.Add(TTextRange.Create(mReceiver.StartPos, mReceiver.EndPos), cTexts[TTrapText.CaptionMessage].Fmt(
            [mText, mType, ANode.Name]), TRuleConfidence.High, [mFix]);
        end);
    finally
      mTypes.Free;
    end;
  finally
    mScope.Free;
  end;
end;

{ TUsesOrderHidesTypeRule }

function TUsesOrderHidesTypeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUsesOrderHidesTypeRuleId, TRuleSeverity.Error, cTexts[TTrapText.OrderTitle].Text);
end;

/// <summary>Steht APosition an oder hinter AAfter?</summary>
function NotBefore(const APosition, AAfter: TTextPosition): Boolean;
begin
  Result := (APosition.Line > AAfter.Line) or (APosition.Line = AAfter.Line) and
    (APosition.Character >= AAfter.Character);
end;

/// <summary>Nennt die Datei TBitmap hinter AAfter (dem Windows-Eintrag), außerhalb der uses-Listen und nicht nach
/// einem Punkt? Davor gilt der Eintrag noch nicht: Das uses des implementation-Teils wirkt nicht auf den interface-
/// Teil.</summary>
function NamesBitmap(const ATokens: TArray<TPascalToken>; const AClauses: TArray<TUsesClauseInfo>;
  const AAfter: TTextPosition): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, 'TBitmap') and
      NotBefore(ATokens[mIndex].StartPos, AAfter) and not AfterDot(ATokens, mIndex) and
      not TUsesClauses.InClause(ATokens, AClauses, ATokens[mIndex].Offset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Einträge der uses-Listen in Dateireihenfolge, ohne contains und requires.</summary>
function UsesListEntries(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>;
var
  mRef: TUsesReference;
begin
  Result := nil;
  for mRef in TUsesClauses.References(ATokens) do
  begin
    if mRef.List = TUsesListKind.UsesList then
    begin
      Result := Result + [mRef];
    end;
  end;
end;

/// <summary>Index des ersten Eintrags in AUses, dessen Name in ANames steht; -1 ohne.</summary>
function FirstEntryOf(const AUses: TArray<TUsesReference>; const ANames: array of string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AUses) do
  begin
    if MatchText(AUses[mIndex].Name, ANames) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Korrektur innerhalb derselben Liste: Eintrag AWindows samt Komma davor entfernen und vor AGraphics
/// einsetzen, bei Einträgen je Zeile auf eigener Zeile.</summary>
function MoveBeforeFix(const AText: string; const AUses: TArray<TUsesReference>; AWindows,
  AGraphics: Integer): TRuleFix;
var
  mLines: TLineTable;
  mInsert: string;
  mGraphicsStart: TTextPosition;
begin
  mLines := TLineTable.Build(AText);
  mGraphicsStart := AUses[AGraphics].Range.StartPos;
  mInsert := Copy(AText, mLines.LineStart(mGraphicsStart.Line) + 1, mGraphicsStart.Character);
  if Trim(mInsert) = '' then
  begin
    mInsert := AUses[AWindows].Name + ',' + TTextLines.LineBreakOf(AText) + mInsert;
  end
  else
  begin
    mInsert := AUses[AWindows].Name + ', ';
  end;
  Result := TRuleFix.Create(cTexts[TTrapText.OrderFix].Fmt([AUses[AWindows].Name, AUses[AGraphics].Name]),
    [TTextEdit.Create(TTextRange.Create(mGraphicsStart, mGraphicsStart), mInsert),
    TTextEdit.Create(TTextRange.Create(AUses[AWindows - 1].Range.EndPos, AUses[AWindows].Range.EndPos), '')], True);
end;

procedure TUsesOrderHidesTypeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mUses: TArray<TUsesReference>;
  mWindows, mGraphics: Integer;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'TBitmap') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mUses := UsesListEntries(mTokens);
  mWindows := FirstEntryOf(mUses, cWindowsUnits);
  mGraphics := FirstEntryOf(mUses, cGraphicsUnits);
  if (mWindows < 0) or (mGraphics < 0) or (mWindows < mGraphics) or
    not NamesBitmap(mTokens, TUsesClauses.Clauses(mTokens), mUses[mWindows].Range.EndPos) then
  begin
    Exit;
  end;
  mFixes := nil;
  if (mUses[mWindows].InInterface = mUses[mGraphics].InInterface) and (mWindows > 0) then
  begin
    SetLength(mFixes, 1);
    mFixes[0] := MoveBeforeFix(AContext.Text, mUses, mWindows, mGraphics);
  end;
  AReport.Add(mUses[mWindows].Range, cTexts[TTrapText.OrderMessage].Fmt([mUses[mWindows].Name,
    mUses[mGraphics].Name]), TRuleConfidence.High, mFixes);
end;

{ TInterfaceUsesMissingRule }

function TInterfaceUsesMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInterfaceUsesMissingRuleId, TRuleSeverity.Error,
    cTexts[TTrapText.InterfaceTitle].Text);
end;

type
  /// <summary>Ein Lauf von interface-uses-missing über eine Datei.</summary>
  TInterfaceUsesCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FClauses: TArray<TUsesClauseInfo>;
    FUses: TArray<TUsesReference>;
    FReported: TArray<string>;
    function DeclaringEntry(const AName: string; out AEntry: Integer): Boolean;
    function LastInterfaceEntry: Integer;
    function RemovalRange(AEntry: Integer; const AClause: TUsesClauseInfo): TTextRange;
    function MoveFix(AEntry: Integer): TRuleFix;
    procedure CheckToken(AScope: TTypedScope; AIndex: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TInterfaceUsesCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FClauses := TUsesClauses.Clauses(FTokens);
  FUses := UsesListEntries(FTokens);
end;

/// <summary>Eintrag des implementation-uses, dessen Unit AName auf Unit-Ebene im interface deklariert.</summary>
function TInterfaceUsesCheck.DeclaringEntry(const AName: string; out AEntry: Integer): Boolean;
var
  mIndex: Integer;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mNamespace: string;
  mFound: Boolean;
begin
  for mIndex := 0 to High(FUses) do
  begin
    if FUses[mIndex].InInterface then
    begin
      Continue;
    end;
    mFound := FContext.Index.FindUnit(FUses[mIndex].Name, mUnit);
    for mNamespace in FContext.Namespaces do
    begin
      mFound := mFound or FContext.Index.FindUnit(mNamespace + '.' + FUses[mIndex].Name, mUnit);
    end;
    if not mFound then
    begin
      Continue;
    end;
    for mSymbol in mUnit.Symbols do
    begin
      if mSymbol.InInterface and (mSymbol.Container = '') and not mSymbol.Unavailable and
        SameText(mSymbol.Name, AName) then
      begin
        AEntry := mIndex;
        Exit(True);
      end;
    end;
  end;
  AEntry := -1;
  Result := False;
end;

/// <summary>Index des letzten Eintrags im interface-uses; -1 ohne.</summary>
function TInterfaceUsesCheck.LastInterfaceEntry: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FUses) do
  begin
    if FUses[mIndex].InInterface then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Bereich, dessen Entfernen den Eintrag AEntry aus seiner Liste AClause nimmt: als einziger Eintrag die
/// ganze Liste, sonst samt Komma davor bzw. danach.</summary>
function TInterfaceUsesCheck.RemovalRange(AEntry: Integer; const AClause: TUsesClauseInfo): TTextRange;
begin
  if Length(AClause.Names) = 1 then
  begin
    Result := TTextRange.Create(FTokens[AClause.UsesIndex].StartPos, FTokens[AClause.Semicolon].EndPos);
  end
  else if (AEntry > 0) and not FUses[AEntry - 1].InInterface then
  begin
    Result := TTextRange.Create(FUses[AEntry - 1].Range.EndPos, FUses[AEntry].Range.EndPos);
  end
  else
  begin
    Result := TTextRange.Create(FUses[AEntry].Range.StartPos, FUses[AEntry + 1].Range.StartPos);
  end;
end;

/// <summary>Verschiebt den Eintrag AEntry des implementation-uses ins interface-uses; ohne Edits, wenn es kein
/// interface-uses gibt.</summary>
function TInterfaceUsesCheck.MoveFix(AEntry: Integer): TRuleFix;
var
  mClause: TUsesClauseInfo;
  mInterface: Integer;
  mEdits: TArray<TTextEdit>;
begin
  mEdits := nil;
  mInterface := LastInterfaceEntry;
  if mInterface >= 0 then
  begin
    mEdits := [TTextEdit.Create(TTextRange.Create(FUses[mInterface].Range.EndPos, FUses[mInterface].Range.EndPos),
      ', ' + FUses[AEntry].Name)];
    for mClause in FClauses do
    begin
      if not mClause.InInterface and InRange(FUses[AEntry].Range.StartPos, FTokens[mClause.UsesIndex].StartPos,
        FTokens[mClause.Semicolon].EndPos) then
      begin
        mEdits := mEdits + [TTextEdit.Create(RemovalRange(AEntry, mClause), '')];
        Break;
      end;
    end;
  end;
  Result := TRuleFix.Create(cTexts[TTrapText.InterfaceFix].Fmt([FUses[AEntry].Name]), mEdits, False);
end;

procedure TInterfaceUsesCheck.CheckToken(AScope: TTypedScope; AIndex: Integer);
var
  mSymbol: TResolvedSymbol;
  mEntry: Integer;
  mFixes: TArray<TRuleFix>;
  mFix: TRuleFix;
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  if (mToken.Kind <> TPascalTokenKind.Identifier) or AfterDot(FTokens, AIndex) or
    TUsesClauses.InClause(FTokens, FClauses, mToken.Offset) then
  begin
    Exit;
  end;
  mSymbol := AScope.Resolver.Resolve(FContext.Tree, AScope.FileName, mToken.StartPos);
  // Die Namensauflösung sieht im interface-Teil nur dessen uses: Ein Name, den sie dort nicht findet, den aber
  // eine Unit des implementation-uses im interface deklariert, fehlt im interface-uses.
  if (mSymbol.Kind <> TResolvedKind.None) or not DeclaringEntry(mToken.Text, mEntry) or
    MatchText(FUses[mEntry].Name, FReported) then
  begin
    Exit;
  end;
  FReported := FReported + [FUses[mEntry].Name];
  mFixes := nil;
  mFix := MoveFix(mEntry);
  if Length(mFix.Edits) > 0 then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), cTexts[TTrapText.InterfaceMessage].Fmt(
    [mToken.Text, FUses[mEntry].Name]), TRuleConfidence.High, mFixes);
end;

procedure TInterfaceUsesCheck.Run;
var
  mScope: TTypedScope;
  mSection, mIndex: Integer;
  mHasImplementationUses: Boolean;
  mRef: TUsesReference;
  mTypes: TArray<TSyntaxNode>;
  mType: TSyntaxNode;
begin
  mHasImplementationUses := False;
  for mRef in FUses do
  begin
    mHasImplementationUses := mHasImplementationUses or not mRef.InInterface;
  end;
  if not mHasImplementationUses then
  begin
    Exit;
  end;
  // Nur Typangaben des interface-Teils: Namen, die dort deklariert werden, löst der Resolver nicht auf.
  mTypes := nil;
  for mSection := 0 to FContext.Tree.Root.ChildCount - 1 do
  begin
    if FContext.Tree.Root[mSection].Kind = TSyntaxKind.InterfaceSection then
    begin
      FContext.Tree.Root[mSection].Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := ANode.Kind <> TSyntaxKind.TypeReference;
          if not Result then
          begin
            mTypes := mTypes + [ANode];
          end;
        end);
    end;
  end;
  if mTypes = nil then
  begin
    Exit;
  end;
  mScope := TTypedScope.Create(FContext);
  try
    for mType in mTypes do
    begin
      mIndex := TokenFrom(FTokens, mType.StartOffset);
      while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < mType.EndOffset) do
      begin
        CheckToken(mScope, mIndex);
        Inc(mIndex);
      end;
    end;
  finally
    mScope.Free;
  end;
end;

procedure TInterfaceUsesMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TInterfaceUsesCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) or
    (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) then
  begin
    Exit;
  end;
  mCheck := TInterfaceUsesCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterCompilerTrapRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TExitArrayLiteralRule.Create);
  ARegistry.Register(TCaptionStringHelperRule.Create);
  ARegistry.Register(TUsesOrderHidesTypeRule.Create);
  ARegistry.Register(TInterfaceUsesMissingRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.CompilerTraps', cTexts);

end.
