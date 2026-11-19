unit Atlas.Common.Rules.Builtin.Declarations.FieldOrder;

// Prüfregel field-after-method (#986, wie E2169): Feld nach Methode oder
// Property im selben Abschnitt einer Klasse, eines Objekts oder Records.
// Korrekturen: Feld samt Attributen und Kommentaren an den Anfang des
// Abschnitts verschieben (nur ohne Bedingungen dazwischen) oder var davor
// setzen; in Records var zuerst, weil Verschieben das Speicherlayout ändert.
// Zweige bedingter Übersetzung zählen: Gemeldet wird nur, wenn eine Methode
// sicher vor dem Feld übersetzt wird.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TFieldAfterMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cFieldAfterMethodRuleId = 'field-after-method';

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFieldOrderText = (Title, MoveField, InsertVar, FieldAfter);

const
  cTexts: array[TFieldOrderText] of TAtlasText = (
    (De: 'Feld nach Methoden im selben Abschnitt'; En: 'Field after methods in the same section'),
    (De: 'Feld an den Anfang des Abschnitts verschieben'; En: 'Move field to the start of the section'),
    (De: 'var davor setzen'; En: 'Put var before it'),
    (De: 'Feld nach Methoden im selben Abschnitt (wie E2169).';
     En: 'Field after methods in the same section (like E2169).'));

{$SCOPEDENUMS OFF}

{ TFieldAfterMethodRule }

function TFieldAfterMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cFieldAfterMethodRuleId, TRuleSeverity.Error,
    cTexts[TFieldOrderText.Title].Text);
end;

type
  /// <summary>Ein Lauf von TFieldAfterMethodRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TFieldAfterMethodScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FLines: TArray<string>;
    FLineBreak: string;
    FPaths: TArray<string>;
    function FirstToken(ANode: TSyntaxNode): Integer;
    function PathOf(ANode: TSyntaxNode): string;
    function OnlySpaceBefore(const APosition: TTextPosition): Boolean;
    function OnlyCommentAfter(const APosition: TTextPosition): Boolean;
    function BlockFirst(ABody: TSyntaxNode; AIndex: Integer): TSyntaxNode;
    function StartLine(ANode: TSyntaxNode): Integer;
    function MoveFix(ABody: TSyntaxNode; AField, AMember: Integer): TArray<TRuleFix>;
    function VarFix(ABody: TSyntaxNode; AField: Integer): TRuleFix;
    function Guards(ABody: TSyntaxNode; AMember, AField: Integer): Boolean;
    function HasGuard(ABody: TSyntaxNode; AFirst, AField: Integer): Boolean;
    procedure CheckField(ABody: TSyntaxNode; AField, AFirst: Integer; ASamePaths: Boolean);
    procedure CheckBody(ABody: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TFieldAfterMethodScan }

constructor TFieldAfterMethodScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TFieldAfterMethodScan.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TokenFrom(FTokens, ANode.StartOffset);
end;

function TFieldAfterMethodScan.PathOf(ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(ANode));
end;

function TFieldAfterMethodScan.OnlySpaceBefore(const APosition: TTextPosition): Boolean;
begin
  Result := BlankBefore(FLines, APosition);
end;

function TFieldAfterMethodScan.OnlyCommentAfter(const APosition: TTextPosition): Boolean;
begin
  Result := BlankAfter(FLines, APosition);
end;

