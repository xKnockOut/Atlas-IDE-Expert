unit Atlas.Common.Editing.HoistedDeclarations;

// Deklarationen, die beim Ordnen der Methodenrümpfe mit nach vorn wandern.
//
// TMethodOrder tauscht nur die Plätze der Rümpfe; freie Routinen und
// Deklarationen (const, var, type) zwischen ihnen bleiben stehen. Rückt ein
// Rumpf dabei über eine solche Deklaration nach vorn, die er braucht,
// übersetzte die Unit nicht mehr. LinesOf nennt dann den Code zwischen den
// Plätzen, der vor den ersten Platz wandert: die gebrauchte Deklaration und
// allen Code davor zwischen den Plätzen, damit dessen Reihenfolge bleibt.
// Rümpfe und Kommentare am Ende eines Stücks (sie gehören zum Rumpf
// dahinter) bleiben stehen. "Braucht" heißt: Der Name kommt als Bezeichner im
// Rumpf vor; ein zufällig gleicher Name zieht die Deklaration unnötig, aber
// unschädlich mit.

interface

type
  /// <summary>Zeilen eines Rumpfs (ab 0, mit den Kommentaren darüber).</summary>
  TBodySpan = record
    First, Last: Integer;
    class function Create(AFirst, ALast: Integer): TBodySpan; static;
  end;

  THoistedDeclarations = class
  public
    /// <summary>Zeilen von ALines, die vor den ersten Platz wandern; nil, wenn nichts wandern muss oder ein
    /// Stück eine {$IF…}- bzw. {$REGION}-Klammer nur halb enthält. ABodies sind alle Rümpfe der Unit, ASlots
    /// die Plätze der verschobenen nach Zeilen, AOrigins[I] der Platz, von dem der Rumpf für Platz I kommt.
    /// </summary>
    class function LinesOf(const ALines: TArray<string>; const ABodies, ASlots: TArray<TBodySpan>;
      const AOrigins: TArray<Integer>): TArray<Boolean>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cRoutineWords: array[0..5] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator',
    'class');

/// <summary>Bezeichner am Anfang von AText; '' ohne.</summary>
function LeadingIdent(const AText: string): string;
var
  mEnd: Integer;
