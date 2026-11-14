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
//
// Grouped (#1836) ordnet je Typ: Lebenszyklus (class constructor, class
// destructor, constructor, destructor, AfterConstruction, BeforeDestruction),
// Getter und Setter als Paar in Reihenfolge der Properties, überschriebene,
// übrige; LifecycleFirst zieht den Lebenszyklus auch bei Declaration und
// Alphabetical vor. Der Kommentar über dem Abschnitt eines Typs ({ TKunde },
// Trennlinie, {$REGION 'TKunde'} … {$ENDREGION}, #1835) gehört zum Typ und
// steht danach vor seinem ersten Rumpf; eine solche Region hält ihre Rümpfe
// nicht fest. PlaceNew legt für einen Typ, dessen Rümpfe alle neu sind, den
// Kommentar in der eingestellten Form an bzw. bringt den der IDE in diese.
//
// Review (Regel method-order, #1840) prüft je Typ, ob seine verschiebbaren
// Rümpfe untereinander in der Ordnung stehen und ob über ihnen ein
// Typkommentar steht, und liefert die Änderungen, die nur diesen Typ ordnen
// bzw. nur seinen Kommentar einfügen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.TypeComments;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ordnung der Rümpfe; Off schaltet Verschieben und Befehl ab (editor.methodPlacement).</summary>
  TMethodPlacement = (Off, Declaration, Alphabetical, Grouped);

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

  /// <summary>Was das Ordnen außer der Ordnung braucht (#1834).</summary>
  TMethodOrderOptions = record
    Placement: TMethodPlacement;
    /// <summary>Lebenszyklus auch bei Declaration und Alphabetical zuerst.</summary>
    LifecycleFirst: Boolean;
    /// <summary>Form des Kommentars, den PlaceNew für Typen mit nur neuen Rümpfen anlegt; Off = keinen.</summary>
    TypeComment: TTypeCommentStyle;
    /// <summary>Breite der Trennlinie; 0 = Vorgabe.</summary>
    LineLength: Integer;
    /// <summary>Nur APlacement, ohne Vorziehen und ohne neuen Kommentar.</summary>
    class function Create(APlacement: TMethodPlacement): TMethodOrderOptions; static;
  end;

  TMethodOrderResult = record
    Edits: TArray<TTextEdit>;
    /// <summary>Verschobene Rümpfe in der neuen Reihenfolge, danach die stehen bleibenden.</summary>
    Moves: TArray<TMethodMove>;
  end;

  /// <summary>Stand eines Typs für die Regel method-order (#1840).</summary>
  TMethodTypeReview = record
    TypeName: string;
    /// <summary>Typname im Kopf des ersten Rumpfs (nach Zeilen).</summary>
    NameRange: TTextRange;
    /// <summary>Ordnet nur die Rümpfe dieses Typs untereinander; nil = sie stehen schon in der Ordnung.</summary>
    OrderEdits: TArray<TTextEdit>;
    /// <summary>Fügt den fehlenden Typkommentar ein; nil = vorhanden oder TypeComment Off.</summary>
    CommentEdits: TArray<TTextEdit>;
    /// <summary>Zeile des einzufügenden Kommentars mit dem Typnamen, z. B. "{ TKunde }"; '' ohne.</summary>
    CommentText: string;
  end;

  TMethodOrder = class
  public
    /// <summary>Ordnet alle Rümpfe der Unit; ohne Edits, wenn alles passt oder APlacement Off ist.</summary>
    class function Arrange(ATree: TSyntaxTree; const AText: string;
      APlacement: TMethodPlacement): TMethodOrderResult; overload; static;
    class function Arrange(ATree: TSyntaxTree; const AText: string;
      const AOptions: TMethodOrderOptions): TMethodOrderResult; overload; static;
    /// <summary>Setzt die gegenüber ABefore neuen Rümpfe an ihre Stelle; ohne Edits, wenn keiner neu ist oder
    /// alle schon passen.</summary>
    class function PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
      APlacement: TMethodPlacement): TMethodOrderResult; overload; static;
    class function PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
      const AOptions: TMethodOrderOptions): TMethodOrderResult; overload; static;
    /// <summary>Je Typ mit Rümpfen (in der Reihenfolge des ersten Rumpfs), ob seine Rümpfe in der Ordnung
    /// stehen und ob ein Typkommentar fehlt (#1840); leer bei APlacement Off.</summary>
    class function Review(ATree: TSyntaxTree; const AText: string;
      const AOptions: TMethodOrderOptions): TArray<TMethodTypeReview>; static;
    /// <summary>off, declaration, alphabetical, grouped.</summary>
    class function PlacementName(APlacement: TMethodPlacement): string; static;
    /// <summary>Unbekannt: Declaration; leer: Grouped (Vorgabe seit #1836).</summary>
    class function PlacementOf(const AName: string): TMethodPlacement; static;
    /// <summary>'', region, ifdef, line.</summary>
    class function ReasonName(AReason: TMethodStayReason): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Math,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.ClassBodies,
  Atlas.Common.Editing.ClassCompletion;

type
  TBlock = record
    TypeName, Name: string;
    TypeOrder, DeclarationOrder: Integer;
    /// <summary>Rang aus TClassBodies.RankOf (#1836).</summary>
    Group, Sub: Integer;
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
  cRoutineWords: array[0..5] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
    'class ');

