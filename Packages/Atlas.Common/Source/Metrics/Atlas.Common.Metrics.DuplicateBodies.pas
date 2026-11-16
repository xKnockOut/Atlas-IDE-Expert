unit Atlas.Common.Metrics.DuplicateBodies;

// Wortgleiche Rümpfe über Units hinweg (Kopien-Prüfung, Regel duplicate-routine-body und --check-duplicates).
//
// Je Routine mit Rumpf ein Fingerabdruck über die normalisierte Token-Folge des Rumpfs: alles hinter dem Kopf bis
// zum Ende der Routine, also auch lokale Deklarationen und lokale Routinen. Normalisiert heißt: ohne Kommentare und
// Leerraum, Bezeichner, Schlüsselwörter und Direktiven ohne Groß-/Kleinschreibung, Zahlen, Strings und Symbole
// unverändert. Name und Parameter der Routine zählen nicht: TA.Show und TB.Show mit gleichem Rumpf sind Kopien.
//
// Find bildet Gruppen gleicher Fingerabdrücke ab einer Mindestzahl von Zeilen, deren Mitglieder in mindestens zwei
// Units liegen; Kopien nur innerhalb einer Unit zählen nicht. Erzeugte Units (IsGenerated) gehören nicht dazu.
// Eine lokale Routine bildet keine eigene Gruppe, wenn alle ihre Fassungen in Routinen stehen, die selbst eine
// Gruppe bilden: Die äußere Gruppe meldet die Kopie schon.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Fingerabdruck des Rumpfs einer Routine.</summary>
  TRoutineBody = record
    /// <summary>Name wie im Kopf (TFoo.Bar); lokale Routinen mit der äußeren davor (TFoo.Bar.Inner).</summary>
    Name: string;
    /// <summary>Zeile des Kopfs, ab 1.</summary>
    Line: Integer;
    /// <summary>Kopf der Routine (vom ersten Token bis zum Ende des Kopfs); dort stehen Treffer der Regel.</summary>
    HeaderRange: TTextRange;
    /// <summary>Zeilen vom ersten bis zum letzten Token des Rumpfs.</summary>
    BodyLines: Integer;
    /// <summary>Fingerabdruck der normalisierten Token-Folge (16 Hex-Ziffern).</summary>
    Hash: string;
    /// <summary>Fingerabdruck der umschließenden Routine; '' für Routinen auf oberster Ebene.</summary>
    OuterHash: string;
  end;

  /// <summary>Die Rümpfe einer Unit.</summary>
  TDuplicateBodyUnit = record
    /// <summary>Pfad, unter dem die Unit gemeldet wird (relativ zur Wurzel, mit „/“).</summary>
    Path: string;
    Bodies: TArray<TRoutineBody>;
    constructor Create(const APath: string; const ABodies: TArray<TRoutineBody>);
  end;

  /// <summary>Eine Fassung eines Rumpfs in einer Gruppe.</summary>
  TDuplicateBodyMember = record
    Path: string;
    Routine: string;
    /// <summary>Zeile des Kopfs, ab 1.</summary>
    Line: Integer;
    /// <summary>"Pfad:Routine", Schlüssel in der Baseline.</summary>
    function Key: string;
  end;

  /// <summary>Routinen mit wortgleichem Rumpf in verschiedenen Units.</summary>
  TDuplicateBodyGroup = record
    Hash: string;
    BodyLines: Integer;
    /// <summary>Nach Pfad und Routine sortiert.</summary>
    Members: TArray<TDuplicateBodyMember>;
  end;

  TDuplicateBodies = record
  public const
    /// <summary>Vorgabe für die Mindestzahl der Zeilen eines Rumpfs.</summary>
    cMinBodyLines = 6;
  public
    /// <summary>Fingerabdrücke aller Routinen mit begin-Rumpf in ATree (ohne asm-Rümpfe und forward/external), nach
    /// Position.</summary>
    class function Bodies(ATree: TSyntaxTree): TArray<TRoutineBody>; static;
    /// <summary>Parst AText und liefert die Fingerabdrücke; nil für erzeugte Units.</summary>
    class function ForText(const AText: string): TArray<TRoutineBody>; static;
    /// <summary>Normalisierte Token-Folge ATokens[AFirst..ALast]: Kommentare fehlen, Bezeichner, Schlüsselwörter und
    /// Direktiven in Kleinbuchstaben, getrennt durch #1.</summary>
    class function Normalized(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string; static;
    /// <summary>64-Bit-Fingerabdruck von AText als 16 Hex-Ziffern (zwei FNV-1a-Läufe über die UTF-16-Zeichen).
    /// </summary>
    class function Fingerprint(const AText: string): string; static;
    /// <summary>Erzeugte Unit: Der Kopf (erste 15 Zeilen) sagt „nicht von Hand ändern“, „do not edit“ oder
    /// „generated“.</summary>
    class function IsGenerated(const AText: string): Boolean; static;
    /// <summary>Gruppen in AUnits mit Rümpfen ab AMinLines Zeilen und Mitgliedern in mindestens zwei Units; nach
    /// Zeilen absteigend, dann nach Fingerabdruck.</summary>
    class function Find(const AUnits: TArray<TDuplicateBodyUnit>; AMinLines: Integer): TArray<TDuplicateBodyGroup>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.TreeCache;

const
  /// <summary>Zeilen am Anfang der Unit, in denen IsGenerated die Marke sucht.</summary>
  cHeaderLines = 15;
  /// <summary>Marken erzeugter Units, in Kleinbuchstaben.</summary>
  cGeneratedMarks: array[0..3] of string = ('nicht von hand', // german-ok: Marke im Kopf erzeugter Units
    'do not edit', 'auto-generated', 'automatically generated');
  cFnvPrime = 16777619;
  cFnvOffset = 2166136261;
  /// <summary>Zweiter Startwert, damit die zweite Hälfte des Fingerabdrucks unabhängig von der ersten ist.</summary>
  cFnvOffsetSecond = 3735928559;

{ TDuplicateBodyUnit }

constructor TDuplicateBodyUnit.Create(const APath: string; const ABodies: TArray<TRoutineBody>);
begin
  Path := APath;
  Bodies := ABodies;
end;

{ TDuplicateBodyMember }

function TDuplicateBodyMember.Key: string;
begin
  Result := Path + ':' + Routine;
end;

{ Hilfen }

/// <summary>Letzte Rumpf-Knoten (Block) von ARoutine; nil ohne begin-Rumpf.</summary>
function BlockOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := ARoutine.ChildCount - 1 downto 0 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.Block then
    begin
      Exit(ARoutine[mIndex]);
    end;
  end;
end;

function QualifiedName(ARoutine: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  Result := ARoutine.Name;
  mParent := ARoutine.Parent;
  while mParent <> nil do
  begin
    if mParent.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := mParent.Name + '.' + Result;
    end;
    mParent := mParent.Parent;
  end;
end;

/// <summary>Routinen mit begin-Rumpf in ATree, äußere vor inneren, sonst nach Position.</summary>
function FindRoutines(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mStack: TStack<TSyntaxNode>;
  mList: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mStack := TStack<TSyntaxNode>.Create;
  mList := TList<TSyntaxNode>.Create;
  try
    mStack.Push(ATree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if (mNode.Kind = TSyntaxKind.RoutineDecl) and (BlockOf(mNode) <> nil) then
      begin
        mList.Add(mNode);
      end;
      // In Rümpfen stehen keine Routinen (anonyme Methoden gehören zur Routine); lokale Routinen sind Kinder der
      // RoutineDecl vor dem Block.
      if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]) then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mStack.Push(mNode[mIndex]);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mStack.Free;
  end;
end;

/// <summary>Index des letzten Tokens vor AOffset, ab AFirst gesucht.</summary>
function LastTokenBefore(const ATokens: TArray<TPascalToken>; AFirst, AOffset: Integer): Integer;
begin
  Result := TSyntaxTree.FirstTokenOf(ATokens, AOffset) - 1;
  if Result < AFirst then
  begin
    Result := AFirst - 1;
  end;
end;

/// <summary>Fingerabdruck einer Routine ohne OuterHash; False ohne Token im Rumpf.</summary>
function BodyOf(ATree: TSyntaxTree; ARoutine: TSyntaxNode; out ABody: TRoutineBody): Boolean;
var
  mHeader: TSyntaxNode;
  mStart, mFirst, mLast: Integer;
  mTokens: TArray<TPascalToken>;
begin
  ABody := Default(TRoutineBody);
  mTokens := ATree.Tokens;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mStart := ARoutine.StartOffset;
  ABody.HeaderRange := TTextRange.Create(ARoutine.StartPos, ARoutine.StartPos);
  if mHeader <> nil then
  begin
    mStart := mHeader.EndOffset;
    ABody.HeaderRange := TTextRange.Create(ARoutine.StartPos, mHeader.EndPos);
  end;
  mFirst := TSyntaxTree.FirstTokenOf(mTokens, mStart);
  // Kommentare direkt hinter dem Kopf gehören nicht zum Rumpf.
  while (mFirst < Length(mTokens)) and (mTokens[mFirst].Kind = TPascalTokenKind.Comment) do
  begin
    Inc(mFirst);
  end;
  mLast := LastTokenBefore(mTokens, mFirst, ARoutine.EndOffset);
  if (mFirst >= Length(mTokens)) or (mLast < mFirst) then
  begin
    Exit(False);
  end;
  ABody.Name := QualifiedName(ARoutine);
  ABody.Line := ARoutine.StartPos.Line + 1;
  ABody.BodyLines := mTokens[mLast].EndPos.Line - mTokens[mFirst].StartPos.Line + 1;
  ABody.Hash := TDuplicateBodies.Fingerprint(TDuplicateBodies.Normalized(mTokens, mFirst, mLast));
  Result := True;
end;

{ TDuplicateBodies }

class function TDuplicateBodies.Normalized(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := AFirst to ALast do
    begin
      case ATokens[mIndex].Kind of
        TPascalTokenKind.Comment:
          Continue;
        TPascalTokenKind.Identifier, TPascalTokenKind.Keyword, TPascalTokenKind.Directive:
          mBuilder.Append(LowerCase(ATokens[mIndex].Text));
      else
        mBuilder.Append(ATokens[mIndex].Text);
      end;
      mBuilder.Append(#1);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TDuplicateBodies.Fingerprint(const AText: string): string;
var
  mFirst, mSecond: Cardinal;
  mChar: Char;
begin
  mFirst := cFnvOffset;
  mSecond := cFnvOffsetSecond;
  for mChar in AText do
  begin
    // In 64 Bit gerechnet und abgeschnitten: kein Überlauf, auch mit Überlaufprüfung.
    mFirst := Cardinal((UInt64(mFirst xor Ord(mChar)) * cFnvPrime) and $FFFFFFFF);
    mSecond := Cardinal((UInt64(mSecond xor (Ord(mChar) + 1)) * cFnvPrime) and $FFFFFFFF);
  end;
  Result := LowerCase(IntToHex(mFirst, 8) + IntToHex(mSecond, 8));
end;

class function TDuplicateBodies.IsGenerated(const AText: string): Boolean;
var
  mHead, mMark: string;
  mPosition, mLines: Integer;
begin
  mLines := 0;
  mPosition := 1;
  while (mPosition <= Length(AText)) and (mLines < cHeaderLines) do
  begin
    if AText[mPosition] = #10 then
    begin
      Inc(mLines);
    end;
    Inc(mPosition);
  end;
  mHead := LowerCase(Copy(AText, 1, mPosition - 1));
  for mMark in cGeneratedMarks do
  begin
    if Pos(mMark, mHead) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDuplicateBodies.Bodies(ATree: TSyntaxTree): TArray<TRoutineBody>;
var
  mRoutines: TArray<TSyntaxNode>;
  mHashes: TDictionary<TSyntaxNode, string>;
  mList: TList<TRoutineBody>;
  mNode, mOuter: TSyntaxNode;
  mBody: TRoutineBody;
  mOuterHash: string;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mRoutines := FindRoutines(ATree);
  mHashes := TDictionary<TSyntaxNode, string>.Create;
  mList := TList<TRoutineBody>.Create;
  try
    for mNode in mRoutines do
    begin
      if not BodyOf(ATree, mNode, mBody) then
      begin
        Continue;
      end;
      mOuter := mNode.Parent;
      while (mOuter <> nil) and (mOuter.Kind <> TSyntaxKind.RoutineDecl) do
      begin
        mOuter := mOuter.Parent;
      end;
      if (mOuter <> nil) and mHashes.TryGetValue(mOuter, mOuterHash) then
      begin
        mBody.OuterHash := mOuterHash;
      end;
      mHashes.AddOrSetValue(mNode, mBody.Hash);
      mList.Add(mBody);
    end;
    mList.Sort(TComparer<TRoutineBody>.Construct(
      function(const ALeft, ARight: TRoutineBody): Integer
      begin
        Result := ALeft.Line - ARight.Line;
        if Result = 0 then
        begin
          Result := CompareStr(ALeft.Name, ARight.Name);
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
    mHashes.Free;
  end;
end;

class function TDuplicateBodies.ForText(const AText: string): TArray<TRoutineBody>;
var
  mTree: TSyntaxTree;
begin
  Result := nil;
  if IsGenerated(AText) then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Bodies(mTree);
  finally
    mTree.Free;
  end;
end;

type
  /// <summary>Gesammelte Fassungen eines Fingerabdrucks.</summary>
  TCandidate = record
    BodyLines: Integer;
    Members: TArray<TDuplicateBodyMember>;
    /// <summary>OuterHash je Fassung, in der Reihenfolge von Members.</summary>
    OuterHashes: TArray<string>;
    /// <summary>Liegen die Fassungen in mindestens zwei Units?</summary>
    function SpansUnits: Boolean;
  end;

function TCandidate.SpansUnits: Boolean;
var
  mMember: TDuplicateBodyMember;
begin
  for mMember in Members do
  begin
    if not SameText(mMember.Path, Members[0].Path) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function MemberOrder(const ALeft, ARight: TDuplicateBodyMember): Integer;
begin
  Result := CompareText(ALeft.Path, ARight.Path);
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Routine, ARight.Routine);
  end;
  if Result = 0 then
  begin
    Result := ALeft.Line - ARight.Line;
  end;
end;

function GroupOrder(const ALeft, ARight: TDuplicateBodyGroup): Integer;
begin
  Result := ARight.BodyLines - ALeft.BodyLines;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Hash, ARight.Hash);
  end;
end;

/// <summary>Sammelt die Fassungen je Fingerabdruck in ACandidates; AIndex führt vom Fingerabdruck zur Stelle.
/// </summary>
procedure Gather(const AUnits: TArray<TDuplicateBodyUnit>; AMinLines: Integer; AIndex: TDictionary<string, Integer>;
  ACandidates: TList<TCandidate>);
var
  mUnit: TDuplicateBodyUnit;
  mBody: TRoutineBody;
  mCandidate: TCandidate;
  mMember: TDuplicateBodyMember;
  mAt: Integer;
begin
  for mUnit in AUnits do
  begin
    for mBody in mUnit.Bodies do
    begin
      if mBody.BodyLines < AMinLines then
      begin
        Continue;
      end;
      if not AIndex.TryGetValue(mBody.Hash, mAt) then
      begin
        mCandidate := Default(TCandidate);
        mCandidate.BodyLines := mBody.BodyLines;
        mAt := ACandidates.Add(mCandidate);
        AIndex.Add(mBody.Hash, mAt);
      end;
      mMember.Path := mUnit.Path;
      mMember.Routine := mBody.Name;
      mMember.Line := mBody.Line;
      mCandidate := ACandidates[mAt];
      mCandidate.Members := mCandidate.Members + [mMember];
      mCandidate.OuterHashes := mCandidate.OuterHashes + [mBody.OuterHash];
      ACandidates[mAt] := mCandidate;
    end;
  end;
end;

/// <summary>Alle Fassungen stehen in Routinen, die selbst eine Gruppe bilden.</summary>
function CoveredByOuter(const ACandidate: TCandidate; AGroups: TDictionary<string, Boolean>): Boolean;
var
  mOuter: string;
begin
  for mOuter in ACandidate.OuterHashes do
  begin
    if (mOuter = '') or not AGroups.ContainsKey(mOuter) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TDuplicateBodies.Find(const AUnits: TArray<TDuplicateBodyUnit>;
  AMinLines: Integer): TArray<TDuplicateBodyGroup>;
var
  mIndex: TDictionary<string, Integer>;
  mCandidates: TList<TCandidate>;
  mGroups: TDictionary<string, Boolean>;
  mList: TList<TDuplicateBodyGroup>;
  mPair: TPair<string, Integer>;
  mCandidate: TCandidate;
  mGroup: TDuplicateBodyGroup;
begin
  mIndex := TDictionary<string, Integer>.Create;
  mCandidates := TList<TCandidate>.Create;
  mGroups := TDictionary<string, Boolean>.Create;
  mList := TList<TDuplicateBodyGroup>.Create;
  try
    Gather(AUnits, AMinLines, mIndex, mCandidates);
    for mPair in mIndex do
    begin
      if mCandidates[mPair.Value].SpansUnits then
      begin
        mGroups.Add(mPair.Key, True);
      end;
    end;
    for mPair in mIndex do
    begin
      mCandidate := mCandidates[mPair.Value];
      if not mGroups.ContainsKey(mPair.Key) or CoveredByOuter(mCandidate, mGroups) then
      begin
        Continue;
      end;
      mGroup.Hash := mPair.Key;
      mGroup.BodyLines := mCandidate.BodyLines;
      mGroup.Members := Copy(mCandidate.Members);
      TArray.Sort<TDuplicateBodyMember>(mGroup.Members, TComparer<TDuplicateBodyMember>.Construct(MemberOrder));
      mList.Add(mGroup);
    end;
    mList.Sort(TComparer<TDuplicateBodyGroup>.Construct(GroupOrder));
    Result := mList.ToArray;
  finally
    mList.Free;
    mGroups.Free;
    mCandidates.Free;
    mIndex.Free;
  end;
end;

end.
