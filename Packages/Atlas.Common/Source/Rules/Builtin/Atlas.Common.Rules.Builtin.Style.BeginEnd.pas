unit Atlas.Common.Rules.Builtin.Style.BeginEnd;

// Stilregel missing-begin-end (#1025), registriert mit den übrigen Stilregeln (RegisterStyleRules):
//   Rumpf von if, else, for, while, with (Option statements, auch case-Zweige) ohne begin … end; else if, repeat,
//   case, try und asm sind schon Blöcke. Korrektur für die Stelle, die Methode oder die Datei, ; vor else richtig.
//   Ist die Regel an, schweigt redundant-begin-end (Katalog overriddenBy, Rules.Engine).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TMissingBeginEndRule = class(TInterfacedObject, IRule)
  public const
    cDefaultStatements: array[0..4] of string = ('if', 'else', 'for', 'while', 'with');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.Formatter.Layout,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Style.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStyleBeginEndText = (Title, SetBeginEnd, InMethod, InFile, CaseBranch, Without);

const
  cTexts: array[TStyleBeginEndText] of TAtlasText = (
    (De: 'Bedingung oder Schleife ohne begin … end'; En: 'Condition or loop without begin … end'),
    (De: 'begin … end setzen'; En: 'Add begin … end'),
    (De: 'begin … end in der ganzen Methode setzen (%d Stellen)';
     En: 'Add begin … end in the whole method (%d places)'),
    (De: 'begin … end in der ganzen Datei setzen (%d Stellen)'; En: 'Add begin … end in the whole file (%d places)'),
    (De: 'case-Zweig ohne begin … end'; En: 'case branch without begin … end'),
    (De: '%s ohne begin … end'; En: '%s without begin … end'));

{$SCOPEDENUMS OFF}

{ TMissingBeginEndRule }

function TMissingBeginEndRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-begin-end', TRuleSeverity.Hint,
    cTexts[TStyleBeginEndText.Title].Text);
end;

type
  /// <summary>Ein Rumpf ohne begin … end (#1025): gemeldetes Schlüsselwort, Token vor dem Rumpf (then, do,
  /// else, :) und erstes und letztes Token des Rumpfs (Indizes in die Tokens des Baums).</summary>
  TBodySite = record
    Name: string;
    Keyword: Integer;
    Lead: Integer;
    First: Integer;
    Last: Integer;
    /// <summary>Token, dessen Einrückung begin und end bekommen; bei else, das nicht am Zeilenanfang steht,
    /// das zugehörige if.</summary>
    Anchor: Integer;
    /// <summary>Nächste umschließende Routine (Reichweite „ganze Methode“); nil außerhalb.</summary>
    Routine: TSyntaxNode;
  end;

  /// <summary>Sucht die Rümpfe ohne begin … end und baut die Korrekturen dafür (#1025).</summary>
  TBeginEndSites = class
  private
    FText: string;
    FTokens: TTokens;
    FLines: TArray<string>;
    FLineBreak: string;
    FIndentUnit: string;
    /// <summary>format.elsePlacement: SameLine setzt else hinter das neue end.</summary>
    FElsePlacement: TBlockPlacement;
    FPaths: TArray<string>;
    FStatements: TArray<string>;
    FAllowSingleLineExit: Boolean;
    FAllowSameLine: Boolean;
    FSites: TArray<TBodySite>;
    function LastTokenOf(ANode: TSyntaxNode): Integer;
    function Checked(const AName: string): Boolean;
    function StartsLine(AToken: Integer): Boolean;
    function Conditional(AFirst, ALast: Integer): Boolean;
    function Allowed(ALead, AFirst, ALast: Integer): Boolean;
    procedure Add(const AName: string; AKeyword, ALead, AAnchor: Integer; ABody, ARoutine: TSyntaxNode);
    procedure SortSites;
    procedure Visit(ANode, ARoutine: TSyntaxNode);
    procedure VisitNode(ANode, ARoutine: TSyntaxNode);
    procedure VisitIf(ANode, ARoutine: TSyntaxNode; AKeyword: Integer);
    procedure VisitElse(ANode, ARoutine, ABody: TSyntaxNode; AKeyword: Integer);
    procedure VisitBody(ANode, ARoutine: TSyntaxNode; AKeyword: Integer; const AName: string);
    function Indent(ASite: Integer; const AChosen: TArray<Boolean>): string;
    function BeginEdit(ASite: Integer; const AChosen: TArray<Boolean>): TRuleEdit;
    function EndEdit(ASite: Integer; const AChosen: TArray<Boolean>; const ADone: TArray<Boolean>): TRuleEdit;
    procedure JoinElse(ASite, AOuter: Integer; const AChosen: TArray<Boolean>; var AText: string;
      var ARange: TTextRange);
  public
    constructor Create(const AContext: TRuleContext);
    property Sites: TArray<TBodySite> read FSites;
    /// <summary>Edits, die um die Rümpfe ASites begin … end setzen; ein Undo-Schritt für den Client.</summary>
    function Edits(const ASites: TArray<Integer>): TArray<TRuleEdit>;
  end;

  /// <summary>Korrektur „ganze Methode“ je Stelle, einmal je Routine gebaut, und die Zahl der Stellen der
  /// Routine.</summary>
  TMethodFixes = record
    Edits: TArray<TArray<TRuleEdit>>;
    Counts: TArray<Integer>;
  end;

