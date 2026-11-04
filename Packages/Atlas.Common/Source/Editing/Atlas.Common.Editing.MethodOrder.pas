unit Atlas.Common.Editing.MethodOrder;

// Methodenrümpfe in Deklarationsreihenfolge (#660).
//
// Arrange ordnet alle Rümpfe der Unit: nach ihrem Typ (Reihenfolge der Typen
// in der Datei) und dort nach der Deklarationsreihenfolge, alternativ
// alphabetisch. Die Rümpfe tauschen nur untereinander die Plätze; freie
// Routinen, Rümpfe ohne Deklaration, {$REGION}-Klammern und alles zwischen
// den Rümpfen bleibt stehen. Kommentare direkt über einem Rumpf (ohne
// Leerzeile) wandern mit.
//
// Nicht verschoben ("bleibt") wird ein Rumpf,
//   - der in einer Region oder einem {$IF…}-Zweig liegt oder dessen Bereich
//     eine solche Klammer nur zur Hälfte enthält,
//   - der eine Zeile mit anderem Code teilt.
//
// PlaceNew setzt nur neue Rümpfe an ihre Stelle: hinter den Rumpf der
// zuletzt davor deklarierten Methode desselben Typs, sonst vor den der
// nächsten, sonst hinter den letzten Rumpf eines früheren bzw. vor den ersten
// eines späteren Typs. Neu ist ein Rumpf, dessen Kopfzeile im Text vorher
// (ABefore) nicht vorkam und der keinen dort schon vorhandenen Routinenkopf
// umschließt; so zählt ein halb getippter Rumpf, der den nächsten
// verschluckt, nicht als neu.
//
// Beide liefern eine Textänderung über den betroffenen Zeilenbereich und je
// Rumpf die Verschiebung in Rümpfen (negativ = nach oben).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ordnung der Rümpfe; Off schaltet Verschieben und Befehl ab (editor.methodPlacement).</summary>
  TMethodPlacement = (Off, Declaration, Alphabetical);

  /// <summary>Warum ein Rumpf stehen bleibt.</summary>
  TMethodStayReason = (None, Region, Conditional, SharedLine);
  {$SCOPEDENUMS OFF}

  TMethodMove = record
    TypeName: string;
    Name: string;
    /// <summary>Zeile des Kopfs im Text vor der Änderung.</summary>
    Line: Integer;
    /// <summary>Zeile des Kopfs danach; bei stehen bleibenden Rümpfen -1.</summary>
    NewLine: Integer;
    /// <summary>Zeilen vom Kopf bis zum abschließenden end.</summary>
    Size: Integer;
    /// <summary>Verschiebung in Rümpfen; negativ = nach oben.</summary>
    Delta: Integer;
    /// <summary>Bleibt stehen (Grund in Reason).</summary>
    Fixed: Boolean;
    Reason: TMethodStayReason;
  end;

  TMethodOrderResult = record
    Edits: TArray<TTextEdit>;
    /// <summary>Verschobene Rümpfe in der neuen Reihenfolge, danach die stehen bleibenden.</summary>
    Moves: TArray<TMethodMove>;
  end;

  TMethodOrder = class
  public
    /// <summary>Ordnet alle Rümpfe der Unit; ohne Edits, wenn alles passt oder APlacement Off ist.</summary>
    class function Arrange(ATree: TSyntaxTree; const AText: string;
      APlacement: TMethodPlacement): TMethodOrderResult; static;
    /// <summary>Setzt die gegenüber ABefore neuen Rümpfe an ihre Stelle; ohne Edits, wenn keiner neu ist oder
    /// alle schon passen.</summary>
    class function PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
      APlacement: TMethodPlacement): TMethodOrderResult; static;
    /// <summary>off, declaration, alphabetical.</summary>
    class function PlacementName(APlacement: TMethodPlacement): string; static;
    /// <summary>Unbekannt oder leer: Declaration.</summary>
    class function PlacementOf(const AName: string): TMethodPlacement; static;
    /// <summary>'', region, ifdef, line.</summary>
    class function ReasonName(AReason: TMethodStayReason): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.ClassCompletion;