/// <summary>Entscheidet der Rang (#1836) zwischen A und B desselben Typs? AResult: A kommt zuerst.</summary>
function RankDecides(const A, B: TBlock; const ARule: TMethodOrderOptions; out AResult: Boolean): Boolean;
var
  mLifeA, mLifeB: Boolean;
begin
  AResult := False;
  mLifeA := A.Group = TClassBodies.cGroupLifecycle;
  mLifeB := B.Group = TClassBodies.cGroupLifecycle;
  if ARule.Placement = TMethodPlacement.Grouped then
  begin
    Result := (A.Group <> B.Group) or (A.Sub <> B.Sub);
    AResult := (A.Group < B.Group) or ((A.Group = B.Group) and (A.Sub < B.Sub));
  end
  else
  begin
    Result := ARule.LifecycleFirst and ((mLifeA <> mLifeB) or (mLifeA and (A.Sub <> B.Sub)));
    AResult := (mLifeA and not mLifeB) or (mLifeA and mLifeB and (A.Sub < B.Sub));
  end;
end;

function Before(const A, B: TBlock; const ARule: TMethodOrderOptions): Boolean;
var
  mCompared: Integer;
begin
  if A.TypeOrder <> B.TypeOrder then
  begin
    Exit(A.TypeOrder < B.TypeOrder);
  end;
  if RankDecides(A, B, ARule, Result) then
  begin
    Exit;
  end;
  if ARule.Placement = TMethodPlacement.Alphabetical then
  begin
    mCompared := CompareText(A.Name, B.Name);
    if mCompared <> 0 then
    begin
      Exit(mCompared < 0);
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
function Sorted(const ABlocks: TBlocks; const APlacement: TMethodOrderOptions): TBlocks;
var
  mIndex, mTarget: Integer;
  mItem: TBlock;
begin
  Result := Copy(ABlocks);
  for mIndex := 1 to High(Result) do
  begin
    mItem := Result[mIndex];
    mTarget := mIndex - 1;
    while (mTarget >= 0) and Before(mItem, Result[mTarget], APlacement) do
    begin
      Result[mTarget + 1] := Result[mTarget];
      Dec(mTarget);
    end;
    Result[mTarget + 1] := mItem;
  end;
end;

function ByLine(const ABlocks: TBlocks): TBlocks;
var
  mIndex, mTarget: Integer;
  mItem: TBlock;
begin
  Result := Copy(ABlocks);
  for mIndex := 1 to High(Result) do
  begin
    mItem := Result[mIndex];
    mTarget := mIndex - 1;
    while (mTarget >= 0) and (mItem.First < Result[mTarget].First) do
    begin
      Result[mTarget + 1] := Result[mTarget];
      Dec(mTarget);
    end;
    Result[mTarget + 1] := mItem;
  end;
end;

function IndexOfBlock(const ABlocks: TBlocks; const ABlock: TBlock): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ABlocks) do
  begin
    if ABlocks[mIndex].Header = ABlock.Header then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function IsRoutineHeader(const ALine: string): Boolean;
var
  mWord: string;
  mLower: string;
begin
  mLower := LowerCase(Trim(ALine));
  for mWord in cRoutineWords do
  begin
    if StartsStr(mWord, mLower) then
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
    /// <summary>Liest die Merkmale der ALineCount Zeilen aus den Tokens von ATree; Direktiven in Zeilen mit
    /// AIgnore (Regionen als Typkommentar, #1835) zählen nicht.</summary>
    procedure Build(ATree: TSyntaxTree; ALineCount: Integer; const AIgnore: TArray<Boolean>);
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

procedure TLineMarks.Build(ATree: TSyntaxTree; ALineCount: Integer; const AIgnore: TArray<Boolean>);
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
    if (mToken.Kind = TPascalTokenKind.Directive) and
      ((mToken.StartPos.Line > High(AIgnore)) or not AIgnore[mToken.StartPos.Line]) then
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
function BlockOf(const AMethod: TDeclaredMethod; const ALines: TArray<string>; const AMarks: TLineMarks;
  const ARank: TMethodRank): TBlock;
begin
  Result := Default(TBlock);
  Result.Group := ARank.Group;
  Result.Sub := ARank.Sub;
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

/// <summary>Rang der Methode AMethod (#1836); die Form ihres Typs liest AShapes einmal je Typ.</summary>
function RankOfMethod(const AMethod: TDeclaredMethod; const AUnit: TUnitIndex; const ALines: TArray<string>;
  AShapes: TDictionary<string, TTypeShape>): TMethodRank;
var
  mShape: TTypeShape;
begin
  if not AShapes.TryGetValue(LowerCase(AMethod.TypeName), mShape) then
  begin
    mShape := TTypeShape.Read(AUnit, ALines, AMethod.TypeName);
    AShapes.Add(LowerCase(AMethod.TypeName), mShape);
  end;
  Result := TClassBodies.RankOf(mShape, TClassBodies.DeclarationText(ALines, AMethod.Declaration.Range),
    AMethod.Declaration.Name);
end;

/// <summary>Die Rümpfe deklarierter Methoden mit ihrem Bereich und Rang; markiert, was stehen bleiben muss.
/// Direktiven in Zeilen mit AIgnore halten nichts fest.</summary>
function CollectBlocks(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>;
  const AIgnore: TArray<Boolean>): TBlocks;
var
  mMarks: TLineMarks;
  mMethod: TDeclaredMethod;
  mUnit: TUnitIndex;
  mShapes: TDictionary<string, TTypeShape>;