constructor TBeginEndSites.Create(const AContext: TRuleContext);
var
  mStyle: TFormatStyle;
  mIndex: Integer;
begin
  inherited Create;
  FText := AContext.Text;
  FTokens := AContext.Tree.Tokens;
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  mStyle := AContext.Formatting;
  if mStyle.IndentSize <= 0 then
  begin
    mStyle.IndentSize := 2;
  end;
  FIndentUnit := TFormatLayout.IndentUnit(mStyle);
  FElsePlacement := mStyle.ElsePlacement;
  if mStyle.EndOfLine <> '' then
  begin
    FLineBreak := mStyle.EndOfLine;
  end;
  FPaths := TConditionalBranches.Paths(FTokens);
  SetLength(FStatements, Length(TMissingBeginEndRule.cDefaultStatements));
  for mIndex := 0 to High(TMissingBeginEndRule.cDefaultStatements) do
  begin
    FStatements[mIndex] := TMissingBeginEndRule.cDefaultStatements[mIndex];
  end;
  FStatements := TRuleOptions.Strings(AContext.Options, 'statements', FStatements);
  FAllowSingleLineExit := TRuleOptions.Bool(AContext.Options, 'allowSingleLineExit', False);
  FAllowSameLine := TRuleOptions.Bool(AContext.Options, 'allowSameLine', False);
  FSites := nil;
  Visit(AContext.Tree.Root, nil);
  SortSites;
end;

procedure TBeginEndSites.SortSites;
var
  mIndex, mOther: Integer;
  mSite: TBodySite;
begin
  // Nach dem Schlüsselwort ordnen (else steht hinter den Stellen im then-Zweig); fast schon sortiert.
  for mIndex := 1 to High(FSites) do
  begin
    mSite := FSites[mIndex];
    mOther := mIndex - 1;
    while (mOther >= 0) and (FSites[mOther].Keyword > mSite.Keyword) do
    begin
      FSites[mOther + 1] := FSites[mOther];
      Dec(mOther);
    end;
    FSites[mOther + 1] := mSite;
  end;
end;

function TBeginEndSites.LastTokenOf(ANode: TSyntaxNode): Integer;
begin
  Result := PreviousCode(FTokens, TokenFrom(FTokens, ANode.EndOffset));
end;

function TBeginEndSites.Checked(const AName: string): Boolean;
begin
  Result := IndexText(AName, FStatements) >= 0;
end;

function TBeginEndSites.StartsLine(AToken: Integer): Boolean;
var
  mLine: Integer;
begin
  mLine := FTokens[AToken].StartPos.Line;
  Result := (mLine < Length(FLines)) and (Trim(Copy(FLines[mLine], 1, FTokens[AToken].StartPos.Character)) = '');
end;