type
  TBlock = record
    TypeName, Name: string;
    TypeOrder, DeclarationOrder: Integer;
    /// <summary>Erste Zeile (mit Kommentaren darüber), Kopfzeile, letzte Zeile.</summary>
    First, Header, Last: Integer;
    Fixed, New: Boolean;
    Reason: TMethodStayReason;
  end;

  TBlocks = TArray<TBlock>;

  /// <summary>Ziel eines neuen Rumpfs.</summary>
  TAnchor = record
    /// <summary>Index in den vorhandenen Rümpfen; -1 = bleibt, wo er ist.</summary>
    Block: Integer;
    After: Boolean;
  end;

const
  RoutineWords: array[0..5] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
    'class ');

function Before(const A, B: TBlock; APlacement: TMethodPlacement): Boolean;
var
  Compared: Integer;
begin
  if A.TypeOrder <> B.TypeOrder then
  begin
    Exit(A.TypeOrder < B.TypeOrder);
  end;
  if APlacement = TMethodPlacement.Alphabetical then
  begin
    Compared := CompareText(A.Name, B.Name);
    if Compared <> 0 then
    begin
      Exit(Compared < 0);
    end;
  end;
  if A.DeclarationOrder <> B.DeclarationOrder then
  begin
    Exit(A.DeclarationOrder < B.DeclarationOrder);
  end;
  // Eindeutig weiter nach der Stelle im Text.
  Result := A.First < B.First;
end;

/// <summary>Stabil nach Ordnung (Einfügen; die Zahl der Rümpfe bleibt klein).</summary>
function Sorted(const ABlocks: TBlocks; APlacement: TMethodPlacement): TBlocks;
var
  Index, Target: Integer;
  Item: TBlock;
begin
  Result := Copy(ABlocks);
  for Index := 1 to High(Result) do
  begin
    Item := Result[Index];
    Target := Index - 1;
    while (Target >= 0) and Before(Item, Result[Target], APlacement) do
    begin
      Result[Target + 1] := Result[Target];
      Dec(Target);
    end;
    Result[Target + 1] := Item;
  end;
end;

function ByLine(const ABlocks: TBlocks): TBlocks;
var
  Index, Target: Integer;
  Item: TBlock;
begin
  Result := Copy(ABlocks);
  for Index := 1 to High(Result) do
  begin
    Item := Result[Index];
    Target := Index - 1;
    while (Target >= 0) and (Item.First < Result[Target].First) do
    begin
      Result[Target + 1] := Result[Target];
      Dec(Target);
    end;
    Result[Target + 1] := Item;
  end;
end;

function IndexOfBlock(const ABlocks: TBlocks; const ABlock: TBlock): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ABlocks) do
  begin
    if ABlocks[Index].Header = ABlock.Header then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function IsRoutineHeader(const ALine: string): Boolean;
var
  Word: string;
  Lower: string;