begin
  Result := nil;
  mMarks := Default(TLineMarks);
  mMarks.Build(ATree, Length(ALines), AIgnore);
  mUnit := TIndexExtractor.Extract(ATree, '');
  mShapes := TDictionary<string, TTypeShape>.Create;
  try
    for mMethod in TClassCompletion.DeclaredMethods(ATree, AText) do
    begin
      if mMethod.HasBody and (mMethod.Body.Range.EndPos.Line <= High(ALines)) then
      begin
        Result := Result + [BlockOf(mMethod, ALines, mMarks, RankOfMethod(mMethod, mUnit, ALines, mShapes))];
      end;
    end;
  finally
    mShapes.Free;
  end;
  Result := ByLine(Result);
  FixSharedLines(Result);
end;

type
  /// <summary>Kommentar über dem Abschnitt eines Typs beim Ordnen (#1835).</summary>
  THeader = record
    TypeName: string;
    /// <summary>Fundstelle im alten Text; ohne bei einem neu angelegten.</summary>
    Comment: TTypeComment;
    /// <summary>Leerzeile hinter dem Kopf bzw. vor {$ENDREGION} im alten Text (fällt mit weg).</summary>
    OldGapAfter, OldGapBefore: Boolean;
    /// <summary>Kopfzeilen, wie sie wieder eingesetzt werden, und {$ENDREGION} ('' ohne).</summary>
    Lines: TArray<string>;
    EndLine: string;
    GapAfter, GapBefore: Boolean;
  end;

  THeaders = TArray<THeader>;

  /// <summary>Neuer Text mit der alten Zeile je Zeile (-1 = eingefügt).</summary>
  TOrderText = record
    Lines: TArray<string>;
    Origins: TArray<Integer>;
    procedure Add(const ALine: string; AOrigin: Integer);
    procedure AddBlock(const ALines: TArray<string>; const ABlock: TBlock);
    /// <summary>Stelle der alten Zeile AOrigin; -1 ohne.</summary>
    function IndexOf(AOrigin: Integer): Integer;
    procedure Insert(AIndex: Integer; const ALines: TArray<string>);
  end;

  /// <summary>Einfügung eines Kommentarteils an einer Stelle des neuen Texts.</summary>
  THeaderInsert = record
    Index: Integer;
    /// <summary>Ende einer Region: kommt bei gleicher Stelle vor den Kopf des nächsten Typs.</summary>
    RegionEnd: Boolean;
    Lines: TArray<string>;
  end;

procedure TOrderText.Add(const ALine: string; AOrigin: Integer);
begin
  Lines := Lines + [ALine];
  Origins := Origins + [AOrigin];
end;

procedure TOrderText.AddBlock(const ALines: TArray<string>; const ABlock: TBlock);
var
  mLine: Integer;
begin
  for mLine := ABlock.First to ABlock.Last do
  begin
    Add(ALines[mLine], mLine);
  end;
end;

function TOrderText.IndexOf(AOrigin: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Origins) do
  begin
    if Origins[mIndex] = AOrigin then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TOrderText.Insert(AIndex: Integer; const ALines: TArray<string>);
var
  mOrigins: TArray<Integer>;
  mIndex: Integer;
begin
  SetLength(mOrigins, Length(ALines));
  for mIndex := 0 to High(mOrigins) do
  begin
    mOrigins[mIndex] := -1;
  end;
  Lines := Copy(Lines, 0, AIndex) + ALines + Copy(Lines, AIndex, MaxInt);
  Origins := Copy(Origins, 0, AIndex) + mOrigins + Copy(Origins, AIndex, MaxInt);
end;

function IsBlank(const ALines: TArray<string>; ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine <= High(ALines)) and (Trim(ALines[ALine]) = '');
end;