function TBeginEndSites.Conditional(AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
  mPath: string;
begin
  // Rumpf mit {$IFDEF}: Der Baum enthält beide Zweige; ohne sichere Lage keine Meldung.
  Result := False;
  if FPaths = nil then
  begin
    Exit;
  end;
  mPath := TConditionalBranches.PathAt(FPaths, AFirst);
  for mIndex := AFirst to Min(ALast, High(FTokens)) do
  begin
    if TConditionalBranches.PathAt(FPaths, mIndex) <> mPath then
    begin
      Exit(True);
    end;
  end;
end;

function TBeginEndSites.Allowed(ALead, AFirst, ALast: Integer): Boolean;
var
  mSameLine: Boolean;
begin
  mSameLine := FTokens[ALast].EndPos.Line = FTokens[ALead].StartPos.Line;
  Result := mSameLine and (FAllowSameLine or (FAllowSingleLineExit and
    MatchText(FTokens[AFirst].Text, ['Exit', 'Continue', 'Break', 'raise'])));
end;

procedure TBeginEndSites.Add(const AName: string; AKeyword, ALead, AAnchor: Integer; ABody,
  ARoutine: TSyntaxNode);
var
  mSite: TBodySite;
begin
  // Schon Blöcke: begin … end, asm … end, try … end, repeat … until, case … end.
  if ABody.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.TryStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.CaseStatement, TSyntaxKind.EmptyStatement, TSyntaxKind.Error] then
  begin
    Exit;
  end;
  if not Checked(AName) then
  begin
    Exit;
  end;
  mSite := Default(TBodySite);
  mSite.Name := AName;
  mSite.Keyword := AKeyword;
  mSite.Lead := ALead;
  mSite.Anchor := AAnchor;
  mSite.Routine := ARoutine;
  mSite.First := TokenFrom(FTokens, ABody.StartOffset);
  mSite.Last := LastTokenOf(ABody);
  if (mSite.First > High(FTokens)) or (mSite.Last < mSite.First) or
    (FTokens[mSite.First].Offset <> ABody.StartOffset) then
  begin
    Exit;
  end;
  if Conditional(ALead, NextCode(FTokens, mSite.Last + 1)) or Allowed(ALead, mSite.First, mSite.Last) then
  begin
    Exit;
  end;
  FSites := FSites + [mSite];
end;

procedure TBeginEndSites.Visit(ANode, ARoutine: TSyntaxNode);
var
  mStack: TArray<TSyntaxNode>;
  mRoutines: TArray<TSyntaxNode>;
  mCount, mIndex: Integer;
  mNode, mRoutine: TSyntaxNode;
begin
  // Ohne Rekursion: Ausdrücke können sehr tief sein (#1094).
  SetLength(mStack, 64);
  SetLength(mRoutines, 64);
  mStack[0] := ANode;
  mRoutines[0] := ARoutine;
  mCount := 1;
  while mCount > 0 do
  begin
    Dec(mCount);
    mNode := mStack[mCount];
    mRoutine := mRoutines[mCount];
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      mRoutine := mNode;
    end;
    if mCount + mNode.ChildCount > Length(mStack) then
    begin
      SetLength(mStack, 2 * (mCount + mNode.ChildCount));
      SetLength(mRoutines, Length(mStack));
    end;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      mStack[mCount] := mNode[mIndex];
      mRoutines[mCount] := mRoutine;
      Inc(mCount);
    end;
    VisitNode(mNode, mRoutine);
  end;
end;

procedure TBeginEndSites.VisitNode(ANode, ARoutine: TSyntaxNode);
var
  mKeyword: Integer;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mKeyword := TokenFrom(FTokens, ANode.StartOffset);
  if mKeyword > High(FTokens) then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.IfStatement:
      VisitIf(ANode, ARoutine, mKeyword);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
      VisitBody(ANode, ARoutine, mKeyword, LowerCase(FTokens[mKeyword].Text));
    TSyntaxKind.CaseItem:
      VisitBody(ANode, ARoutine, mKeyword, 'case');
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TBeginEndSites.VisitIf(ANode, ARoutine: TSyntaxNode; AKeyword: Integer);
var
  mLead, mNext: Integer;
  mBody: TSyntaxNode;
