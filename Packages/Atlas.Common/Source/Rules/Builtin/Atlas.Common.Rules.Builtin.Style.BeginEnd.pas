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
    DefaultStatements: array[0..4] of string = ('if', 'else', 'for', 'while', 'with');
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
    function TokenAtOffset(AOffset: Integer): Integer;
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
  Style: TFormatStyle;
  Index: Integer;
begin
  inherited Create;
  FText := AContext.Text;
  FTokens := AContext.Tree.Tokens;
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  Style := AContext.Formatting;
  if Style.IndentSize <= 0 then
  begin
    Style.IndentSize := 2;
  end;
  FIndentUnit := TFormatLayout.IndentUnit(Style);
  FElsePlacement := Style.ElsePlacement;
  if Style.EndOfLine <> '' then
  begin
    FLineBreak := Style.EndOfLine;
  end;
  FPaths := TConditionalBranches.Paths(FTokens);
  SetLength(FStatements, Length(TMissingBeginEndRule.DefaultStatements));
  for Index := 0 to High(TMissingBeginEndRule.DefaultStatements) do
  begin
    FStatements[Index] := TMissingBeginEndRule.DefaultStatements[Index];
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
  Index, Other: Integer;
  Site: TBodySite;
begin
  // Nach dem Schlüsselwort ordnen (else steht hinter den Stellen im then-Zweig); fast schon sortiert.
  for Index := 1 to High(FSites) do
  begin
    Site := FSites[Index];
    Other := Index - 1;
    while (Other >= 0) and (FSites[Other].Keyword > Site.Keyword) do
    begin
      FSites[Other + 1] := FSites[Other];
      Dec(Other);
    end;
    FSites[Other + 1] := Site;
  end;
end;

function TBeginEndSites.TokenAtOffset(AOffset: Integer): Integer;
var
  Upper, Middle: Integer;
begin
  // Erstes Token ab AOffset (die Tokens sind nach Offset sortiert).
  Result := 0;
  Upper := Length(FTokens);
  while Result < Upper do
  begin
    Middle := (Result + Upper) div 2;
    if FTokens[Middle].Offset < AOffset then
    begin
      Result := Middle + 1;
    end
    else
    begin
      Upper := Middle;
    end;
  end;
end;

function TBeginEndSites.LastTokenOf(ANode: TSyntaxNode): Integer;
begin
  Result := PreviousCode(FTokens, TokenAtOffset(ANode.EndOffset));
end;

function TBeginEndSites.Checked(const AName: string): Boolean;
begin
  Result := IndexText(AName, FStatements) >= 0;
end;

function TBeginEndSites.StartsLine(AToken: Integer): Boolean;
var
  Line: Integer;
begin
  Line := FTokens[AToken].StartPos.Line;
  Result := (Line < Length(FLines)) and (Trim(Copy(FLines[Line], 1, FTokens[AToken].StartPos.Character)) = '');
end;

