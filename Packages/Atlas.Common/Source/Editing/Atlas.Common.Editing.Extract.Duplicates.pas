unit Atlas.Common.Editing.Extract.Duplicates;

// „Methode extrahieren“ mit gleichen Stellen (#2054): Nach dem Plan für die Auswahl sucht die Unit in allen
// Routinen der Unit Anweisungsfolgen, die der Auswahl textgleich sind (Normalform: Token ohne Kommentare,
// Groß-/Kleinschreibung egal, Direktiven zählen mit), nur über ganze Anweisungen derselben Anweisungsliste und
// ohne Überlappung. Verglichen wird erst das erste Token, dann die Normalform.
// Eine Fundstelle gilt nur, wenn derselbe Plan an ihr dieselbe neue Methode ergäbe: gleicher Kopf (also dieselbe
// Klasse bzw. Ebene), gleiche Parameter mit gleicher Art und gleichem Typ, gleiche lokale Variablen und
// Konstanten. Das deckt die Bedeutung der Namen ab: Ein lokaler Name, der an der Fundstelle ein Feld verdeckt
// (oder umgekehrt), ändert die Parameterliste; ein with-Rumpf, eine anonyme Methode oder ein Sprung an der
// Fundstelle lässt den Plan scheitern.
// Stellen in derselben Routine beeinflussen einander: Nach dem Ersetzen greift dort nur noch der Aufruf zu. Darum
// rechnet die Unit die Parameterarten so lange neu, bis sie sich nicht mehr ändern (Fixpunkt); weichen Stellen
// ab, fallen sie heraus.
// Ergebnis ist eine Code-Aktion mit abwählbaren Teilen (TCodeAction.Choices): je Fundstelle der Aufruf; das
// Entfernen lokaler Variablen einer Routine gilt nur, wenn alle Fundstellen dieser Routine gewählt sind.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract.Shared,
  Atlas.Common.Editing.Extract.Method;

type
  /// <summary>Eine weitere gleiche Stelle.</summary>
  TExtractDuplicate = record
    Window: TExtractWindow;
    Range: TTextRange;
    /// <summary>Umgebende Routine.</summary>
    Routine: TSyntaxNode;
    Plan: TMethodPlan;
  end;

  /// <summary>Sucht und prüft gleiche Stellen zu einer Auswahl.</summary>
  TExtractDuplicates = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FOptions: TExtractOptions;
    FRange: TTextRange;
    FMain: TExtractWindow;
    FMainRoutine: TSyntaxNode;
    FPattern: TArray<string>;
    FFirstToken: string;
    FFound: TArray<TExtractDuplicate>;
    FAction: TCodeAction;
    FPlan: TMethodPlan;
    FReason: string;
    /// <summary>Plan der Auswahl ohne weitere Stellen: Muster und Prüfungen.</summary>
    function PrepareMain: Boolean;
    /// <summary>Normalform von ANode; für die erste Anweisung (AFirst) '' ohne passendes erstes Token.</summary>
    function Normal(ANode: TSyntaxNode; AFirst: Boolean): string;
    function Overlaps(const AWindow: TExtractWindow): Boolean;
    /// <summary>Folge ab Kind AFirst von AParent passt zum Muster.</summary>
    function Matches(AParent: TSyntaxNode; AFirst: Integer): Boolean;
    procedure AddCandidate(AParent: TSyntaxNode; AFirst: Integer);
    procedure SearchList(AParent: TSyntaxNode);
    procedure Search(ANode: TSyntaxNode);
    /// <summary>Weitere Stellen in ARoutine außer AWindow (die Auswahl eingeschlossen).</summary>
    function OthersIn(ARoutine: TSyntaxNode; const AWindow: TExtractWindow): TArray<TExtractWindow>;
    /// <summary>Plan für ARange mit weiteren Stellen und angenommenen Parameterarten.</summary>
    function PlanFor(const ARange: TTextRange; const AContext: TExtractContext; out AAction: TCodeAction;
      out APlan: TMethodPlan): Boolean;
    /// <summary>Eine Runde: Auswahl mit AAssumed planen, Fundstellen gegen ihren Plan prüfen; True, wenn sich
    /// nichts geändert hat.</summary>
    function Round(var AAssumed: TArray<TExtractParameter>): Boolean;
    function Settle: Boolean;
    procedure Remove(AIndex: Integer);
    function ChoicesIn(ARoutine: TSyntaxNode): TArray<Integer>;
    function BuildAction: TCodeAction;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
    /// <summary>Plant die Auswahl ARange samt gleichen Stellen; False, wenn es keine gibt (Grund in AReason).
    /// </summary>
    function Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
    /// <summary>Gefundene Stellen nach Run.</summary>
    property Found: TArray<TExtractDuplicate> read FFound;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen.</summary>
  TDuplicatesText = (NoDuplicates, Title, TitleOne, PreviewHead, PreviewPlaces, Place);