// Erstes Kind des Blocks um ABody[AIndex]: davorstehende Attribute gehören dazu.
function TFieldAfterMethodScan.BlockFirst(ABody: TSyntaxNode; AIndex: Integer): TSyntaxNode;
begin
  while (AIndex > 0) and (ABody[AIndex - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(AIndex);
  end;
  Result := ABody[AIndex];
end;

// Erste Zeile des Blocks ab ANode samt Kommentarzeilen direkt darüber (XMLDoc).
function TFieldAfterMethodScan.StartLine(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := ANode.StartPos.Line;
  mIndex := FirstToken(ANode) - 1;
  while (mIndex >= 0) and (FTokens[mIndex].Kind = TPascalTokenKind.Comment) and
    (FTokens[mIndex].EndPos.Line = Result - 1) and OnlySpaceBefore(FTokens[mIndex].StartPos) do
  begin
    Result := FTokens[mIndex].StartPos.Line;
    Dec(mIndex);
  end;
end;

// Feld samt Attributen und Kommentaren vor das erste Mitglied des Abschnitts; nil, wenn Zeilen nicht passen.
function TFieldAfterMethodScan.MoveFix(ABody: TSyntaxNode; AField, AMember: Integer): TArray<TRuleFix>;
var
  mField, mTarget: TSyntaxNode;
  mFieldStart, mFieldEnd, mTargetLine, mLine: Integer;
  mMoved: string;
begin
  Result := nil;
  mField := BlockFirst(ABody, AField);
  mTarget := BlockFirst(ABody, AMember);
  if not OnlySpaceBefore(mField.StartPos) or not OnlySpaceBefore(mTarget.StartPos) or
    not OnlyCommentAfter(ABody[AField].EndPos) then
  begin
    Exit;
  end;
  mFieldStart := StartLine(mField);
  mFieldEnd := ABody[AField].EndPos.Line;
  mTargetLine := StartLine(mTarget);
  if (mTargetLine >= mFieldStart) or (mFieldEnd + 1 >= Length(FLines)) then
  begin
    Exit;
  end;
  mMoved := '';
  for mLine := mFieldStart to mFieldEnd do
  begin
    mMoved := mMoved + FLines[mLine] + FLineBreak;
  end;
  Result := [TRuleFix.Create(cTexts[TFieldOrderText.MoveField].Text, [
    TRuleEdit.Create(TTextRange.Create(mTargetLine, 0, mTargetLine, 0), mMoved),
    TRuleEdit.Create(TTextRange.Create(mFieldStart, 0, mFieldEnd + 1, 0), '')], True)];
end;

function TFieldAfterMethodScan.VarFix(ABody: TSyntaxNode; AField: Integer): TRuleFix;
var
  mFirst: TSyntaxNode;
begin
  mFirst := BlockFirst(ABody, AField);
  Result := TRuleFix.Create(cTexts[TFieldOrderText.InsertVar].Text,
    [TRuleEdit.Create(TTextRange.Create(mFirst.StartPos,
    mFirst.StartPos), 'var ')], True);
end;

// Ist ABody[AMember] eine Methode oder Property, die immer mit übersetzt wird, wenn das Feld ABody[AField]
// übersetzt wird?
function TFieldAfterMethodScan.Guards(ABody: TSyntaxNode; AMember, AField: Integer): Boolean;
begin
  Result := (ABody[AMember].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
    TConditionalBranches.Implies(PathOf(ABody[AField]), PathOf(ABody[AMember]));
end;

// Gibt es zwischen ABody[AFirst] und dem Feld ABody[AField] eine Methode, die es sicher vor dem Feld gibt?
function TFieldAfterMethodScan.HasGuard(ABody: TSyntaxNode; AFirst, AField: Integer): Boolean;
var
  mMember: Integer;
begin
  mMember := AFirst;
  while (mMember < AField) and not Guards(ABody, mMember, AField) do
  begin
    Inc(mMember);
  end;
  Result := mMember < AField;
end;

// Meldet das Feld ABody[AField] hinter dem ersten Mitglied ABody[AFirst]; ASamePaths: keine Bedingungen
// zwischen den Mitgliedern.
procedure TFieldAfterMethodScan.CheckField(ABody: TSyntaxNode; AField, AFirst: Integer; ASamePaths: Boolean);
var
  mFixes: TArray<TRuleFix>;
begin
  if not HasGuard(ABody, AFirst, AField) then
  begin
    Exit;
  end;
  mFixes := nil;
  // Verschieben nur ohne Bedingungen dazwischen, sonst landet das Feld in einem anderen Zweig.
  if ASamePaths and (PathOf(ABody[AField]) = PathOf(ABody[AFirst])) then
  begin
    mFixes := MoveFix(ABody, AField, AFirst);
  end;
  if ABody.Kind = TSyntaxKind.RecordType then
  begin
    // In Records verschiebt das Verschieben das Speicherlayout; var zuerst.
    mFixes := [VarFix(ABody, AField)] + mFixes;
  end
  else
  begin
    mFixes := mFixes + [VarFix(ABody, AField)];
  end;
  FReport.Add(TTextRange.Create(ABody[AField].StartPos, ABody[AField].EndPos),
    cTexts[TFieldOrderText.FieldAfter].Text, TRuleConfidence.High, mFixes);
end;

procedure TFieldAfterMethodScan.CheckBody(ABody: TSyntaxNode);
var
  mIndex, mFirst: Integer;
  mSamePaths: Boolean;
begin
  mFirst := -1;
  mSamePaths := True;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    case ABody[mIndex].Kind of
      // Ein neuer Abschnitt bzw. var erlaubt wieder Felder.
      TSyntaxKind.Visibility, TSyntaxKind.VarSection, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection:
        begin
          mFirst := -1;
          mSamePaths := True;
        end;
      TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
        if mFirst < 0 then
        begin
          mFirst := mIndex;
        end
        else if PathOf(ABody[mIndex]) <> PathOf(ABody[mFirst]) then
        begin
          mSamePaths := False;
        end;
      TSyntaxKind.Field:
        if mFirst >= 0 then
        begin
          CheckField(ABody, mIndex, mFirst, mSamePaths);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

procedure TFieldAfterMethodScan.Visit(ARoot: TSyntaxNode);
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
      if mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType] then
      begin
        CheckBody(mNode);
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

procedure TFieldAfterMethodScan.Run;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FTokens := FContext.Tree.Tokens;
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  FPaths := TConditionalBranches.Paths(FTokens);
  Visit(FContext.Tree.Root);
end;

procedure TFieldAfterMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TFieldAfterMethodScan;
begin
  mScan := TFieldAfterMethodScan.Create(AContext, AReport);
  mScan.Run;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.FieldOrder', cTexts);

end.