begin
  Lower := LowerCase(Trim(ALine));
  for Word in RoutineWords do
  begin
    if StartsStr(Word, Lower) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Merkmale je Zeile: Code, Kommentar und Tiefe der {$IF…}- und {$REGION}-Klammern am Zeilenanfang (der
  /// letzte Eintrag gilt hinter der letzten Zeile).</summary>
  TLineMarks = record
    Code, Comment: TArray<Boolean>;
    CondAt, RegionAt: TArray<Integer>;
    /// <summary>Liest die Merkmale der ALineCount Zeilen aus den Tokens von ATree.</summary>
    procedure Build(ATree: TSyntaxTree; ALineCount: Integer);
    /// <summary>Markiert die Zeilen von AToken als Code bzw. Kommentar.</summary>
    procedure MarkLines(const AToken: TPascalToken);
    /// <summary>Region bzw. Conditional, wenn AFirst..ALast in einer Klammer liegt, eine nur zur Hälfte enthält
    /// oder ACondition gesetzt ist; sonst None.</summary>
    function ReasonFor(AFirst, ALast: Integer; const ACondition: string): TMethodStayReason;
  end;

/// <summary>Zählt die Direktive ADirective in Zeile ALine als Öffnen oder Schließen einer Klammer.</summary>
procedure CountDirective(const ADirective: string; ALine: Integer; var ACondDelta, ARegionDelta: TArray<Integer>);
begin
  if MatchStr(ADirective, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
  begin
    Inc(ACondDelta[ALine]);
  end
  else if MatchStr(ADirective, ['ENDIF', 'IFEND']) then
  begin
    Dec(ACondDelta[ALine]);
  end
  else if ADirective = 'REGION' then
  begin
    Inc(ARegionDelta[ALine]);
  end
  else if ADirective = 'ENDREGION' then
  begin
    Dec(ARegionDelta[ALine]);
  end;
end;

procedure TLineMarks.MarkLines(const AToken: TPascalToken);
var
  mLine: Integer;
begin
  for mLine := AToken.StartPos.Line to AToken.EndPos.Line do
  begin
    if AToken.Kind = TPascalTokenKind.Comment then
    begin
      Comment[mLine] := True;
    end
    else
    begin
      Code[mLine] := True;
    end;
  end;
end;

procedure TLineMarks.Build(ATree: TSyntaxTree; ALineCount: Integer);
var
  mCondDelta, mRegionDelta: TArray<Integer>;
  mToken: TPascalToken;
  mLine: Integer;
begin
  SetLength(Code, ALineCount);
  SetLength(Comment, ALineCount);
  SetLength(mCondDelta, ALineCount + 1);
  SetLength(mRegionDelta, ALineCount + 1);
  for mToken in ATree.Tokens do
  begin
    if (mToken.StartPos.Line < 0) or (mToken.EndPos.Line >= ALineCount) then
    begin
      Continue;
    end;
    MarkLines(mToken);
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      CountDirective(TPascalLexer.DirectiveName(mToken.Text), mToken.StartPos.Line, mCondDelta, mRegionDelta);
    end;
  end;
  SetLength(CondAt, ALineCount + 1);
  SetLength(RegionAt, ALineCount + 1);
  for mLine := 1 to ALineCount do
  begin
    CondAt[mLine] := CondAt[mLine - 1] + mCondDelta[mLine - 1];
    RegionAt[mLine] := RegionAt[mLine - 1] + mRegionDelta[mLine - 1];
  end;
end;

function TLineMarks.ReasonFor(AFirst, ALast: Integer; const ACondition: string): TMethodStayReason;
begin
  if (RegionAt[AFirst] > 0) or (RegionAt[ALast + 1] <> RegionAt[AFirst]) then
  begin
    Result := TMethodStayReason.Region;
  end
  else if (CondAt[AFirst] > 0) or (CondAt[ALast + 1] <> CondAt[AFirst]) or (ACondition <> '') then
  begin
    Result := TMethodStayReason.Conditional;
  end
  else
  begin
    Result := TMethodStayReason.None;
  end;
end;

/// <summary>Teilt der Rumpf ARange eine Zeile mit anderem Code? Vor dem Kopf darf höchstens "class" stehen,
/// hinter "end;" höchstens ein Kommentar.</summary>
function SharesLine(const ALines: TArray<string>; const ARange: TTextRange): Boolean;
var
  mRest: string;
begin
  mRest := LowerCase(Trim(Copy(ALines[ARange.StartPos.Line], 1, ARange.StartPos.Character)));
  if (mRest <> '') and (mRest <> 'class') then
  begin
    Exit(True);
  end;
  mRest := Trim(Copy(ALines[ARange.EndPos.Line], ARange.EndPos.Character + 1, MaxInt));
  if StartsStr(';', mRest) then
  begin
    mRest := Trim(Copy(mRest, 2, MaxInt));
  end;
  Result := (mRest <> '') and not StartsStr('//', mRest);
end;

/// <summary>Rumpf der Methode AMethod mit Kommentaren direkt darüber; markiert, ob er stehen bleiben muss.</summary>
function BlockOf(const AMethod: TDeclaredMethod; const ALines: TArray<string>; const AMarks: TLineMarks): TBlock;
begin
  Result := Default(TBlock);
  Result.TypeName := AMethod.TypeName;
  Result.Name := AMethod.Declaration.Name;
  Result.TypeOrder := AMethod.TypeOrder;
  Result.DeclarationOrder := AMethod.DeclarationOrder;
  Result.Header := AMethod.Body.Range.StartPos.Line;
  Result.Last := AMethod.Body.Range.EndPos.Line;
  Result.First := Result.Header;
  while (Result.First > 0) and AMarks.Comment[Result.First - 1] and not AMarks.Code[Result.First - 1] do
  begin
    Dec(Result.First);
  end;
  Result.Reason := AMarks.ReasonFor(Result.First, Result.Last, AMethod.Body.Condition);
  if (Result.Reason = TMethodStayReason.None) and SharesLine(ALines, AMethod.Body.Range) then
  begin
    Result.Reason := TMethodStayReason.SharedLine;
  end;
  Result.Fixed := Result.Reason <> TMethodStayReason.None;
end;

/// <summary>Hält ABlock fest; ohne anderen Grund, weil er eine Zeile teilt.</summary>
procedure FixShared(var ABlock: TBlock);
begin
  ABlock.Fixed := True;
  if ABlock.Reason = TMethodStayReason.None then
  begin
    ABlock.Reason := TMethodStayReason.SharedLine;
  end;
end;

/// <summary>Rümpfe (nach Zeilen geordnet), die sich Zeilen teilen, bleiben beide stehen.</summary>
procedure FixSharedLines(var ABlocks: TBlocks);
var
  mIndex: Integer;
begin
  for mIndex := 1 to High(ABlocks) do
  begin
    if ABlocks[mIndex].First <= ABlocks[mIndex - 1].Last then
    begin
      ABlocks[mIndex].First := ABlocks[mIndex].Header;
    end;
    if ABlocks[mIndex].First <= ABlocks[mIndex - 1].Last then
    begin
      FixShared(ABlocks[mIndex]);
      FixShared(ABlocks[mIndex - 1]);
    end;
  end;
end;

/// <summary>Die Rümpfe deklarierter Methoden mit ihrem Bereich; markiert, was stehen bleiben muss.</summary>
function CollectBlocks(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>): TBlocks;
var
  mMarks: TLineMarks;
  mMethod: TDeclaredMethod;
begin
  Result := nil;
  mMarks := Default(TLineMarks);
  mMarks.Build(ATree, Length(ALines));
  for mMethod in TClassCompletion.DeclaredMethods(ATree, AText) do
  begin
    if mMethod.HasBody and (mMethod.Body.Range.EndPos.Line <= High(ALines)) then
    begin
      Result := Result + [BlockOf(mMethod, ALines, mMarks)];
    end;
  end;
  Result := ByLine(Result);
  FixSharedLines(Result);
end;

function BlockLines(const ALines: TArray<string>; const ABlock: TBlock): TArray<string>;
begin
  Result := Copy(ALines, ABlock.First, ABlock.Last - ABlock.First + 1);
end;

/// <summary>Eine Änderung vom alten zum neuen Zeilenstand über den Bereich, in dem sie sich unterscheiden.
/// </summary>
function LinesEdit(const AOld, ANew: TArray<string>; const ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  Prefix, Suffix, Index: Integer;
  Text: string;
begin
  AEdit := Default(TTextEdit);
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix] = ANew[Prefix]) do
  begin
    Inc(Prefix);
  end;
  if (Prefix = Length(AOld)) and (Prefix = Length(ANew)) then
  begin
    Exit(False);
  end;
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[High(AOld) - Suffix] = ANew[High(ANew) - Suffix]) do
  begin
    Inc(Suffix);
  end;
  if Suffix > 0 then
  begin
    Text := '';
    for Index := Prefix to High(ANew) - Suffix do
    begin
      Text := Text + ANew[Index] + ALineBreak;
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(Prefix, 0, Length(AOld) - Suffix, 0), Text);
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(0, 0, High(AOld), Length(AOld[High(AOld)])),
      TTextLines.JoinLines(ANew, ALineBreak));
  end;
  Result := True;