/// <summary>Erster (nach Zeilen) und letzter Rumpf des Typs ATypeName in ABlocks; False ohne.</summary>
function TypeRange(const ABlocks: TBlocks; const ATypeName: string; out AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  AFirst := -1;
  ALast := -1;
  for mIndex := 0 to High(ABlocks) do
  begin
    if not SameText(ABlocks[mIndex].TypeName, ATypeName) then
    begin
      Continue;
    end;
    if (AFirst < 0) or (ABlocks[mIndex].First < ABlocks[AFirst].First) then
    begin
      AFirst := mIndex;
    end;
    if (ALast < 0) or (ABlocks[mIndex].Last > ABlocks[ALast].Last) then
    begin
      ALast := mIndex;
    end;
  end;
  Result := AFirst >= 0;
end;

/// <summary>Liegen in der Region AComment nur Rümpfe von ATypeName?</summary>
function RegionOnlyOf(const ABlocks: TBlocks; const AComment: TTypeComment; const ATypeName: string): Boolean;
var
  mBlock: TBlock;
begin
  for mBlock in ABlocks do
  begin
    if (mBlock.Header > AComment.First) and (mBlock.Header < AComment.RegionEnd) and
      not SameText(mBlock.TypeName, ATypeName) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Kommentar über dem ersten Rumpf ABlocks[AFirst]: getrennt durch Leerzeilen oder als oberster Teil der
/// Kommentare, die am Rumpf hängen (dann beginnt der Rumpf danach).</summary>
function CommentAbove(const ALines: TArray<string>; var ABlocks: TBlocks; AFirst, ALast: Integer;
  const ATypeName: string): TTypeComment;
var
  mLine: Integer;
begin
  Result := TTypeComments.Find(ALines, ABlocks[AFirst].First, ABlocks[ALast].Last, ATypeName);
  mLine := ABlocks[AFirst].First + 1;
  while not Result.Found and (mLine <= ABlocks[AFirst].Header) do
  begin
    Result := TTypeComments.Find(ALines, mLine, ABlocks[ALast].Last, ATypeName);
    if Result.Found and ((Result.Last <> mLine - 1) or (Result.First < ABlocks[AFirst].First)) then
    begin
      Result := TTypeComment.None;
    end;
    Inc(mLine);
  end;
  if Result.Found and (Result.Last >= ABlocks[AFirst].First) then
  begin
    ABlocks[AFirst].First := Result.Last + 1;
  end;
end;

function HeaderOf(const ALines: TArray<string>; const ATypeName: string; const AComment: TTypeComment): THeader;
begin
  Result := Default(THeader);
  Result.TypeName := ATypeName;
  Result.Comment := AComment;
  Result.Lines := Copy(ALines, AComment.First, AComment.Last - AComment.First + 1);
  Result.OldGapAfter := IsBlank(ALines, AComment.Last + 1);
  Result.GapAfter := Result.OldGapAfter;
  if AComment.Style = TTypeCommentStyle.Region then
  begin
    Result.EndLine := ALines[AComment.RegionEnd];
    Result.OldGapBefore := IsBlank(ALines, AComment.RegionEnd - 1);
    Result.GapBefore := Result.OldGapBefore;
  end;
end;

/// <summary>Kommentare über den Abschnitten der Typen in ABlocks; setzt den Anfang eines Rumpfs hinter einen
/// Kommentar, der an ihm hängt.</summary>
function DetectHeaders(const ALines: TArray<string>; var ABlocks: TBlocks): THeaders;
var
  mDone: TDictionary<string, Boolean>;
  mBlock: TBlock;
  mFirst, mLast: Integer;
  mComment: TTypeComment;
begin
  Result := nil;
  mDone := TDictionary<string, Boolean>.Create;
  try
    for mBlock in Copy(ABlocks) do
    begin
      if mDone.ContainsKey(LowerCase(mBlock.TypeName)) then
      begin
        Continue;
      end;
      mDone.Add(LowerCase(mBlock.TypeName), True);
      TypeRange(ABlocks, mBlock.TypeName, mFirst, mLast);
      mComment := CommentAbove(ALines, ABlocks, mFirst, mLast, mBlock.TypeName);
      if mComment.Found and ((mComment.Style <> TTypeCommentStyle.Region) or
        RegionOnlyOf(ABlocks, mComment, mBlock.TypeName)) then
      begin
        Result := Result + [HeaderOf(ALines, mBlock.TypeName, mComment)];
      end;
    end;
  finally
    mDone.Free;
  end;
end;

/// <summary>Zeilen der Regionen, die Typkommentare sind; nil ohne.</summary>
function IgnoreOf(const AHeaders: THeaders; ALineCount: Integer): TArray<Boolean>;
var
  mHeader: THeader;
begin
  Result := nil;
  for mHeader in AHeaders do
  begin
    if mHeader.Comment.Style = TTypeCommentStyle.Region then
    begin
      SetLength(Result, ALineCount);
      Result[mHeader.Comment.First] := True;
      Result[mHeader.Comment.RegionEnd] := True;
    end;
  end;
end;

/// <summary>Zeilen der alten Kommentare (mit ihrer Leerzeile), die beim Neuaufbau wegfallen.</summary>
function SkipOf(const AHeaders: THeaders; ALineCount: Integer): TArray<Boolean>;
var
  mHeader: THeader;
  mLine: Integer;
begin
  SetLength(Result, ALineCount);
  for mHeader in AHeaders do
  begin
    if not mHeader.Comment.Found then
    begin
      Continue;
    end;
    for mLine := mHeader.Comment.First to mHeader.Comment.Last do
    begin
      Result[mLine] := True;
    end;
    Result[mHeader.Comment.Last + 1] := Result[mHeader.Comment.Last + 1] or mHeader.OldGapAfter;
    if mHeader.Comment.RegionEnd >= 0 then
    begin
      Result[mHeader.Comment.RegionEnd] := True;
      Result[mHeader.Comment.RegionEnd - 1] := Result[mHeader.Comment.RegionEnd - 1] or mHeader.OldGapBefore;
    end;
  end;
end;

/// <summary>Stelle des ersten (AFirst) bzw. hinter dem letzten Rumpf von ATypeName im neuen Text; -1 ohne.</summary>
function TypeEdge(const AText: TOrderText; const ABlocks: TBlocks; const ATypeName: string; AFirst: Boolean): Integer;
var
  mBlock: TBlock;
  mIndex: Integer;
begin
  Result := -1;
  for mBlock in ABlocks do
  begin
    if not SameText(mBlock.TypeName, ATypeName) then
    begin
      Continue;
    end;
    if AFirst then
    begin
      mIndex := AText.IndexOf(mBlock.First);
      if (mIndex >= 0) and ((Result < 0) or (mIndex < Result)) then
      begin
        Result := mIndex;
      end;
    end
    else
    begin
      Result := Max(Result, AText.IndexOf(mBlock.Last) + 1);
    end;
  end;
end;

function InsertOf(AIndex: Integer; ARegionEnd: Boolean; const ALines: TArray<string>): THeaderInsert;
begin
  Result.Index := AIndex;
  Result.RegionEnd := ARegionEnd;
  Result.Lines := ALines;
end;

/// <summary>Einfügungen der Kommentare AHeaders vor den ersten bzw. hinter den letzten Rumpf ihres Typs.</summary>
function HeaderInserts(const AText: TOrderText; const AHeaders: THeaders; const ABlocks: TBlocks):
  TArray<THeaderInsert>;
var
  mHeader: THeader;
  mIndex: Integer;
  mLines: TArray<string>;
begin
  Result := nil;
  for mHeader in AHeaders do
  begin
    mIndex := TypeEdge(AText, ABlocks, mHeader.TypeName, True);
    if (mIndex < 0) or (mHeader.Lines = nil) then
    begin
      Continue;
    end;
    mLines := mHeader.Lines;
    if mHeader.GapAfter then
    begin
      mLines := mLines + [''];
    end;
    Result := Result + [InsertOf(mIndex, False, mLines)];
    if mHeader.EndLine <> '' then
    begin
      mLines := TArray<string>.Create(mHeader.EndLine);
      if mHeader.GapBefore then
      begin
        mLines := TArray<string>.Create('', mHeader.EndLine);
      end;
      Result := Result + [InsertOf(TypeEdge(AText, ABlocks, mHeader.TypeName, False), True, mLines)];
    end;
  end;
end;

/// <summary>Soll AInsert vor AOther eingesetzt werden? Von hinten nach vorn; bei gleicher Stelle das Ende einer
/// Region zuletzt, damit es vor dem Kopf des nächsten Typs steht.</summary>
function InsertsEarlier(const AInsert, AOther: THeaderInsert): Boolean;
begin
  Result := (AInsert.Index > AOther.Index) or ((AInsert.Index = AOther.Index) and not AInsert.RegionEnd and
    AOther.RegionEnd);
end;

/// <summary>Setzt die Kommentare AHeaders vor den jeweils ersten Rumpf ihres Typs in AText.</summary>
procedure ApplyHeaders(var AText: TOrderText; const AHeaders: THeaders; const ABlocks: TBlocks);
var
  mInserts: TArray<THeaderInsert>;
  mIndex, mTarget: Integer;
  mItem: THeaderInsert;
begin
  mInserts := HeaderInserts(AText, AHeaders, ABlocks);
  for mIndex := 1 to High(mInserts) do
  begin
    mItem := mInserts[mIndex];
    mTarget := mIndex - 1;
    while (mTarget >= 0) and InsertsEarlier(mItem, mInserts[mTarget]) do
    begin
      mInserts[mTarget + 1] := mInserts[mTarget];
      Dec(mTarget);
    end;
    mInserts[mTarget + 1] := mItem;
  end;
  for mItem in mInserts do
  begin
    AText.Insert(mItem.Index, mItem.Lines);
  end;
end;

/// <summary>Rümpfe mit Rang und Kommentaren der Typen; Regionen, die Typkommentare sind, halten nichts fest.
/// </summary>
function PreparedBlocks(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>;
  out AHeaders: THeaders): TBlocks;
var
  mIgnore: TArray<Boolean>;
begin
  Result := CollectBlocks(ATree, AText, ALines, nil);
  AHeaders := DetectHeaders(ALines, Result);
  mIgnore := IgnoreOf(AHeaders, Length(ALines));
  if mIgnore <> nil then
  begin
    Result := CollectBlocks(ATree, AText, ALines, mIgnore);
    AHeaders := DetectHeaders(ALines, Result);
  end;
end;


/// <summary>Eine Änderung vom alten zum neuen Zeilenstand über den Bereich, in dem sie sich unterscheiden.
/// </summary>
function LinesEdit(const AOld, ANew: TArray<string>; const ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mPrefix, mSuffix, mIndex: Integer;
  mText: string;
begin
  AEdit := Default(TTextEdit);
  mPrefix := 0;
  while (mPrefix < Length(AOld)) and (mPrefix < Length(ANew)) and (AOld[mPrefix] = ANew[mPrefix]) do
  begin
    Inc(mPrefix);
  end;
  if (mPrefix = Length(AOld)) and (mPrefix = Length(ANew)) then
  begin
    Exit(False);
  end;
  mSuffix := 0;
  while (mSuffix < Length(AOld) - mPrefix) and (mSuffix < Length(ANew) - mPrefix) and
    (AOld[High(AOld) - mSuffix] = ANew[High(ANew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  if mSuffix > 0 then
  begin
    mText := '';
    for mIndex := mPrefix to High(ANew) - mSuffix do
    begin
      mText := mText + ANew[mIndex] + ALineBreak;
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(mPrefix, 0, Length(AOld) - mSuffix, 0), mText);
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

{ TMethodOrderOptions }

class function TMethodOrderOptions.Create(APlacement: TMethodPlacement): TMethodOrderOptions;
begin
  Result.Placement := APlacement;
  Result.LifecycleFirst := False;
  Result.TypeComment := TTypeCommentStyle.Off;
  Result.LineLength := 0;
end;

{ TMethodOrder }

class function TMethodOrder.PlacementName(APlacement: TMethodPlacement): string;
begin
  case APlacement of
    TMethodPlacement.Off:
      Result := 'off';
    TMethodPlacement.Alphabetical:
      Result := 'alphabetical';
    TMethodPlacement.Grouped:
      Result := 'grouped';
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
  else if (AName = '') or SameText(AName, 'grouped') then
  begin
    Result := TMethodPlacement.Grouped;
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

/// <summary>Neuer Text: jeder Platz ASlots[I] bekommt den Rumpf ATarget[I], die Kommentare der Typen stehen vor
/// ihrem ersten Rumpf.</summary>
function Rearranged(const ALines: TArray<string>; const ABlocks, ASlots, ATarget: TBlocks;
  const AHeaders: THeaders): TOrderText;
var
  mSkip: TArray<Boolean>;
  mLine, mSlot: Integer;
begin
  Result := Default(TOrderText);
  mSkip := SkipOf(AHeaders, Length(ALines));
  mLine := 0;
  mSlot := 0;
  while mLine < Length(ALines) do
  begin
    if (mSlot < Length(ASlots)) and (mLine = ASlots[mSlot].First) then
    begin
      Result.AddBlock(ALines, ATarget[mSlot]);
      mLine := ASlots[mSlot].Last + 1;
      Inc(mSlot);
    end
    else
    begin
      if not mSkip[mLine] then
      begin
        Result.Add(ALines[mLine], mLine);
      end;
      Inc(mLine);
    end;
  end;
  ApplyHeaders(Result, AHeaders, ABlocks);
end;

/// <summary>Verschobene Rümpfe in der neuen Reihenfolge, danach die stehen bleibenden aus ABlocks.</summary>
function ArrangeMoves(const ABlocks, ASlots, ATarget: TBlocks; const AText: TOrderText): TArray<TMethodMove>;
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
      Result := Result + [MoveOf(ATarget[mIndex], mIndex - mFrom, AText.IndexOf(ATarget[mIndex].Header))];
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

/// <summary>Ordnet die verschiebbaren Rümpfe aus ABlocks nach AOptions; die Kommentare AHeaders gehen mit.</summary>
function ArrangeBlocks(const ALines: TArray<string>; const ABlocks: TBlocks; const AHeaders: THeaders;
  const AOptions: TMethodOrderOptions; const ALineBreak: string): TMethodOrderResult;
var
  mSlots, mTarget: TBlocks;
  mText: TOrderText;
  mEdit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  mSlots := MovableOf(ABlocks);
  mTarget := Sorted(mSlots, AOptions);
  // Jeder Platz bekommt den Rumpf, der in der Ordnung an seiner Stelle steht.
  mText := Rearranged(ALines, ABlocks, mSlots, mTarget, AHeaders);
  if LinesEdit(ALines, mText.Lines, ALineBreak, mEdit) then
  begin
    Result.Edits := [mEdit];
    Result.Moves := ArrangeMoves(ABlocks, mSlots, mTarget, mText);
  end;
end;

class function TMethodOrder.Arrange(ATree: TSyntaxTree; const AText: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
begin
  Result := Arrange(ATree, AText, TMethodOrderOptions.Create(APlacement));
end;

class function TMethodOrder.Arrange(ATree: TSyntaxTree; const AText: string;
  const AOptions: TMethodOrderOptions): TMethodOrderResult;
var
  mLines: TArray<string>;
  mBlocks: TBlocks;
  mHeaders: THeaders;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (AOptions.Placement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  mBlocks := PreparedBlocks(ATree, AText, mLines, mHeaders);
  Result := ArrangeBlocks(mLines, mBlocks, mHeaders, AOptions, TTextLines.LineBreakOf(AText));
end;

type
  /// <summary>Setzt neue Rümpfe an ihre Stelle (PlaceNew).</summary>
  TNewPlacement = record
    Lines: TArray<string>;
    Placement: TMethodOrderOptions;
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
    /// <summary>Neuer Text: verschobene Rümpfe samt folgender Leerzeilen heraus, am Ziel mit Leerzeile hinein;
    /// die Kommentare AHeaders der Typen in ABlocks vor ihren ersten Rumpf.</summary>
    function NewText(const AHeaders: THeaders; const ABlocks: TBlocks): TOrderText;
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

function TNewPlacement.NewText(const AHeaders: THeaders; const ABlocks: TBlocks): TOrderText;
var
  mRemoved: TArray<Boolean>;
  mInsertBefore, mInsertAfter: TArray<TBlocks>;
  mIndex, mLine: Integer;
  mBlock: TBlock;
begin
  mRemoved := SkipOf(AHeaders, Length(Lines));
  SetLength(mInsertBefore, Length(Lines));
  SetLength(mInsertAfter, Length(Lines));
  for mIndex := 0 to High(News) do
  begin
    if Moved[mIndex] then
    begin
      MarkRemoved(Lines, News[mIndex], mRemoved);
      mBlock := Existing[Anchors[mIndex].Block];
      if Anchors[mIndex].After then
      begin
        mInsertAfter[mBlock.Last] := mInsertAfter[mBlock.Last] + [News[mIndex]];
      end
      else
      begin
        mInsertBefore[mBlock.First] := mInsertBefore[mBlock.First] + [News[mIndex]];
      end;
    end;
  end;
  Result := Default(TOrderText);
  for mLine := 0 to High(Lines) do
  begin
    for mBlock in mInsertBefore[mLine] do
    begin
      Result.AddBlock(Lines, mBlock);
      Result.Add('', -1);
    end;
    if not mRemoved[mLine] then
    begin
      Result.Add(Lines[mLine], mLine);
    end;
    for mBlock in mInsertAfter[mLine] do
    begin
      Result.Add('', -1);
      Result.AddBlock(Lines, mBlock);
    end;
  end;
  ApplyHeaders(Result, AHeaders, ABlocks);
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

/// <summary>Sind alle Rümpfe von ATypeName in ABlocks neu (ANews)?</summary>
function AllNew(const ABlocks, ANews: TBlocks; const ATypeName: string): Boolean;
var
  mBlock: TBlock;
begin
  for mBlock in ABlocks do
  begin
    if SameText(mBlock.TypeName, ATypeName) and (IndexOfBlock(ANews, mBlock) < 0) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function IndexOfHeader(const AHeaders: THeaders; const ATypeName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AHeaders) do
  begin
    if SameText(AHeaders[mIndex].TypeName, ATypeName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Setzt die Zeilen von AHeader auf die Form AOptions.TypeComment.</summary>
procedure Restyle(var AHeader: THeader; const AOptions: TMethodOrderOptions; const ASummary: string);
begin
  AHeader.Lines := TTypeComments.Header(AOptions.TypeComment, AHeader.TypeName, ASummary, AOptions.LineLength);
  AHeader.EndLine := '';
  AHeader.GapAfter := AOptions.TypeComment <> TTypeCommentStyle.Region;
  AHeader.GapBefore := False;
  if AOptions.TypeComment = TTypeCommentStyle.Region then
  begin
    AHeader.EndLine := TTypeComments.cRegionEndText;
  end;
end;

/// <summary>Typen, deren Rümpfe alle neu sind (Strg+Umschalt+C, Atlas-Aktion): Kommentar in der eingestellten
/// Form anlegen bzw. den vorhandenen (etwa { TKunde } der IDE) in diese bringen.</summary>
procedure FreshHeaders(ATree: TSyntaxTree; const ALines: TArray<string>; const ABlocks, ANews: TBlocks;
  const AOptions: TMethodOrderOptions; var AHeaders: THeaders);
var
  mBlock: TBlock;
  mIndex: Integer;
  mHeader: THeader;
  mUnit: TUnitIndex;
begin
  if AOptions.TypeComment = TTypeCommentStyle.Off then
  begin
    Exit;
  end;
  mUnit := TIndexExtractor.Extract(ATree, '');
  for mBlock in ANews do
  begin
    mIndex := IndexOfHeader(AHeaders, mBlock.TypeName);
    if not AllNew(ABlocks, ANews, mBlock.TypeName) or
      ((mIndex >= 0) and (AHeaders[mIndex].Comment.Style = AOptions.TypeComment)) then
    begin
      Continue;
    end;
    if mIndex < 0 then
    begin
      mHeader := Default(THeader);
      mHeader.TypeName := mBlock.TypeName;
      mHeader.Comment := TTypeComment.None;
      AHeaders := AHeaders + [mHeader];
      mIndex := High(AHeaders);
    end;
    Restyle(AHeaders[mIndex], AOptions, TTypeShape.Read(mUnit, ALines, mBlock.TypeName).Summary);
    // Je Typ nur einmal.
    AHeaders[mIndex].Comment.Style := AOptions.TypeComment;
  end;
end;

{ Review (#1840) }

/// <summary>Kopie von ABlocks, in der nur die Rümpfe von ATypeName (ohne AAll: keine) verschiebbar bleiben.
/// </summary>
function MovableOnly(const ABlocks: TBlocks; const ATypeName: string; AAll: Boolean): TBlocks;
var
  mIndex: Integer;
begin
  Result := Copy(ABlocks);
  for mIndex := 0 to High(Result) do
  begin
    if not AAll or not SameText(Result[mIndex].TypeName, ATypeName) then
    begin
      Result[mIndex].Fixed := True;
    end;
  end;
end;

/// <summary>Kommentar des Typs ATypeName aus AHeaders; leer ohne.</summary>
function HeadersOf(const AHeaders: THeaders; const ATypeName: string): THeaders;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := IndexOfHeader(AHeaders, ATypeName);
  if mIndex >= 0 then
  begin
    Result := TArray<THeader>.Create(AHeaders[mIndex]);
  end;
end;

/// <summary>Steht über den Rümpfen von ATypeName ein Typkommentar in irgendeiner Form (auch eine Region, die
/// Rümpfe anderer Typen umschließt)?</summary>
function HasTypeComment(const ALines: TArray<string>; const ABlocks: TBlocks; const ATypeName: string): Boolean;
var
  mBlocks: TBlocks;
  mFirst, mLast: Integer;
begin
  mBlocks := Copy(ABlocks);
  Result := TypeRange(mBlocks, ATypeName, mFirst, mLast) and
    CommentAbove(ALines, mBlocks, mFirst, mLast, ATypeName).Found;
end;

/// <summary>Bereich von ATypeName im Kopf des Rumpfs ABlock; ohne Fund der Anfang des Kopfs.</summary>
function NameRangeOf(const ALines: TArray<string>; const ABlock: TBlock; const ATypeName: string): TTextRange;
var
  mLine: string;
  mColumn, mLength: Integer;
begin
  mLine := LowerCase(ALines[ABlock.Header]);
  mLength := Length(ATypeName);
  mColumn := Pos(LowerCase(ATypeName) + '.', mLine);
  if mColumn = 0 then
  begin
    // Generische Typen: TListe<T> steht im Kopf auch als TListe<TElement>.
    mLength := Length(SplitString(ATypeName, '<')[0]);
    mColumn := Pos(LowerCase(Copy(ATypeName, 1, mLength)) + '<', mLine);
  end;
  if mColumn = 0 then
  begin
    mColumn := Length(mLine) - Length(TrimLeft(mLine)) + 1;
    mLength := Length(Trim(mLine));
  end;
  Result := TTextRange.Create(ABlock.Header, mColumn - 1, ABlock.Header, mColumn - 1 + mLength);
end;

/// <summary>Zeile des Kommentars AHeader, die den Typnamen nennt; sonst die erste.</summary>
function CommentTextOf(const AHeader: THeader): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in AHeader.Lines do
  begin
    if ContainsText(mLine, AHeader.TypeName) then
    begin
      Exit(Trim(mLine));
    end;
  end;
  if AHeader.Lines <> nil then
  begin
    Result := Trim(AHeader.Lines[0]);
  end;
end;

type
  /// <summary>Prüft die Typen einer Unit für Review.</summary>
  TOrderReview = record
    Lines: TArray<string>;
    LineBreak: string;
    Options: TMethodOrderOptions;
    Blocks: TBlocks;
    Headers: THeaders;
    UnitIndex: TUnitIndex;
    function ReviewOf(const ATypeName: string): TMethodTypeReview;
    procedure AddComment(var AReview: TMethodTypeReview);
  end;

procedure TOrderReview.AddComment(var AReview: TMethodTypeReview);
var
  mHeader: THeader;
begin
  if (Options.TypeComment = TTypeCommentStyle.Off) or HasTypeComment(Lines, Blocks, AReview.TypeName) then
  begin
    Exit;
  end;
  mHeader := Default(THeader);
  mHeader.TypeName := AReview.TypeName;
  mHeader.Comment := TTypeComment.None;
  Restyle(mHeader, Options, TTypeShape.Read(UnitIndex, Lines, AReview.TypeName).Summary);
  AReview.CommentText := CommentTextOf(mHeader);
  AReview.CommentEdits := ArrangeBlocks(Lines, MovableOnly(Blocks, AReview.TypeName, False),
    TArray<THeader>.Create(mHeader), Options, LineBreak).Edits;
end;

function TOrderReview.ReviewOf(const ATypeName: string): TMethodTypeReview;
var
  mFirst, mLast: Integer;
begin
  Result := Default(TMethodTypeReview);
  Result.TypeName := ATypeName;
  TypeRange(Blocks, ATypeName, mFirst, mLast);
  Result.NameRange := NameRangeOf(Lines, Blocks[mFirst], ATypeName);
  Result.OrderEdits := ArrangeBlocks(Lines, MovableOnly(Blocks, ATypeName, True), HeadersOf(Headers, ATypeName),
    Options, LineBreak).Edits;
  AddComment(Result);
end;

class function TMethodOrder.Review(ATree: TSyntaxTree; const AText: string;
  const AOptions: TMethodOrderOptions): TArray<TMethodTypeReview>;
var
  mReview: TOrderReview;
  mDone: TDictionary<string, Boolean>;
  mBlock: TBlock;
begin
  Result := nil;
  if (ATree = nil) or (AOptions.Placement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  mReview := Default(TOrderReview);
  mReview.Options := AOptions;
  mReview.Lines := TTextLines.SplitLines(AText);
  mReview.LineBreak := TTextLines.LineBreakOf(AText);
  mReview.Blocks := PreparedBlocks(ATree, AText, mReview.Lines, mReview.Headers);
  mReview.UnitIndex := TIndexExtractor.Extract(ATree, '');
  mDone := TDictionary<string, Boolean>.Create;
  try
    for mBlock in mReview.Blocks do
    begin
      if mDone.ContainsKey(LowerCase(mBlock.TypeName)) then
      begin
        Continue;
      end;
      mDone.Add(LowerCase(mBlock.TypeName), True);
      Result := Result + [mReview.ReviewOf(mBlock.TypeName)];
    end;
  finally
    mDone.Free;
  end;
end;

class function TMethodOrder.PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
  APlacement: TMethodPlacement): TMethodOrderResult;
begin
  Result := PlaceNew(ATree, AText, ABefore, TMethodOrderOptions.Create(APlacement));
end;

class function TMethodOrder.PlaceNew(ATree: TSyntaxTree; const AText, ABefore: string;
  const AOptions: TMethodOrderOptions): TMethodOrderResult;
var
  mPlacement: TNewPlacement;
  mBlocks: TBlocks;
  mHeaders: THeaders;
  mText: TOrderText;
  mEdit: TTextEdit;
begin
  Result := Default(TMethodOrderResult);
  if (ATree = nil) or (AOptions.Placement = TMethodPlacement.Off) then
  begin
    Exit;
  end;
  mPlacement := Default(TNewPlacement);
  mPlacement.Placement := AOptions;
  mPlacement.Lines := TTextLines.SplitLines(AText);
  mBlocks := PreparedBlocks(ATree, AText, mPlacement.Lines, mHeaders);
  mPlacement.Split(mBlocks, ABefore);
  if mPlacement.News = nil then
  begin
    Exit;
  end;
  FreshHeaders(ATree, mPlacement.Lines, mBlocks, mPlacement.News, AOptions, mHeaders);
  // Nur neue Rümpfe (erste Klasse der Unit): sie untereinander ordnen.
  if mPlacement.Existing = nil then
  begin
    Exit(ArrangeBlocks(mPlacement.Lines, mBlocks, mHeaders, AOptions, TTextLines.LineBreakOf(AText)));
  end;
  mPlacement.Anchor;
  mPlacement.KeepGroupsInPlace;
  mText := mPlacement.NewText(mHeaders, mBlocks);
  if LinesEdit(mPlacement.Lines, mText.Lines, TTextLines.LineBreakOf(AText), mEdit) then
  begin
    Result.Edits := [mEdit];
    Result.Moves := mPlacement.Moves(mText.Lines);
  end;
end;

end.