function TBeginEndSites.Conditional(AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
  Path: string;
begin
  // Rumpf mit {$IFDEF}: Der Baum enthält beide Zweige; ohne sichere Lage keine Meldung.
  Result := False;
  if FPaths = nil then
  begin
    Exit;
  end;
  Path := TConditionalBranches.PathAt(FPaths, AFirst);
  for Index := AFirst to Min(ALast, High(FTokens)) do
  begin
    if TConditionalBranches.PathAt(FPaths, Index) <> Path then
    begin
      Exit(True);
    end;
  end;
end;

function TBeginEndSites.Allowed(ALead, AFirst, ALast: Integer): Boolean;
var
  SameLine: Boolean;
begin
  SameLine := FTokens[ALast].EndPos.Line = FTokens[ALead].StartPos.Line;
  Result := SameLine and (FAllowSameLine or (FAllowSingleLineExit and
    MatchText(FTokens[AFirst].Text, ['Exit', 'Continue', 'Break', 'raise'])));
end;

procedure TBeginEndSites.Add(const AName: string; AKeyword, ALead, AAnchor: Integer; ABody,
  ARoutine: TSyntaxNode);
var
  Site: TBodySite;
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
  Site := Default(TBodySite);
  Site.Name := AName;
  Site.Keyword := AKeyword;
  Site.Lead := ALead;
  Site.Anchor := AAnchor;
  Site.Routine := ARoutine;
  Site.First := TokenAtOffset(ABody.StartOffset);
  Site.Last := LastTokenOf(ABody);
  if (Site.First > High(FTokens)) or (Site.Last < Site.First) or (FTokens[Site.First].Offset <> ABody.StartOffset) then
  begin
    Exit;
  end;
  if Conditional(ALead, NextCode(FTokens, Site.Last + 1)) or Allowed(ALead, Site.First, Site.Last) then
  begin
    Exit;
  end;
  FSites := FSites + [Site];
end;

procedure TBeginEndSites.Visit(ANode, ARoutine: TSyntaxNode);
var
  Stack: TArray<TSyntaxNode>;
  Routines: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node, Routine: TSyntaxNode;
begin
  // Ohne Rekursion: Ausdrücke können sehr tief sein (#1094).
  SetLength(Stack, 64);
  SetLength(Routines, 64);
  Stack[0] := ANode;
  Routines[0] := ARoutine;
  Count := 1;
  while Count > 0 do
  begin
    Dec(Count);
    Node := Stack[Count];
    Routine := Routines[Count];
    if Node.Kind = TSyntaxKind.RoutineDecl then
    begin
      Routine := Node;
    end;
    if Count + Node.ChildCount > Length(Stack) then
    begin
      SetLength(Stack, 2 * (Count + Node.ChildCount));
      SetLength(Routines, Length(Stack));
    end;
    for Index := Node.ChildCount - 1 downto 0 do
    begin
      Stack[Count] := Node[Index];
      Routines[Count] := Routine;
      Inc(Count);
    end;
    VisitNode(Node, Routine);
  end;
end;

procedure TBeginEndSites.VisitNode(ANode, ARoutine: TSyntaxNode);
var
  Keyword: Integer;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  Keyword := TokenAtOffset(ANode.StartOffset);
  if Keyword > High(FTokens) then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.IfStatement:
      VisitIf(ANode, ARoutine, Keyword);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
      VisitBody(ANode, ARoutine, Keyword, LowerCase(FTokens[Keyword].Text));
    TSyntaxKind.CaseItem:
      VisitBody(ANode, ARoutine, Keyword, 'case');
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TBeginEndSites.VisitIf(ANode, ARoutine: TSyntaxNode; AKeyword: Integer);
var
  Lead, Next: Integer;
  Body: TSyntaxNode;
begin
  Lead := NextCode(FTokens, LastTokenOf(ANode[0]) + 1);
  if (Lead > High(FTokens)) or not FTokens[Lead].IsKeyword('then') then
  begin
    Exit;
  end;
  Next := NextCode(FTokens, Lead + 1);
  Body := nil;
  if (ANode.ChildCount > 1) and (Next <= High(FTokens)) and (ANode[1].StartOffset = FTokens[Next].Offset) then
  begin
    Body := ANode[1];
    Add('if', AKeyword, Lead, AKeyword, Body, ARoutine);
  end;
  VisitElse(ANode, ARoutine, Body, AKeyword);
end;

procedure TBeginEndSites.VisitElse(ANode, ARoutine, ABody: TSyntaxNode; AKeyword: Integer);
var
  Last: TSyntaxNode;
  ElseToken: Integer;
begin
  // else: das letzte Kind, wenn davor else steht; else if braucht keinen eigenen Block.
  Last := ANode[ANode.ChildCount - 1];
  if (Last = ANode[0]) or (Last = ABody) or (Last.Kind = TSyntaxKind.IfStatement) then
  begin
    Exit;
  end;
  ElseToken := PreviousCode(FTokens, TokenAtOffset(Last.StartOffset));
  if (ElseToken < 0) or not FTokens[ElseToken].IsKeyword('else') then
  begin
    Exit;
  end;
  if StartsLine(ElseToken) then
  begin
    Add('else', ElseToken, ElseToken, ElseToken, Last, ARoutine);
  end
  else
  begin
    Add('else', ElseToken, ElseToken, AKeyword, Last, ARoutine);
  end;
end;

procedure TBeginEndSites.VisitBody(ANode, ARoutine: TSyntaxNode; AKeyword: Integer; const AName: string);
var
  Last: TSyntaxNode;
  Lead: Integer;
  Fits: Boolean;
begin
  // Rumpf hinter do (Schleifen, with) bzw. hinter : (case-Zweig).
  Last := ANode[ANode.ChildCount - 1];
  Lead := PreviousCode(FTokens, TokenAtOffset(Last.StartOffset));
  if Lead < 0 then
  begin
    Exit;
  end;
  if AName = 'case' then
  begin
    Fits := FTokens[Lead].IsSymbol(':');
  end
  else
  begin
    Fits := FTokens[Lead].IsKeyword('do');
  end;
  if Fits then
  begin
    Add(AName, AKeyword, Lead, AKeyword, Last, ARoutine);
  end;
end;

function TBeginEndSites.Indent(ASite: Integer; const AChosen: TArray<Boolean>): string;
var
  Anchor, Index: Integer;
begin
  Anchor := FSites[ASite].Anchor;
  if StartsLine(Anchor) then
  begin
    Exit(TTextLines.IndentOf(FLines[FTokens[Anchor].StartPos.Line]));
  end;
  // Steht die Anweisung hinter then/do in derselben Zeile, kommt sie mit der Korrektur in eine eigene Zeile.
  for Index := 0 to High(FSites) do
  begin
    if AChosen[Index] and (FSites[Index].First = Anchor) and
      (FTokens[FSites[Index].Lead].StartPos.Line = FTokens[Anchor].StartPos.Line) then
    begin
      Exit(Indent(Index, AChosen) + FIndentUnit);
    end;
  end;
  Result := TTextLines.IndentOf(FLines[FTokens[Anchor].StartPos.Line]);
end;

function TBeginEndSites.BeginEdit(ASite: Integer; const AChosen: TArray<Boolean>): TRuleEdit;
var
  Own, Gap, Text: string;
  LeadEnd: Integer;
begin
  // Vorn: begin in eigener Zeile auf der Einrückung der Anweisung; ein Rumpf aus derselben Zeile rückt ein.
  Own := Indent(ASite, AChosen);
  LeadEnd := FTokens[FSites[ASite].Lead].Offset + Length(FTokens[FSites[ASite].Lead].Text);
  Gap := Copy(FText, LeadEnd + 1, FTokens[FSites[ASite].First].Offset - LeadEnd);
  if Pos(#10, Gap) > 0 then
  begin
    Text := FLineBreak + Own + 'begin' + Gap;
  end
  else
  begin
    Text := FLineBreak + Own + 'begin' + FLineBreak + Own + FIndentUnit + Trim(Gap);
    if Trim(Gap) <> '' then
    begin
      Text := Text + ' ';
    end;
  end;
  Result := TRuleEdit.Create(TTextRange.Create(FTokens[FSites[ASite].Lead].EndPos,
    FTokens[FSites[ASite].First].StartPos), Text);
end;

function TBeginEndSites.EndEdit(ASite: Integer; const AChosen: TArray<Boolean>;
  const ADone: TArray<Boolean>): TRuleEdit;
var
  Text: string;
  Outer, Index: Integer;
  Range: TTextRange;
begin
  // Hinten: alle Rümpfe, die am selben Token enden, innen zuerst. Das Semikolon steht im Block, vor else
  // also keins (E2153). ADone ist ein dynamisches Array: die erledigten Stellen stehen danach beim Aufrufer.
  Text := '';
  Outer := -1;
  // Die Stellen sind nach Schlüsselwort geordnet: von hinten ist die innere zuerst dran.
  for Index := High(FSites) downto 0 do
  begin
    if not AChosen[Index] or (FSites[Index].Last <> FSites[ASite].Last) then
    begin
      Continue;
    end;
    ADone[Index] := True;
    Outer := Index;
    Text := Text + ';' + FLineBreak + Indent(Index, AChosen) + 'end';
  end;
  Range := TTextRange.Create(FTokens[FSites[ASite].Last].EndPos, FTokens[FSites[ASite].Last].EndPos);
  JoinElse(ASite, Outer, AChosen, Text, Range);
  Result := TRuleEdit.Create(Range, Text);
end;

procedure TBeginEndSites.JoinElse(ASite, AOuter: Integer; const AChosen: TArray<Boolean>; var AText: string;
  var ARange: TTextRange);
var
  Next, LeadEnd: Integer;
  Gap: string;
begin
  Next := NextCode(FTokens, FSites[ASite].Last + 1);
  if (Next > High(FTokens)) or not FTokens[Next].IsKeyword('else') then
  begin
    Exit;
  end;
  LeadEnd := FTokens[FSites[ASite].Last].Offset + Length(FTokens[FSites[ASite].Last].Text);
  Gap := Copy(FText, LeadEnd + 1, FTokens[Next].Offset - LeadEnd);
  // format.elsePlacement sameLine: end else. Nur ohne Kommentar dazwischen, der ginge sonst verloren.
  if (FElsePlacement = TBlockPlacement.SameLine) and (Trim(Gap) = '') then
  begin
    AText := AText + ' ';
    ARange.EndPos := FTokens[Next].StartPos;
  end
  else if FTokens[Next].StartPos.Line = FTokens[FSites[ASite].Last].EndPos.Line then
  begin
    AText := AText + FLineBreak + Indent(AOuter, AChosen);
    ARange.EndPos := FTokens[Next].StartPos;
  end;
end;

function TBeginEndSites.Edits(const ASites: TArray<Integer>): TArray<TRuleEdit>;
var
  Chosen, Done: TArray<Boolean>;
  Site, Count: Integer;
begin
  // Höchstens zwei Edits je Stelle: vorn begin, hinten end (gleiche Enden zusammengefasst).
  SetLength(Result, 2 * Length(ASites));
  Count := 0;
  SetLength(Chosen, Length(FSites));
  SetLength(Done, Length(FSites));
  for Site in ASites do
  begin
    Chosen[Site] := True;
  end;
  for Site in ASites do
  begin
    Result[Count] := BeginEdit(Site, Chosen);
    Inc(Count);
  end;
  for Site in ASites do
  begin
    if Done[Site] then
    begin
      Continue;
    end;
    Result[Count] := EndEdit(Site, Chosen, Done);
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

/// <summary>Indizes der Stellen ab AFirst, die in derselben Routine liegen wie AFirst.</summary>
function SitesOfRoutine(const ASites: TArray<TBodySite>; AFirst: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := AFirst to High(ASites) do
  begin
    if ASites[Index].Routine = ASites[AFirst].Routine then
    begin
      Result := Result + [Index];
    end;
  end;
end;

/// <summary>Korrekturen „ganze Methode“ zu allen Stellen von AFinder.</summary>
function MethodFixes(AFinder: TBeginEndSites): TMethodFixes;
var
  Sites: TArray<TBodySite>;
  Index, Other: Integer;
  Method: TArray<Integer>;
begin
  Sites := AFinder.Sites;
  SetLength(Result.Edits, Length(Sites));
  SetLength(Result.Counts, Length(Sites));
  // Die Stellen einer Routine folgen aufeinander (nach Schlüsselwort geordnet), außer bei verschachtelten
  // Routinen; deshalb über alle Stellen sammeln.
  for Index := 0 to High(Sites) do
  begin
    if (Sites[Index].Routine = nil) or (Result.Counts[Index] > 0) then
    begin
      Continue;
    end;
    Method := SitesOfRoutine(Sites, Index);
    if Length(Method) > 1 then
    begin
      Result.Edits[Index] := AFinder.Edits(Method);
    end;
    for Other in Method do
    begin
      Result.Edits[Other] := Result.Edits[Index];
      Result.Counts[Other] := Length(Method);
    end;
  end;
end;

/// <summary>Alle Stellen 0..ACount-1.</summary>
function AllSites(ACount: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  SetLength(Result, ACount);
  for Index := 0 to ACount - 1 do
  begin
    Result[Index] := Index;
  end;
end;

/// <summary>Korrekturen der Stelle ASite: die Stelle, die ganze Methode und die ganze Datei. AFileEdits baut die
/// Korrektur der ganzen Datei beim ersten Bedarf.</summary>
function SiteFixes(AFinder: TBeginEndSites; ASite: Integer; const AMethods: TMethodFixes;
  var AFileEdits: TArray<TRuleEdit>): TArray<TRuleFix>;
var
  SiteCount: Integer;
begin
  Result := [TRuleFix.Create(cTexts[TStyleBeginEndText.SetBeginEnd].Text, AFinder.Edits([ASite]), True)];
  if AMethods.Counts[ASite] > 1 then
  begin
    Result := Result + [TRuleFix.Create(cTexts[TStyleBeginEndText.InMethod].Fmt(
      [AMethods.Counts[ASite]]), AMethods.Edits[ASite])];
  end;
  SiteCount := Length(AFinder.Sites);
  if SiteCount <= Max(1, AMethods.Counts[ASite]) then
  begin
    Exit;
  end;
  if AFileEdits = nil then
  begin
    AFileEdits := AFinder.Edits(AllSites(SiteCount));
  end;
  Result := Result + [TRuleFix.Create(cTexts[TStyleBeginEndText.InFile].Fmt([SiteCount]),
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
  Finder: TBeginEndSites;
  Sites: TArray<TBodySite>;
  Index: Integer;
  Methods: TMethodFixes;
  FileEdits: TArray<TRuleEdit>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Finder := TBeginEndSites.Create(AContext);
  try
    Sites := Finder.Sites;
    Methods := MethodFixes(Finder);
    FileEdits := nil;
    for Index := 0 to High(Sites) do
    begin
      AReport.Add(RangeOf(AContext.Tree.Tokens, Sites[Index].Keyword, Sites[Index].Keyword),
        SiteMessage(Sites[Index].Name), TRuleConfidence.High, SiteFixes(Finder, Index, Methods, FileEdits));
    end;
  finally
    Finder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.BeginEnd', cTexts);

end.