end;

function MoveOf(const ABlock: TBlock; ADelta, ANewLine: Integer): TMethodMove;
begin
  Result := Default(TMethodMove);
  Result.TypeName := ABlock.TypeName;
  Result.Name := ABlock.Name;
  Result.Line := ABlock.Header;
  Result.NewLine := ANewLine;
  Result.Size := ABlock.Last - ABlock.Header + 1;
  Result.Delta := ADelta;
  Result.Fixed := ABlock.Fixed;
  Result.Reason := ABlock.Reason;
end;

{ TMethodOrder }

class function TMethodOrder.PlacementName(APlacement: TMethodPlacement): string;
begin
  case APlacement of
    TMethodPlacement.Off:
      Result := 'off';
    TMethodPlacement.Alphabetical:
      Result := 'alphabetical';
  else
    Result := 'declaration';
  end;
end;

class function TMethodOrder.PlacementOf(const AName: string): TMethodPlacement;
begin
  if SameText(AName, 'off') then
  begin
    Result := TMethodPlacement.Off;
  end
  else if SameText(AName, 'alphabetical') then
  begin
    Result := TMethodPlacement.Alphabetical;
  end
  else
  begin
    Result := TMethodPlacement.Declaration;
  end;
end;

class function TMethodOrder.ReasonName(AReason: TMethodStayReason): string;
begin
  case AReason of
    TMethodStayReason.Region:
      Result := 'region';
    TMethodStayReason.Conditional:
      Result := 'ifdef';
    TMethodStayReason.SharedLine:
      Result := 'line';
  else
    Result := '';
  end;
