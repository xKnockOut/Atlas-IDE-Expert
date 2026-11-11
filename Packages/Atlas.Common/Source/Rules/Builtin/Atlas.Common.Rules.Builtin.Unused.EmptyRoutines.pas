unit Atlas.Common.Rules.Builtin.Unused.EmptyRoutines;

// empty-routine (#977), aus Atlas.Common.Rules.Builtin.Unused herausgelöst; angemeldet wird die Regel weiter
// über RegisterUnusedRules. Beschreibung der Regel siehe dort.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TEmptyRoutineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TUnusedEmptyRoutinesText = (Title, RoutineKind, MethodKind, InsertComment, EmptyComment, Empty, RemoveKind);

const
  cTexts: array[TUnusedEmptyRoutinesText] of TAtlasText = (
    (De: 'Methode oder Routine ohne Anweisung und ohne Kommentar';
     En: 'Method or routine without statement and without comment'),
    (De: 'Routine'; En: 'routine'),
    (De: 'Methode'; En: 'method'),
    (De: 'Kommentar einfügen'; En: 'Insert comment'),
    (De: '  // Absichtlich leer.'; En: '  // Intentionally empty.'),
    (De: '%s ist leer; entweder fehlt der Inhalt oder die %s kann weg.';
     En: '%s is empty; either the content is missing or the %s can go.'),
    (De: '%s entfernen'; En: 'Remove %s'));

{$SCOPEDENUMS OFF}

function TEmptyRoutineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-routine', TRuleSeverity.Hint,
    cTexts[TUnusedEmptyRoutinesText.Title].Text);
end;

/// <summary>Kopf der Methode in ihrem Typ und der Sichtbarkeitsabschnitt davor ('' ohne Angabe).</summary>
function MemberHeader(ATypeBody: TSyntaxNode; const AName: string; out AVisibility: string): TSyntaxNode;
var
  mIndex: Integer;
  mVisibility: string;