begin
  mLead := NextCode(FTokens, LastTokenOf(ANode[0]) + 1);
  if (mLead > High(FTokens)) or not FTokens[mLead].IsKeyword('then') then
  begin
    Exit;
  end;
  mNext := NextCode(FTokens, mLead + 1);
  mBody := nil;
  if (ANode.ChildCount > 1) and (mNext <= High(FTokens)) and (ANode[1].StartOffset = FTokens[mNext].Offset) then
  begin
    mBody := ANode[1];
    Add('if', AKeyword, mLead, AKeyword, mBody, ARoutine);
  end;
  VisitElse(ANode, ARoutine, mBody, AKeyword);
end;

procedure TBeginEndSites.VisitElse(ANode, ARoutine, ABody: TSyntaxNode; AKeyword: Integer);
var
  mLast: TSyntaxNode;
  mElseToken: Integer;
begin
  // else: das letzte Kind, wenn davor else steht; else if braucht keinen eigenen Block.
  mLast := ANode[ANode.ChildCount - 1];
  if (mLast = ANode[0]) or (mLast = ABody) or (mLast.Kind = TSyntaxKind.IfStatement) then
  begin
    Exit;
  end;
  mElseToken := PreviousCode(FTokens, TokenFrom(FTokens, mLast.StartOffset));
  if (mElseToken < 0) or not FTokens[mElseToken].IsKeyword('else') then
  begin
    Exit;
  end;
  if StartsLine(mElseToken) then
  begin
    Add('else', mElseToken, mElseToken, mElseToken, mLast, ARoutine);
  end
  else
  begin
    Add('else', mElseToken, mElseToken, AKeyword, mLast, ARoutine);
  end;
end;

procedure TBeginEndSites.VisitBody(ANode, ARoutine: TSyntaxNode; AKeyword: Integer; const AName: string);
var
  mLast: TSyntaxNode;
  mLead: Integer;
  mFits: Boolean;
begin
  // Rumpf hinter do (Schleifen, with) bzw. hinter : (case-Zweig).
  mLast := ANode[ANode.ChildCount - 1];
  mLead := PreviousCode(FTokens, TokenFrom(FTokens, mLast.StartOffset));
  if mLead < 0 then
  begin
    Exit;
  end;
  if AName = 'case' then
  begin
    mFits := FTokens[mLead].IsSymbol(':');
  end
  else
  begin
    mFits := FTokens[mLead].IsKeyword('do');
  end;
  if mFits then
  begin
    Add(AName, AKeyword, mLead, AKeyword, mLast, ARoutine);
  end;
end;

function TBeginEndSites.Indent(ASite: Integer; const AChosen: TArray<Boolean>): string;
var
  mAnchor, mIndex: Integer;
begin
  mAnchor := FSites[ASite].Anchor;
  if StartsLine(mAnchor) then
  begin
    Exit(TTextLines.IndentOf(FLines[FTokens[mAnchor].StartPos.Line]));
  end;
  // Steht die Anweisung hinter then/do in derselben Zeile, kommt sie mit der Korrektur in eine eigene Zeile.
  for mIndex := 0 to High(FSites) do
  begin
    if AChosen[mIndex] and (FSites[mIndex].First = mAnchor) and
      (FTokens[FSites[mIndex].Lead].StartPos.Line = FTokens[mAnchor].StartPos.Line) then
    begin
      Exit(Indent(mIndex, AChosen) + FIndentUnit);
    end;
  end;
  Result := TTextLines.IndentOf(FLines[FTokens[mAnchor].StartPos.Line]);
end;

function TBeginEndSites.BeginEdit(ASite: Integer; const AChosen: TArray<Boolean>): TRuleEdit;
var
  mOwn, mGap, mText: string;
  mLeadEnd: Integer;