end;

/// <summary>Rümpfe, die nicht stehen bleiben müssen.</summary>
function MovableOf(const ABlocks: TBlocks): TBlocks;
var
  mBlock: TBlock;
begin
  Result := nil;
  for mBlock in ABlocks do
  begin
    if not mBlock.Fixed then
    begin
      Result := Result + [mBlock];
    end;
  end;
end;

/// <summary>Zeilen, in denen jeder Platz ASlots[I] den Rumpf ATarget[I] bekommt; ATargetLines: dessen neue
/// Kopfzeile.</summary>
function Rearranged(const ALines: TArray<string>; const ASlots, ATarget: TBlocks;
  out ATargetLines: TArray<Integer>): TArray<string>;
var
  mLine, mSlot: Integer;
begin
  Result := nil;
  SetLength(ATargetLines, Length(ATarget));
  mLine := 0;
  mSlot := 0;
  while mLine < Length(ALines) do
  begin
    if (mSlot < Length(ASlots)) and (mLine = ASlots[mSlot].First) then
    begin
      ATargetLines[mSlot] := Length(Result) + ATarget[mSlot].Header - ATarget[mSlot].First;
      Result := Result + BlockLines(ALines, ATarget[mSlot]);
      mLine := ASlots[mSlot].Last + 1;
      Inc(mSlot);
    end
    else
    begin
      Result := Result + [ALines[mLine]];
      Inc(mLine);
    end;
  end;
end;

/// <summary>Verschobene Rümpfe in der neuen Reihenfolge, danach die stehen bleibenden aus ABlocks.</summary>
function ArrangeMoves(const ABlocks, ASlots, ATarget: TBlocks; const ATargetLines: TArray<Integer>):
  TArray<TMethodMove>;
var
  mIndex, mFrom: Integer;
  mBlock: TBlock;
begin
  Result := nil;
  for mIndex := 0 to High(ATarget) do
  begin
    mFrom := IndexOfBlock(ASlots, ATarget[mIndex]);
    if mFrom <> mIndex then
    begin
      Result := Result + [MoveOf(ATarget[mIndex], mIndex - mFrom, ATargetLines[mIndex])];
    end;
  end;
  for mBlock in ABlocks do
  begin
    if mBlock.Fixed then
    begin
      Result := Result + [MoveOf(mBlock, 0, -1)];
    end;
  end;
end;