begin
  Result := nil;
  AVisibility := '';
  mVisibility := '';
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if ATypeBody[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      mVisibility := LowerCase(ATypeBody[mIndex].Name);
    end
    else if (ATypeBody[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(ATypeBody[mIndex].Name, AName) then
    begin
      Result := ATypeBody[mIndex];
      AVisibility := mVisibility;
      Exit;
    end;
  end;
end;

function NodesOfKind(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = AKind then
      begin
        mFound := mFound + [ANode];
      end;
      Result := True;
    end);
  Result := mFound;
end;

/// <summary>Besteht der Block nur aus leeren Anweisungen?</summary>
function IsEmptyBlock(ABlock: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if ABlock[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Ist AHeader der Kopf einer forward-Deklaration im implementation-Teil (ohne Rumpf)?</summary>
function IsImplementationForward(AHeader: TSyntaxNode): Boolean;
begin
  Result := (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) and
    (AHeader.Parent.FindChild(TSyntaxKind.Block) = nil);
  Result := Result and (AHeader.Parent.Parent <> nil) and
    (AHeader.Parent.Parent.Kind = TSyntaxKind.ImplementationSection);
end;

/// <summary>Steht vor dem Zeilenanfang ALineStart (Index des Zeilenumbruchs davor) eine Leerzeile?</summary>
function FollowsBlankLine(const AText: string; ALineStart: Integer): Boolean;
begin
  Result := (ALineStart >= 2) and (AText[ALineStart] = #10);
  Result := Result and ((AText[ALineStart - 1] = #10) or ((AText[ALineStart - 1] = #13) and (ALineStart >= 3) and
    (AText[ALineStart - 2] = #10)));
end;

function RoutineKindText(AIsMethod: Boolean): string;
begin
  Result := cTexts[TUnusedEmptyRoutinesText.RoutineKind].Text;
  if AIsMethod then
  begin
    Result := cTexts[TUnusedEmptyRoutinesText.MethodKind].Text;
  end;
end;

type
  /// <summary>Ein Lauf von empty-routine über eine Datei.</summary>
  TEmptyRoutineCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FRoot: TSyntaxNode;
    FReferences: TArray<TSyntaxNode>;
    FLineBreak: string;
    function Range(AStart, AEnd: Integer): TTextRange;
    function HasCommentOrDirective(AHeader, ARoutine: TSyntaxNode): Boolean;
    function Referenced(const AName: string): Boolean;
    function FirstDocComment(ANode: TSyntaxNode): Integer;
    function RemovalOf(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
    function EmptyParts(ARoutine: TSyntaxNode; out AHeader, ABlock: TSyntaxNode): Boolean;
    function MethodExcused(const AName: string; out AMember: TSyntaxNode; out AVisibility: string): Boolean;
    function FormHandler(const AShort: string): Boolean;
    function CommentFix(ABlock: TSyntaxNode): TArray<TRuleFix>;
    function RoutineRemovable(AHeader: TSyntaxNode; const AName: string; out AForward: TSyntaxNode): Boolean;
    function RemoveEdits(ARoutine, AMember, AForward: TSyntaxNode): TArray<TRuleEdit>;
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TEmptyRoutineCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRoot := AContext.Tree.Root;
  FTokens := AContext.Tree.Tokens;
  FCache := TRuleDerived.Open(AContext);
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

function TEmptyRoutineCheck.Range(AStart, AEnd: Integer): TTextRange;
begin
  Result := TRuleDerived.OffsetRange(FCache, FContext, AStart, AEnd);
end;

// Erstes Token ab AOffset.
// Kommentare oder Direktiven zwischen Kopf und Ende der Routine?
function TEmptyRoutineCheck.HasCommentOrDirective(AHeader, ARoutine: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // Binär zum Ende des Kopfs statt ab Dateianfang (#1342).
  mIndex := TSyntaxTree.FirstTokenOf(FTokens, AHeader.EndOffset);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ARoutine.EndOffset) do
  begin
    if FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TEmptyRoutineCheck.Referenced(const AName: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in FReferences do
  begin
    if SameText(mNode.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := (FContext.FormText <> '') and TRegEx.IsMatch(FContext.FormText, '\b' + AName + '\b',
    [roIgnoreCase]);
end;

/// <summary>Anfang von ANode samt ///-Kommentaren direkt darüber.</summary>
function TEmptyRoutineCheck.FirstDocComment(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := ANode.StartOffset;
  mIndex := TokenFrom(FTokens, ANode.StartOffset) - 1;
  while (mIndex >= 0) and (FTokens[mIndex].Kind = TPascalTokenKind.Comment) and
    StartsStr('///', FTokens[mIndex].Text) do
  begin
    Result := FTokens[mIndex].Offset;
    Dec(mIndex);
  end;
end;

// Ganze Zeilen von ANode samt ";" dahinter und ///-Kommentaren direkt darüber; False, wenn auf den Zeilen
// noch anderes steht.
function TEmptyRoutineCheck.RemovalOf(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
var
  mLast, mIndex, mLineStart, mLineEnd: Integer;
begin
  mLast := ANode.EndOffset;
  mIndex := TokenFrom(FTokens, ANode.EndOffset);
  if (mIndex <= High(FTokens)) and FTokens[mIndex].IsSymbol(';') then
  begin
    mLast := FTokens[mIndex].Offset + 1;
  end;
  Result := WholeLines(FContext.Text, FirstDocComment(ANode), mLast, mLineStart, mLineEnd);
  if not Result then
  begin
    Exit;
  end;
  // Eine Leerzeile davor fällt mit weg, damit keine doppelten Leerzeilen bleiben.
  if FollowsBlankLine(FContext.Text, mLineStart) then
  begin
    Dec(mLineStart);
    if FContext.Text[mLineStart] = #13 then
    begin
      Dec(mLineStart);
    end;
  end;
  AEdit := TRuleEdit.Create(Range(mLineStart, mLineEnd), '');
end;

/// <summary>Hat die Routine Kopf und leeren Rumpf ohne Kommentar und ohne Direktive?</summary>
function TEmptyRoutineCheck.EmptyParts(ARoutine: TSyntaxNode; out AHeader, ABlock: TSyntaxNode): Boolean;
begin
  AHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  ABlock := ARoutine.FindChild(TSyntaxKind.Block);
  Result := (AHeader <> nil) and (ABlock <> nil) and IsEmptyBlock(ABlock) and
    not HasCommentOrDirective(AHeader, ARoutine);
end;

/// <summary>Leere virtuelle Methode als Ersatz für abstract; leerer Nachrichten-Handler; Klasse mit Interfaces:
/// der Compiler verlangt jede Interface-Methode, auch wenn sie nichts zu tun hat (Notifier der Open Tools API).
/// AMember ist der Kopf im Typ (nil ohne).</summary>
function TEmptyRoutineCheck.MethodExcused(const AName: string; out AMember: TSyntaxNode;
  out AVisibility: string): Boolean;
var
  mTypeBody: TSyntaxNode;
begin
  AMember := nil;
  AVisibility := '';
  mTypeBody := FindTypeBody(FRoot, MethodTypeName(AName));
  if mTypeBody <> nil then
  begin
    AMember := MemberHeader(mTypeBody, ShortName(AName), AVisibility);
  end;
  Result := HasDirectiveIn(AMember, ['virtual', 'dynamic', 'message']) or ListsInterfaces(mTypeBody);
end;

/// <summary>Ereignis-Handler aus der Formulardatei: die IDE entfernt sie beim Speichern selbst.</summary>
function TEmptyRoutineCheck.FormHandler(const AShort: string): Boolean;
begin
  Result := (FContext.FormText <> '') and TRegEx.IsMatch(FContext.FormText, '=\s*' + AShort + '\b',
    [roIgnoreCase]);
end;

/// <summary>Kommentar zwischen begin und end.</summary>
function TEmptyRoutineCheck.CommentFix(ABlock: TSyntaxNode): TArray<TRuleFix>;
var
  mBeginToken, mEndToken: Integer;
  mLines: TArray<string>;
  mIndent: string;
begin
  Result := nil;
  mBeginToken := TokenFrom(FTokens, ABlock.StartOffset);
  mEndToken := TokenFrom(FTokens, ABlock.EndOffset) - 1;
  if (mBeginToken > High(FTokens)) or not FTokens[mBeginToken].IsKeyword('begin') or
    (mEndToken <= mBeginToken) or not FTokens[mEndToken].IsKeyword('end') then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(FContext.Text);
  mIndent := '';
  if FTokens[mBeginToken].StartPos.Line <= High(mLines) then
  begin
    mIndent := TTextLines.IndentOf(mLines[FTokens[mBeginToken].StartPos.Line]);
  end;
  Result := [TRuleFix.Create(cTexts[TUnusedEmptyRoutinesText.InsertComment].Text, [TRuleEdit.Create(TTextRange.Create(
    FTokens[mBeginToken].EndPos, FTokens[mEndToken].StartPos), FLineBreak + mIndent +
      cTexts[TUnusedEmptyRoutinesText.EmptyComment].Text +
    FLineBreak + mIndent)])];
end;

/// <summary>Darf die Routine (keine Methode) weg? Nicht, wenn es außer einer forward-Deklaration im
/// implementation-Teil (AForward) weitere Köpfe gleichen Namens gibt.</summary>
function TEmptyRoutineCheck.RoutineRemovable(AHeader: TSyntaxNode; const AName: string;
  out AForward: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := True;
  AForward := nil;
  for mNode in NodesOfKind(FRoot, TSyntaxKind.RoutineHeader) do
  begin
    if (mNode = AHeader) or not SameText(mNode.Name, AName) then
    begin
      Continue;
    end;
    if IsImplementationForward(mNode) and (AForward = nil) then
    begin
      AForward := mNode.Parent;
    end
    else
    begin
      Result := False;
    end;
  end;
end;

/// <summary>Entfernt Rumpf, Kopf im Typ und forward-Deklaration; nil, wenn eins davon nicht sauber geht.
/// </summary>
function TEmptyRoutineCheck.RemoveEdits(ARoutine, AMember, AForward: TSyntaxNode): TArray<TRuleEdit>;
var
  mEdit: TRuleEdit;
begin
  Result := nil;
  if not RemovalOf(ARoutine, mEdit) then
  begin
    Exit;
  end;
  Result := [mEdit];
  if (AMember <> nil) and RemovalOf(AMember, mEdit) then
  begin
    Result := Result + [mEdit];
  end
  else if AMember <> nil then
  begin
    Result := nil;
  end;
  if (AForward <> nil) and (Result <> nil) and RemovalOf(AForward, mEdit) then
  begin
    Result := Result + [mEdit];
  end
  else if AForward <> nil then
  begin
    Result := nil;
  end;
end;

procedure TEmptyRoutineCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mHeader, mBlock, mMember, mForward: TSyntaxNode;
  mName, mShort, mVisibility, mKind: string;
  mCanRemove, mIsMethod: Boolean;
  mFixes: TArray<TRuleFix>;
  mEdits: TArray<TRuleEdit>;
begin
  // Nachrichten-Handler ohne Inhalt schlucken die Nachricht absichtlich.
  if not EmptyParts(ARoutine, mHeader, mBlock) or HasDirectiveIn(mHeader, ['message']) then
  begin
    Exit;
  end;
  mName := mHeader.Name;
  mShort := ShortName(mName);
  mIsMethod := Pos('.', mName) > 0;
  mMember := nil;
  mVisibility := '';
  if (mIsMethod and MethodExcused(mName, mMember, mVisibility)) or FormHandler(mShort) then
  begin
    Exit;
  end;
  mKind := RoutineKindText(mIsMethod);
  mFixes := CommentFix(mBlock);
  // Entfernen nur, wo niemand außerhalb der Datei die Routine sehen kann und sie hier nicht vorkommt.
  mForward := nil;
  if mIsMethod then
  begin
    mCanRemove := (mMember <> nil) and ((mVisibility = 'private') or (mVisibility = 'strict private')) and
      not MethodSignatureFixed(FRoot, mName) and not HasDirectiveIn(mMember, ['override', 'overload']);
  end
  else
  begin
    mCanRemove := RoutineRemovable(mHeader, mName, mForward);
  end;
  if mCanRemove and not Referenced(mShort) then
  begin
    mEdits := RemoveEdits(ARoutine, mMember, mForward);
    if mEdits <> nil then
    begin
      mFixes := mFixes + [TRuleFix.Create(cTexts[TUnusedEmptyRoutinesText.RemoveKind].Fmt([mKind]), mEdits)];
    end;
  end;
  FReport.Add(NameRange(FContext, mHeader, mShort), cTexts[TUnusedEmptyRoutinesText.Empty].Fmt([mShort, mKind]),
    mFixes);
end;

procedure TEmptyRoutineCheck.Run;
var
  mRoutine: TSyntaxNode;
begin
  FReferences := NodesOfKind(FRoot, TSyntaxKind.Identifier) + NodesOfKind(FRoot, TSyntaxKind.MemberAccess);
  for mRoutine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

procedure TEmptyRoutineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TEmptyRoutineCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TEmptyRoutineCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Unused.EmptyRoutines', cTexts);

end.