begin
  // Vorn: begin in eigener Zeile auf der Einrückung der Anweisung; ein Rumpf aus derselben Zeile rückt ein.
  mOwn := Indent(ASite, AChosen);
  mLeadEnd := FTokens[FSites[ASite].Lead].Offset + Length(FTokens[FSites[ASite].Lead].Text);
  mGap := Copy(FText, mLeadEnd + 1, FTokens[FSites[ASite].First].Offset - mLeadEnd);
  if Pos(#10, mGap) > 0 then
  begin
    mText := FLineBreak + mOwn + 'begin' + mGap;
  end
  else
  begin
    mText := FLineBreak + mOwn + 'begin' + FLineBreak + mOwn + FIndentUnit + Trim(mGap);
    if Trim(mGap) <> '' then
    begin
      mText := mText + ' ';
    end;
  end;
  Result := TRuleEdit.Create(TTextRange.Create(FTokens[FSites[ASite].Lead].EndPos,
    FTokens[FSites[ASite].First].StartPos), mText);
end;

function TBeginEndSites.EndEdit(ASite: Integer; const AChosen: TArray<Boolean>;
  const ADone: TArray<Boolean>): TRuleEdit;
var
  mText: string;
  mOuter, mIndex: Integer;
  mRange: TTextRange;
begin
  // Hinten: alle Rümpfe, die am selben Token enden, innen zuerst. Das Semikolon steht im Block, vor else
  // also keins (E2153). ADone ist ein dynamisches Array: die erledigten Stellen stehen danach beim Aufrufer.
  mText := '';
  mOuter := -1;
  // Die Stellen sind nach Schlüsselwort geordnet: von hinten ist die innere zuerst dran.
  for mIndex := High(FSites) downto 0 do
  begin
    if not AChosen[mIndex] or (FSites[mIndex].Last <> FSites[ASite].Last) then
    begin
      Continue;
    end;
    ADone[mIndex] := True;
    mOuter := mIndex;
    mText := mText + ';' + FLineBreak + Indent(mIndex, AChosen) + 'end';
  end;
  mRange := TTextRange.Create(FTokens[FSites[ASite].Last].EndPos, FTokens[FSites[ASite].Last].EndPos);
  JoinElse(ASite, mOuter, AChosen, mText, mRange);
  Result := TRuleEdit.Create(mRange, mText);
end;

procedure TBeginEndSites.JoinElse(ASite, AOuter: Integer; const AChosen: TArray<Boolean>; var AText: string;
  var ARange: TTextRange);
var
  mNext, mLeadEnd: Integer;
  mGap: string;
begin
  mNext := NextCode(FTokens, FSites[ASite].Last + 1);
  if (mNext > High(FTokens)) or not FTokens[mNext].IsKeyword('else') then
  begin
    Exit;
  end;
  mLeadEnd := FTokens[FSites[ASite].Last].Offset + Length(FTokens[FSites[ASite].Last].Text);
  mGap := Copy(FText, mLeadEnd + 1, FTokens[mNext].Offset - mLeadEnd);
  // format.elsePlacement sameLine: end else. Nur ohne Kommentar dazwischen, der ginge sonst verloren.
  if (FElsePlacement = TBlockPlacement.SameLine) and (Trim(mGap) = '') then
  begin
    AText := AText + ' ';
    ARange.EndPos := FTokens[mNext].StartPos;
  end
  else if FTokens[mNext].StartPos.Line = FTokens[FSites[ASite].Last].EndPos.Line then
  begin
    AText := AText + FLineBreak + Indent(AOuter, AChosen);
    ARange.EndPos := FTokens[mNext].StartPos;
  end;
end;

function TBeginEndSites.Edits(const ASites: TArray<Integer>): TArray<TRuleEdit>;
var
  mChosen, mDone: TArray<Boolean>;
  mSite, mCount: Integer;
begin
  // Höchstens zwei Edits je Stelle: vorn begin, hinten end (gleiche Enden zusammengefasst).
  SetLength(Result, 2 * Length(ASites));
  mCount := 0;
  SetLength(mChosen, Length(FSites));
  SetLength(mDone, Length(FSites));
  for mSite in ASites do
  begin
    mChosen[mSite] := True;
  end;
  for mSite in ASites do
  begin
    Result[mCount] := BeginEdit(mSite, mChosen);
    Inc(mCount);
  end;
  for mSite in ASites do
  begin
    if mDone[mSite] then
    begin
      Continue;
    end;
    Result[mCount] := EndEdit(mSite, mChosen, mDone);
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

/// <summary>Indizes der Stellen ab AFirst, die in derselben Routine liegen wie AFirst.</summary>
function SitesOfRoutine(const ASites: TArray<TBodySite>; AFirst: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := AFirst to High(ASites) do
  begin
    if ASites[mIndex].Routine = ASites[AFirst].Routine then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Korrekturen „ganze Methode“ zu allen Stellen von AFinder.</summary>
function MethodFixes(AFinder: TBeginEndSites): TMethodFixes;
var
  mSites: TArray<TBodySite>;
  mIndex, mOther: Integer;
  mMethod: TArray<Integer>;
begin
  mSites := AFinder.Sites;
  SetLength(Result.Edits, Length(mSites));
  SetLength(Result.Counts, Length(mSites));
  // Die Stellen einer Routine folgen aufeinander (nach Schlüsselwort geordnet), außer bei verschachtelten
  // Routinen; deshalb über alle Stellen sammeln.
  for mIndex := 0 to High(mSites) do
  begin
    if (mSites[mIndex].Routine = nil) or (Result.Counts[mIndex] > 0) then
    begin
      Continue;
    end;
    mMethod := SitesOfRoutine(mSites, mIndex);
    if Length(mMethod) > 1 then
    begin
      Result.Edits[mIndex] := AFinder.Edits(mMethod);
    end;
    for mOther in mMethod do
    begin
      Result.Edits[mOther] := Result.Edits[mIndex];
      Result.Counts[mOther] := Length(mMethod);
    end;
  end;
end;

/// <summary>Alle Stellen 0..ACount-1.</summary>
function AllSites(ACount: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := mIndex;
  end;
end;

/// <summary>Korrekturen der Stelle ASite: die Stelle, die ganze Methode und die ganze Datei. AFileEdits baut die
/// Korrektur der ganzen Datei beim ersten Bedarf.</summary>
function SiteFixes(AFinder: TBeginEndSites; ASite: Integer; const AMethods: TMethodFixes;
  var AFileEdits: TArray<TRuleEdit>): TArray<TRuleFix>;
var
  mSiteCount: Integer;
begin
  Result := [TRuleFix.Create(cTexts[TStyleBeginEndText.SetBeginEnd].Text, AFinder.Edits([ASite]), True)];
  if AMethods.Counts[ASite] > 1 then
  begin
    Result := Result + [TRuleFix.Create(cTexts[TStyleBeginEndText.InMethod].Fmt(
      [AMethods.Counts[ASite]]), AMethods.Edits[ASite])];
  end;
  mSiteCount := Length(AFinder.Sites);
  if mSiteCount <= Max(1, AMethods.Counts[ASite]) then
  begin
    Exit;
  end;
  if AFileEdits = nil then
  begin
    AFileEdits := AFinder.Edits(AllSites(mSiteCount));
  end;
  Result := Result + [TRuleFix.Create(cTexts[TStyleBeginEndText.InFile].Fmt([mSiteCount]),
    AFileEdits)];
end;

function SiteMessage(const AName: string): string;
begin
  if AName = 'case' then
  begin
    Result := cTexts[TStyleBeginEndText.CaseBranch].Text;
  end
  else
  begin
    Result := cTexts[TStyleBeginEndText.Without].Fmt([AName]);
  end;
end;

procedure TMissingBeginEndRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mFinder: TBeginEndSites;
  mSites: TArray<TBodySite>;
  mIndex: Integer;
  mMethods: TMethodFixes;
  mFileEdits: TArray<TRuleEdit>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFinder := TBeginEndSites.Create(AContext);
  try
    mSites := mFinder.Sites;
    mMethods := MethodFixes(mFinder);
    mFileEdits := nil;
    for mIndex := 0 to High(mSites) do
    begin
      AReport.Add(RangeOf(AContext.Tree.Tokens, mSites[mIndex].Keyword, mSites[mIndex].Keyword),
        SiteMessage(mSites[mIndex].Name), TRuleConfidence.High, SiteFixes(mFinder, mIndex, mMethods, mFileEdits));
    end;
  finally
    mFinder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.BeginEnd', cTexts);

end.