begin
  mEnd := 1;
  while (mEnd <= Length(AText)) and CharInSet(AText[mEnd], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Inc(mEnd);
  end;
  Result := Copy(AText, 1, mEnd - 1);
end;

/// <summary>AText ohne das Wort AWord am Anfang, links ohne Leerraum.</summary>
function AfterWord(const AText, AWord: string): string;
begin
  Result := TrimLeft(Copy(AText, Length(AWord) + 1, MaxInt));
end;

/// <summary>Name der freien Routine im Kopf ALine; '' bei einem Methodenrumpf (TKunde.Laden).</summary>
function RoutineName(const ALine: string): string;
var
  mRest: string;
begin
  mRest := Trim(ALine);
  if SameText(LeadingIdent(mRest), 'class') then
  begin
    mRest := AfterWord(mRest, 'class');
  end;
  mRest := AfterWord(mRest, LeadingIdent(mRest));
  Result := LeadingIdent(mRest);
  if StartsStr('.', AfterWord(mRest, Result)) then
  begin
    Result := '';
  end;
end;

/// <summary>Name, den die eingerückte Zeile ALine eines const-, var- oder type-Abschnitts deklariert; '' ohne.
/// </summary>
function SectionName(const ALine: string): string;
var
  mRest: string;
begin
  Result := LeadingIdent(TrimLeft(ALine));
  mRest := AfterWord(TrimLeft(ALine), Result);
  if (mRest = '') or StartsStr(':=', mRest) or not CharInSet(mRest[1], ['=', ':', ',', '<']) then
  begin
    Result := '';
  end;
end;

type
  /// <summary>Sammelt die Namen, die Code auf oberster Ebene des implementation-Teils deklariert: freie Routinen
  /// und Einträge der const-, var- und type-Abschnitte (nicht die lokalen einer Routine).</summary>
  TDeclarationScan = record
    InRoutine, InSection: Boolean;
    Names: TArray<string>;
    procedure Add(const AName: string);
    procedure Scan(const ALine: string);
  end;

{ TDeclarationScan }

procedure TDeclarationScan.Add(const AName: string);
begin
  if AName <> '' then
  begin
    Names := Names + [AName];
  end;
end;

procedure TDeclarationScan.Scan(const ALine: string);
var
  mWord: string;
begin
  if (ALine = '') or (ALine[1] <= ' ') then
  begin
    if InSection and not InRoutine then
    begin
      Add(SectionName(ALine));
    end;
    Exit;
  end;
  mWord := LowerCase(LeadingIdent(ALine));
  if MatchStr(mWord, cRoutineWords) then
  begin
    Add(RoutineName(ALine));
    InSection := False;
    InRoutine := not ContainsText(ALine, 'forward;') and not ContainsText(ALine, 'external');
  end
  else if MatchStr(mWord, ['const', 'var', 'type', 'threadvar', 'resourcestring']) and not InRoutine then
  begin
    InSection := True;
    Add(SectionName(AfterWord(ALine, mWord)));
  end
  else if mWord = 'end' then
  begin
    InRoutine := False;
    InSection := False;
  end;
end;

/// <summary>Kommt einer der Namen ANames als Bezeichner in der Zeile ALine vor?</summary>
function LineUses(const ALine: string; const ANames: TArray<string>): Boolean;
var
  mPosition: Integer;
  mIdent: string;
begin
  Result := False;
  mPosition := 1;
  while not Result and (mPosition <= Length(ALine)) do
  begin
    mIdent := LeadingIdent(Copy(ALine, mPosition, MaxInt));
    if mIdent = '' then
    begin
      Inc(mPosition);
    end
    else
    begin
      Result := IndexText(mIdent, ANames) >= 0;
      Inc(mPosition, Length(mIdent));
    end;
  end;
end;

/// <summary>Kommt einer der Namen ANames im Rumpf ABlock vor?</summary>
function BlockUses(const ALines: TArray<string>; const ABlock: TBodySpan; const ANames: TArray<string>): Boolean;
var
  mLine: Integer;
begin
  Result := False;
  mLine := ABlock.First;
  while not Result and (mLine <= ABlock.Last) do
  begin
    Result := LineUses(ALines[mLine], ANames);
    Inc(mLine);
  end;
end;

/// <summary>Namen, die der Code zwischen den Plätzen AGap und AGap + 1 deklariert.</summary>
function GapNames(const ALines: TArray<string>; const ASlots: TArray<TBodySpan>; AGap: Integer): TArray<string>;
var
  mScan: TDeclarationScan;
  mLine: Integer;
begin
  mScan := Default(TDeclarationScan);
  for mLine := ASlots[AGap].Last + 1 to ASlots[AGap + 1].First - 1 do
  begin
    mScan.Scan(ALines[mLine]);
  end;
  Result := mScan.Names;
end;

/// <summary>Rückt ein Rumpf über die Lücke hinter dem Platz AGap nach vorn und braucht er etwas, das dort
/// deklariert ist?</summary>
function GapNeeded(const ALines: TArray<string>; const ASlots: TArray<TBodySpan>; const AOrigins: TArray<Integer>;
  AGap: Integer): Boolean;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  Result := False;
  mNames := GapNames(ALines, ASlots, AGap);
  mIndex := 0;
  while not Result and (mNames <> nil) and (mIndex <= AGap) do
  begin
    Result := (AOrigins[mIndex] > AGap) and BlockUses(ALines, ASlots[AOrigins[mIndex]], mNames);
    Inc(mIndex);
  end;
end;

/// <summary>Zeilen, die zu einem Rumpf aus ABlocks gehören.</summary>
function BlockLines(const ABlocks: TArray<TBodySpan>; ALineCount: Integer): TArray<Boolean>;
var
  mBlock: TBodySpan;
  mLine: Integer;
begin
  SetLength(Result, ALineCount);
  for mBlock in ABlocks do
  begin
    for mLine := mBlock.First to mBlock.Last do
    begin
      Result[mLine] := True;
    end;
  end;
end;

/// <summary>Wirkung der Zeile ALine auf die Tiefe der {$IF…}- und {$REGION}-Klammern.</summary>
function DirectiveDepth(const ALine: string): Integer;
var
  mLine: string;
begin
  Result := 0;
  mLine := UpperCase(TrimLeft(ALine));
  if StartsStr('{$IF', mLine) or StartsStr('{$REGION', mLine) then
  begin
    Result := 1;
  end
  else if StartsStr('{$ENDIF', mLine) or StartsStr('{$IFEND', mLine) or StartsStr('{$ENDREGION', mLine) then
  begin
    Result := -1;
  end;
end;

/// <summary>Ist ALine nur ein Kommentar (keine Direktive)?</summary>
function IsCommentLine(const ALine: string): Boolean;
var
  mLine: string;
begin
  mLine := TrimLeft(ALine);
  Result := StartsStr('//', mLine) or StartsStr('(*', mLine) or (StartsStr('{', mLine) and not StartsStr('{$', mLine));
end;

/// <summary>Letzte Zeile des Code-Teils von AFirst..ALast mit den Leerzeilen dahinter; Kommentare am Ende
/// gehören zum folgenden Rumpf. AFirst - 1 ohne Code.</summary>
function CodeEnd(const ALines: TArray<string>; AFirst, ALast: Integer): Integer;
begin
  Result := ALast;
  while (Result >= AFirst) and ((Trim(ALines[Result]) = '') or IsCommentLine(ALines[Result])) do
  begin
    Dec(Result);
  end;
  if Result < AFirst then
  begin
    Exit;
  end;
  while (Result < ALast) and (Trim(ALines[Result + 1]) = '') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Ein Stück AFirst..ALast ohne Rumpf: Sein Code-Teil wandert mit, wenn er Code auf oberster Ebene
/// enthält; ABalanced wird falsch, wenn er eine Klammer nur halb enthält.</summary>
procedure MarkRun(const ALines: TArray<string>; AFirst, ALast: Integer; var AHoisted: TArray<Boolean>;
  var ABalanced: Boolean);
var
  mLine, mDepth: Integer;
  mCode: Boolean;
begin
  while (AFirst <= ALast) and (Trim(ALines[AFirst]) = '') do
  begin
    Inc(AFirst);
  end;
  ALast := CodeEnd(ALines, AFirst, ALast);
  mDepth := 0;
  mCode := False;
  for mLine := AFirst to ALast do
  begin
    Inc(mDepth, DirectiveDepth(ALines[mLine]));
    mCode := mCode or (LeadingIdent(ALines[mLine]) <> '');
  end;
  if not mCode then
  begin
    Exit;
  end;
  ABalanced := ABalanced and (mDepth = 0);
  for mLine := AFirst to ALast do
  begin
    AHoisted[mLine] := True;
  end;
end;

{ TBodySpan }

class function TBodySpan.Create(AFirst, ALast: Integer): TBodySpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

{ THoistedDeclarations }

class function THoistedDeclarations.LinesOf(const ALines: TArray<string>; const ABodies, ASlots: TArray<TBodySpan>;
  const AOrigins: TArray<Integer>): TArray<Boolean>;
var
  mGap, mLast, mLine, mStart: Integer;
  mInBlock: TArray<Boolean>;
  mBalanced: Boolean;
begin
  Result := nil;
  mLast := -1;
  for mGap := 0 to High(ASlots) - 1 do
  begin
    if GapNeeded(ALines, ASlots, AOrigins, mGap) then
    begin
      mLast := mGap;
    end;
  end;
  if mLast < 0 then
  begin
    Exit;
  end;
  mInBlock := BlockLines(ABodies, Length(ALines));
  SetLength(Result, Length(ALines));
  mBalanced := True;
  mStart := -1;
  for mLine := ASlots[0].Last + 1 to ASlots[mLast + 1].First do
  begin
    if mInBlock[mLine] and (mStart >= 0) then
    begin
      MarkRun(ALines, mStart, mLine - 1, Result, mBalanced);
      mStart := -1;
    end
    else if not mInBlock[mLine] and (mStart < 0) then
    begin
      mStart := mLine;
    end;
  end;
  if not mBalanced then
  begin
    Result := nil;
  end;
end;

end.