const
  cTexts: array[TDuplicatesText] of TAtlasText = (
    (De: 'keine gleichen Stellen in der Unit'; En: 'no equal places in the unit'),
    (De: 'Methode extrahieren und %d gleiche Stellen ersetzen'; En: 'Extract method and replace %d equal places'),
    (De: 'Methode extrahieren und gleiche Stelle ersetzen'; En: 'Extract method and replace the equal place'),
    (De: 'Neue Methode: %s'; En: 'New method: %s'),
    (De: 'Weitere gleiche Stellen (%d):'; En: 'Further equal places (%d):'),
    (De: 'Zeile %d in %s'; En: 'Line %d in %s'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Höchstzahl der Runden über die Zahl der Fundstellen hinaus.</summary>
  cExtraRounds = 3;

function FirstTokenText(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := '';
  mTokens := ATree.Tokens;
  mIndex := TRoutineBody.TokenAt(mTokens, ANode.StartOffset);
  if (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) then
  begin
    Result := LowerCase(mTokens[mIndex].Text);
  end;
end;

function WindowOf(AFirst, ALast: TSyntaxNode): TExtractWindow;
begin
  Result := TExtractWindow.Create(AFirst.StartOffset, ALast.EndOffset);
end;

function RoutineName(ARoutine: TSyntaxNode): string;
begin
  Result := '';
  if ARoutine <> nil then
  begin
    Result := ARoutine.Name;
  end;
end;

{ TExtractDuplicates }

constructor TExtractDuplicates.Create(const AText: string; ATree: TSyntaxTree; const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FOptions := AOptions;
end;

function TExtractDuplicates.PlanFor(const ARange: TTextRange; const AContext: TExtractContext;
  out AAction: TCodeAction; out APlan: TMethodPlan): Boolean;
var
  mExtraction: TMethodExtraction;
  mReason: string;
begin
  mExtraction := TMethodExtraction.Create(FText, FTree, FOptions);
  try
    mExtraction.Context := AContext;
    Result := mExtraction.Run(ARange, AAction, mReason);
    APlan := mExtraction.Plan;
    if not Result then
    begin
      FReason := mReason;
    end;
  finally
    mExtraction.Free;
  end;
end;

function TExtractDuplicates.PrepareMain: Boolean;
var
  mExtraction: TMethodExtraction;
  mStatements: TArray<TSyntaxNode>;
  mStatement: TSyntaxNode;
  mAction: TCodeAction;
begin
  mExtraction := TMethodExtraction.Create(FText, FTree, FOptions);
  try
    Result := mExtraction.Run(FRange, mAction, FReason);
    if not Result then
    begin
      Exit;
    end;
    mStatements := mExtraction.Statements;
    FMainRoutine := mExtraction.Plan.Routine;
  finally
    mExtraction.Free;
  end;
  FMain := WindowOf(mStatements[0], mStatements[High(mStatements)]);
  FFirstToken := FirstTokenText(FTree, mStatements[0]);
  FPattern := nil;
  for mStatement in mStatements do
  begin
    FPattern := FPattern + [TExtractSupport.NormalText(FTree, mStatement, True)];
  end;
end;

function TExtractDuplicates.Normal(ANode: TSyntaxNode; AFirst: Boolean): string;
begin
  Result := '';
  if not AFirst or (FirstTokenText(FTree, ANode) = FFirstToken) then
  begin
    Result := TExtractSupport.NormalText(FTree, ANode, True);
  end;
end;

function TExtractDuplicates.Overlaps(const AWindow: TExtractWindow): Boolean;
var
  mDuplicate: TExtractDuplicate;
begin
  Result := (AWindow.Start < FMain.Finish) and (FMain.Start < AWindow.Finish);
  for mDuplicate in FFound do
  begin
    Result := Result or ((AWindow.Start < mDuplicate.Window.Finish) and (mDuplicate.Window.Start < AWindow.Finish));
  end;
end;

function TExtractDuplicates.Matches(AParent: TSyntaxNode; AFirst: Integer): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := AFirst + Length(FPattern) <= AParent.ChildCount;
  mIndex := 0;
  while Result and (mIndex <= High(FPattern)) do
  begin
    mChild := AParent[AFirst + mIndex];
    Result := TRoutineBody.InList(mChild) and (Normal(mChild, mIndex = 0) = FPattern[mIndex]);
    Inc(mIndex);
  end;
end;

procedure TExtractDuplicates.AddCandidate(AParent: TSyntaxNode; AFirst: Integer);
var
  mDuplicate: TExtractDuplicate;
  mLast: TSyntaxNode;
begin
  mDuplicate := Default(TExtractDuplicate);
  mLast := AParent[AFirst + High(FPattern)];
  mDuplicate.Window := WindowOf(AParent[AFirst], mLast);
  if Overlaps(mDuplicate.Window) then
  begin
    Exit;
  end;
  mDuplicate.Range := TTextRange.Create(AParent[AFirst].StartPos, mLast.EndPos);
  mDuplicate.Routine := TRoutineBody.RoutineAt(FTree, mDuplicate.Window.Start);
  if mDuplicate.Routine <> nil then
  begin
    FFound := FFound + [mDuplicate];
  end;
end;

procedure TExtractDuplicates.SearchList(AParent: TSyntaxNode);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParent.ChildCount - Length(FPattern) do
  begin
    if Matches(AParent, mIndex) then
    begin
      AddCandidate(AParent, mIndex);
    end;
  end;
end;

procedure TExtractDuplicates.Search(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  SearchList(ANode);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Search(ANode[mIndex]);
  end;
end;

function TExtractDuplicates.OthersIn(ARoutine: TSyntaxNode; const AWindow: TExtractWindow): TArray<TExtractWindow>;
var
  mDuplicate: TExtractDuplicate;
begin
  Result := nil;
  if (ARoutine = FMainRoutine) and (AWindow.Start <> FMain.Start) then
  begin
    Result := Result + [FMain];
  end;
  for mDuplicate in FFound do
  begin
    if (mDuplicate.Routine = ARoutine) and (mDuplicate.Window.Start <> AWindow.Start) then
    begin
      Result := Result + [mDuplicate.Window];
    end;
  end;
end;

procedure TExtractDuplicates.Remove(AIndex: Integer);
begin
  Delete(FFound, AIndex, 1);
end;

function TExtractDuplicates.Round(var AAssumed: TArray<TExtractParameter>): Boolean;
var
  mContext: TExtractContext;
  mIndex: Integer;
  mAction: TCodeAction;
  mPlan: TMethodPlan;
begin
  mContext.Others := OthersIn(FMainRoutine, FMain);
  mContext.Assumed := AAssumed;
  if not PlanFor(FRange, mContext, FAction, FPlan) then
  begin
    // Ohne Annahmen geht die Auswahl (PrepareMain); mit ihnen nicht: die Stellen der Routine weglassen.
    Result := False;
    mIndex := High(FFound);
    while mIndex >= 0 do
    begin
      if FFound[mIndex].Routine = FMainRoutine then
      begin
        Remove(mIndex);
      end;
      Dec(mIndex);
    end;
    AAssumed := nil;
    Exit;
  end;
  Result := SameParameters(FPlan.Parameters, AAssumed);
  mContext.Assumed := FPlan.Parameters;
  mIndex := High(FFound);
  while mIndex >= 0 do
  begin
    mContext.Others := OthersIn(FFound[mIndex].Routine, FFound[mIndex].Window);
    if PlanFor(FFound[mIndex].Range, mContext, mAction, mPlan) and (mPlan.Key = FPlan.Key) then
    begin
      FFound[mIndex].Plan := mPlan;
    end
    else
    begin
      Remove(mIndex);
      Result := False;
    end;
    Dec(mIndex);
  end;
  AAssumed := FPlan.Parameters;
end;

function TExtractDuplicates.Settle: Boolean;
var
  mAssumed: TArray<TExtractParameter>;
  mRound: Integer;
begin
  mAssumed := nil;
  Result := False;
  mRound := 0;
  while not Result and (FFound <> nil) and (mRound <= Length(FFound) + cExtraRounds) do
  begin
    Result := Round(mAssumed);
    Inc(mRound);
  end;
  Result := Result and (FFound <> nil);
end;

function TExtractDuplicates.ChoicesIn(ARoutine: TSyntaxNode): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FFound) do
  begin
    if FFound[mIndex].Routine = ARoutine then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function SameRange(const ALeft, ARight: TTextRange): Boolean;
begin
  Result := (ALeft.StartPos.Line = ARight.StartPos.Line) and (ALeft.StartPos.Character = ARight.StartPos.Character)
    and (ALeft.EndPos.Line = ARight.EndPos.Line) and (ALeft.EndPos.Character = ARight.EndPos.Character);
end;

function IndexOfNode(const ANodes: TArray<TSyntaxNode>; ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(ANodes) downto 0 do
  begin
    if ANodes[mIndex] = ANode then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Erste Zeile von AText ohne Zeilenumbruch.</summary>
function FirstLine(const AText: string): string;
var
  mEnd: Integer;
begin
  mEnd := Pos(#10, AText);
  Result := AText;
  if mEnd > 0 then
  begin
    Result := Copy(AText, 1, mEnd - 1);
  end;
  Result := Trim(Result);
end;

/// <summary>Edits von AEdits ohne die aus ALocal (gleicher Bereich und Text).</summary>
function Without(const AEdits, ALocal: TArray<TTextEdit>): TArray<TTextEdit>;
var
  mEdit, mLocal: TTextEdit;
  mFound: Boolean;
begin
  Result := nil;
  for mEdit in AEdits do
  begin
    mFound := False;
    for mLocal in ALocal do
    begin
      mFound := mFound or (SameRange(mEdit.Range, mLocal.Range) and (mEdit.NewText = mLocal.NewText));
    end;
    if not mFound then
    begin
      Result := Result + [mEdit];
    end;
  end;
end;

/// <summary>Hängt AEdits an AAction an, jeder mit der Bedingung AChoices.</summary>
procedure AddEdits(var AAction: TCodeAction; const AEdits: TArray<TTextEdit>; const AChoices: TArray<Integer>);
var
  mEdit: TTextEdit;
begin
  for mEdit in AEdits do
  begin
    AAction.Edits := AAction.Edits + [mEdit];
    SetLength(AAction.EditChoices, Length(AAction.Edits));
    AAction.EditChoices[High(AAction.EditChoices)] := AChoices;
  end;
end;

function TExtractDuplicates.BuildAction: TCodeAction;
var
  mIndex: Integer;
  mPreview: string;
  mDone: TArray<TSyntaxNode>;
  mRoutine: TSyntaxNode;
begin
  Result := FAction;
  Result.Edits := nil;
  Result.EditChoices := nil;
  AddEdits(Result, Without(FAction.Edits, FPlan.LocalEdits), nil);
  AddEdits(Result, FPlan.LocalEdits, ChoicesIn(FMainRoutine));
  mDone := [FMainRoutine];
  mPreview := cTexts[TDuplicatesText.PreviewHead].Fmt([FirstLine(FPlan.Key)]) + sLineBreak +
    cTexts[TDuplicatesText.PreviewPlaces].Fmt([Length(FFound)]);
  for mIndex := 0 to High(FFound) do
  begin
    Result.Choices := Result.Choices + [TCodeActionChoice.Create(cTexts[TDuplicatesText.Place].Fmt(
      [FFound[mIndex].Range.StartPos.Line + 1, RoutineName(FFound[mIndex].Routine)]), FFound[mIndex].Range)];
    mPreview := mPreview + sLineBreak + '  ' + Result.Choices[mIndex].Title;
    AddEdits(Result, [TTextEdit.Create(FFound[mIndex].Range, FPlan.CallText)], [mIndex]);
    mRoutine := FFound[mIndex].Routine;
    if IndexOfNode(mDone, mRoutine) < 0 then
    begin
      mDone := mDone + [mRoutine];
      AddEdits(Result, FFound[mIndex].Plan.LocalEdits, ChoicesIn(mRoutine));
    end;
  end;
  Result.Title := cTexts[TDuplicatesText.Title].Fmt([Length(FFound)]);
  if Length(FFound) = 1 then
  begin
    Result.Title := cTexts[TDuplicatesText.TitleOne].Text;
  end;
  Result.Preview := mPreview;
end;

function TExtractDuplicates.Run(const ARange: TTextRange; out AAction: TCodeAction; out AReason: string): Boolean;
begin
  AAction := Default(TCodeAction);
  FRange := ARange;
  FFound := nil;
  FReason := '';
  Result := PrepareMain;
  if Result then
  begin
    Search(FTree.Root);
    Result := Settle;
    if Result then
    begin
      AAction := BuildAction;
    end
    else
    begin
      FReason := cTexts[TDuplicatesText.NoDuplicates].Text;
    end;
  end;
  AReason := FReason;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Extract.Duplicates', cTexts);

end.