class function TMethodOrder.Arrange(ATree: TSyntaxTree; const AText: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
var
  mLines, mNewLines: TArray<string>;
  mBlocks, mSlots, mTarget: TBlocks;
  mTargetLines: TArray<Integer>;
  mEdit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (APlacement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  mBlocks := CollectBlocks(ATree, AText, mLines);
  mSlots := MovableOf(mBlocks);
  mTarget := Sorted(mSlots, APlacement);
  // Jeder Platz bekommt den Rumpf, der in der Ordnung an seiner Stelle steht.
  mNewLines := Rearranged(mLines, mSlots, mTarget, mTargetLines);
  if LinesEdit(mLines, mNewLines, TTextLines.LineBreakOf(AText), mEdit) then
  begin
    Result.Edits := [mEdit];
    Result.Moves := ArrangeMoves(mBlocks, mSlots, mTarget, mTargetLines);
  end;
end;

type
  /// <summary>Setzt neue Rümpfe an ihre Stelle (PlaceNew).</summary>
  TNewPlacement = record
    Lines: TArray<string>;
    Placement: TMethodPlacement;
    /// <summary>Vorhandene und neue verschiebbare Rümpfe; News nach Ordnung.</summary>
    Existing, News: TBlocks;
    /// <summary>Alle verschiebbaren Rümpfe nach Zeilen.</summary>
    Movable: TBlocks;
    /// <summary>Ziel und ob verschoben, je neuem Rumpf.</summary>
    Anchors: TArray<TAnchor>;
    Moved: TArray<Boolean>;
    /// <summary>Teilt die verschiebbaren Rümpfe in vorhandene und gegenüber ABefore neue.</summary>
    procedure Split(const ABlocks: TBlocks; const ABefore: string);
    /// <summary>Neu: Kopfzeile kam in AKnown nicht vor, endet mit end und umschließt keinen bekannten Kopf.</summary>
    function IsFresh(const ABlock: TBlock; AKnown: TDictionary<string, Boolean>): Boolean;
    /// <summary>Spätester vorhandener Rumpf vor ANew desselben (ASameType) bzw. eines früheren Typs; -1 ohne.
    /// </summary>
    function LatestBefore(const ANew: TBlock; ASameType: Boolean): Integer;
    /// <summary>Frühester vorhandener Rumpf hinter ANew desselben (ASameType) bzw. eines späteren Typs; -1 ohne.
    /// </summary>
    function EarliestAfter(const ANew: TBlock; ASameType: Boolean): Integer;
    /// <summary>Ziel für ANew: hinter den nächstliegenden davor desselben Typs, sonst vor den nächsten danach; bei
    /// einem Typ ohne Rümpfe hinter den letzten eines früheren, sonst vor den ersten eines späteren Typs.</summary>
    function AnchorFor(const ANew: TBlock): TAnchor;
    /// <summary>Ordnet die neuen Rümpfe und bestimmt ihre Ziele.</summary>
    procedure Anchor;
    /// <summary>Neue Rümpfe ab AIndex mit demselben Ziel wie der an AIndex.</summary>
    function GroupOf(AIndex: Integer): TBlocks;
    /// <summary>Steht die Gruppe des neuen Rumpfs AIndex schon direkt am Ziel?</summary>
    function InPlace(AIndex: Integer; const AGroup: TBlocks): Boolean;
    /// <summary>Gruppen je Ziel; eine Gruppe, die schon direkt am Ziel steht, bleibt.</summary>
    procedure KeepGroupsInPlace;
    /// <summary>Neuer Text: verschobene Rümpfe samt folgender Leerzeilen heraus, am Ziel mit Leerzeile hinein.
    /// </summary>
    function NewLines: TArray<string>;
    /// <summary>Verschobene neue Rümpfe mit Ziel ABlock davor bzw. dahinter (AAfter).</summary>
    function AnchoredAt(const ABlock: TBlock; AAfter: Boolean): TBlocks;
    /// <summary>Reihenfolge danach: die übrigen Rümpfe, die verschobenen an ihrem Ziel.</summary>
    function FinalOrder: TBlocks;
    /// <summary>Verschiebungen der neuen Rümpfe im Text ANewLines.</summary>
    function Moves(const ANewLines: TArray<string>): TArray<TMethodMove>;
  end;

function SameAnchor(const A, B: TAnchor): Boolean;
begin
  Result := (A.Block = B.Block) and (A.After = B.After);
end;

function TNewPlacement.IsFresh(const ABlock: TBlock; AKnown: TDictionary<string, Boolean>): Boolean;
var
  mLine: Integer;
begin
  Result := not AKnown.ContainsKey(Trim(Lines[ABlock.Header])) and StartsText('end', Trim(Lines[ABlock.Last]));
  for mLine := ABlock.Header + 1 to ABlock.Last do
  begin
    if Result and IsRoutineHeader(Lines[mLine]) and AKnown.ContainsKey(Trim(Lines[mLine])) then
    begin
      Result := False;
    end;
  end;
end;

procedure TNewPlacement.Split(const ABlocks: TBlocks; const ABefore: string);
var
  mKnown: TDictionary<string, Boolean>;
  mLine: string;
  mBlock: TBlock;
begin
  Existing := nil;
  News := nil;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mLine in TTextLines.SplitLines(ABefore) do
    begin
      mKnown.AddOrSetValue(Trim(mLine), True);
    end;
    for mBlock in MovableOf(ABlocks) do
    begin
      if IsFresh(mBlock, mKnown) then
      begin
        News := News + [mBlock];
        News[High(News)].New := True;
      end
      else
      begin
        Existing := Existing + [mBlock];
      end;
    end;
  finally
    mKnown.Free;
  end;
end;

function TNewPlacement.LatestBefore(const ANew: TBlock; ASameType: Boolean): Integer;
var
  mCandidate: Integer;
  mFits: Boolean;
begin
  Result := -1;
  for mCandidate := 0 to High(Existing) do
  begin
    if ASameType then
    begin
      mFits := (Existing[mCandidate].TypeOrder = ANew.TypeOrder) and Before(Existing[mCandidate], ANew, Placement);
    end
    else
    begin
      mFits := Existing[mCandidate].TypeOrder < ANew.TypeOrder;
    end;
    if mFits and ((Result < 0) or Before(Existing[Result], Existing[mCandidate], Placement)) then
    begin
      Result := mCandidate;
    end;
  end;
end;

function TNewPlacement.EarliestAfter(const ANew: TBlock; ASameType: Boolean): Integer;
var
  mCandidate: Integer;
  mFits: Boolean;
begin
  Result := -1;
  for mCandidate := 0 to High(Existing) do
  begin
    if ASameType then
    begin
      mFits := (Existing[mCandidate].TypeOrder = ANew.TypeOrder) and Before(ANew, Existing[mCandidate], Placement);
    end
    else
    begin
      mFits := Existing[mCandidate].TypeOrder > ANew.TypeOrder;
    end;
    if mFits and ((Result < 0) or Before(Existing[mCandidate], Existing[Result], Placement)) then
    begin
      Result := mCandidate;
    end;
  end;
end;

function TNewPlacement.AnchorFor(const ANew: TBlock): TAnchor;
begin
  Result.After := True;
  Result.Block := LatestBefore(ANew, True);
  if Result.Block >= 0 then
  begin
    Exit;
  end;
  Result.After := False;
  Result.Block := EarliestAfter(ANew, True);
  if Result.Block >= 0 then
  begin
    Exit;
  end;
  Result.After := True;
  Result.Block := LatestBefore(ANew, False);
  if Result.Block >= 0 then
  begin
    Exit;
  end;
  Result.After := False;
  Result.Block := EarliestAfter(ANew, False);
end;

procedure TNewPlacement.Anchor;
var
  mIndex: Integer;
begin
  News := Sorted(News, Placement);
  SetLength(Anchors, Length(News));
  for mIndex := 0 to High(News) do
  begin
    Anchors[mIndex] := AnchorFor(News[mIndex]);
  end;
  Movable := ByLine(Existing + News);
  SetLength(Moved, Length(News));
end;

function TNewPlacement.GroupOf(AIndex: Integer): TBlocks;
var
  mMember: Integer;
begin
  Result := nil;
  for mMember := AIndex to High(News) do
  begin
    if SameAnchor(Anchors[mMember], Anchors[AIndex]) then
    begin
      Result := Result + [News[mMember]];
    end;
  end;
end;

function TNewPlacement.InPlace(AIndex: Integer; const AGroup: TBlocks): Boolean;
var
  mPosition, mMember, mCandidate: Integer;
begin
  mPosition := IndexOfBlock(Movable, Existing[Anchors[AIndex].Block]);
  for mMember := 0 to High(AGroup) do
  begin
    if Anchors[AIndex].After then
    begin
      mCandidate := mPosition + 1 + mMember;
    end
    else
    begin
      mCandidate := mPosition - Length(AGroup) + mMember;
    end;
    if (mCandidate < 0) or (mCandidate > High(Movable)) or (Movable[mCandidate].Header <> AGroup[mMember].Header) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TNewPlacement.KeepGroupsInPlace;
var
  mIndex, mMember: Integer;
  mInPlace: Boolean;
  mAnchor: TAnchor;
begin
  for mIndex := 0 to High(News) do
  begin
    if (Anchors[mIndex].Block < 0) or Moved[mIndex] then
    begin
      Continue;
    end;
    mInPlace := InPlace(mIndex, GroupOf(mIndex));
    mAnchor := Anchors[mIndex];
    for mMember := mIndex to High(News) do
    begin
      if not SameAnchor(Anchors[mMember], mAnchor) then
      begin
        Continue;
      end;
      Moved[mMember] := not mInPlace;
      if mInPlace then
      begin
        Anchors[mMember].Block := -1;
      end;
    end;
  end;
end;

/// <summary>Markiert die Zeilen von ABlock und die Leerzeilen dahinter als entfernt.</summary>
procedure MarkRemoved(const ALines: TArray<string>; const ABlock: TBlock; var ARemoved: TArray<Boolean>);
var
  mLine: Integer;
begin
  for mLine := ABlock.First to ABlock.Last do
  begin
    ARemoved[mLine] := True;
  end;
  mLine := ABlock.Last + 1;
  while (mLine < High(ALines)) and (Trim(ALines[mLine]) = '') do
  begin
    ARemoved[mLine] := True;
    Inc(mLine);
  end;
end;

function TNewPlacement.NewLines: TArray<string>;
var
  mRemoved: TArray<Boolean>;
  mInsertBefore, mInsertAfter: TArray<TArray<string>>;
  mIndex, mLine: Integer;
  mBlock: TBlock;
begin
  SetLength(mRemoved, Length(Lines));
  SetLength(mInsertBefore, Length(Lines));
  SetLength(mInsertAfter, Length(Lines));
  for mIndex := 0 to High(News) do
  begin
    if not Moved[mIndex] then
    begin
      Continue;
    end;
    MarkRemoved(Lines, News[mIndex], mRemoved);
    mBlock := Existing[Anchors[mIndex].Block];
    if Anchors[mIndex].After then
    begin
      mInsertAfter[mBlock.Last] := mInsertAfter[mBlock.Last] + [''] + BlockLines(Lines, News[mIndex]);
    end
    else
    begin
      mInsertBefore[mBlock.First] := mInsertBefore[mBlock.First] + BlockLines(Lines, News[mIndex]) + [''];
    end;
  end;
  Result := nil;
  for mLine := 0 to High(Lines) do
  begin
    Result := Result + mInsertBefore[mLine];
    if not mRemoved[mLine] then
    begin
      Result := Result + [Lines[mLine]];
    end;
    Result := Result + mInsertAfter[mLine];
  end;
end;

function TNewPlacement.AnchoredAt(const ABlock: TBlock; AAfter: Boolean): TBlocks;
var
  mMember: Integer;
begin
  Result := nil;
  for mMember := 0 to High(News) do
  begin
    if Moved[mMember] and (Anchors[mMember].After = AAfter) and
      (Existing[Anchors[mMember].Block].Header = ABlock.Header) then
    begin
      Result := Result + [News[mMember]];
    end;
  end;
end;

function TNewPlacement.FinalOrder: TBlocks;
var
  mBlock: TBlock;
  mIndex: Integer;
begin
  Result := nil;
  for mBlock in Movable do
  begin
    mIndex := IndexOfBlock(News, mBlock);
    if (mIndex < 0) or not Moved[mIndex] then
    begin
      Result := Result + AnchoredAt(mBlock, False) + [mBlock] + AnchoredAt(mBlock, True);
    end;
  end;
end;

function TNewPlacement.Moves(const ANewLines: TArray<string>): TArray<TMethodMove>;
var
  mFinal: TBlocks;
  mIndex, mLine: Integer;
begin
  Result := nil;
  mFinal := FinalOrder;
  for mIndex := 0 to High(mFinal) do
  begin
    if not mFinal[mIndex].New or not Moved[IndexOfBlock(News, mFinal[mIndex])] then
    begin
      Continue;
    end;
    // Der Kopf eines neuen Rumpfs kam vorher nicht vor: seine erste Fundstelle ist die neue Zeile.
    mLine := 0;
    while (mLine < High(ANewLines)) and (ANewLines[mLine] <> Lines[mFinal[mIndex].Header]) do
    begin
      Inc(mLine);
    end;
    Result := Result + [MoveOf(mFinal[mIndex], mIndex - IndexOfBlock(Movable, mFinal[mIndex]), mLine)];
  end;
end;

class function TMethodOrder.PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
var
  mPlacement: TNewPlacement;
  mNewLines: TArray<string>;
  mEdit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (APlacement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  mPlacement := Default(TNewPlacement);
  mPlacement.Placement := APlacement;
  mPlacement.Lines := TTextLines.SplitLines(AText);
  mPlacement.Split(CollectBlocks(ATree, AText, mPlacement.Lines), ABefore);
  if (mPlacement.News = nil) or (mPlacement.Existing = nil) then
  begin
    Exit;
  end;
  mPlacement.Anchor;
  mPlacement.KeepGroupsInPlace;
  mNewLines := mPlacement.NewLines;
  if LinesEdit(mPlacement.Lines, mNewLines, TTextLines.LineBreakOf(AText), mEdit) then
  begin
    Result.Edits := [mEdit];
    Result.Moves := mPlacement.Moves(mNewLines);
  end;
end;

end.
