unit Atlas.Core.Debug.RoutinePattern;

// Muster für Routinen im Aufrufstapel, ohne IDE: „Nur wenn im Aufrufstapel“
// der Haltepunkt-Regeln (#2548) und der Ort von Exception-Regeln (#838).
// Eine Routine heißt wie in der Kopfzeile des Aufrufstapels der IDE, ohne
// Parameter („Kunden.Import.TKundenImport.LeseZeile“, siehe
// TAtlasDebugCallStack.RoutineOf). Ein Muster passt, wenn es ab dem Anfang
// eines Namensteils (nach einem Punkt) passt:
//   - ohne Platzhalter bis zum Ende („TKundenImport.LeseZeile“, „LeseZeile“)
//     oder bis zu einem Punkt (ganze Unit „Kunden.Import“, ganze Klasse
//     „TKundenImport“);
//   - mit `*` (beliebig viele Zeichen, auch Punkte) bis zum Ende
//     („Kunden.*“, „*.LeseZeile“, „TKunden*.Lese*“); Glob vergleicht.
// Groß-/Kleinschreibung zählt nicht.

interface

type
  TAtlasRoutinePattern = record
  public
    /// <summary>Passt APattern zur Routine ARoutine? Leeres Muster oder leere Routine: nie.</summary>
    class function Matches(const APattern, ARoutine: string): Boolean; static;
    /// <summary>Index der ersten Routine ab AFirst, zu der APattern passt; -1 ohne.</summary>
    class function FirstMatch(const APattern: string; const ARoutines: TArray<string>; AFirst: Integer): Integer;
      static;
    /// <summary>Passt AText ganz zu APattern? `*` steht für beliebig viele Zeichen, sonst zählt jedes Zeichen
    /// (auch `?`); ohne Groß-/Kleinschreibung.</summary>
    class function Glob(const APattern, AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

const
  cWildcard = '*';

/// <summary>Passt APattern ab dem Anfang von ATail?</summary>
function TailMatches(const APattern, ATail: string): Boolean;
begin
  if Pos('*', APattern) > 0 then
  begin
    Exit(TAtlasRoutinePattern.Glob(APattern, ATail));
  end;
  Result := SameText(APattern, ATail) or StartsText(APattern + '.', ATail);
end;

{ TAtlasRoutinePattern }

class function TAtlasRoutinePattern.Matches(const APattern, ARoutine: string): Boolean;
var
  mPattern, mRoutine: string;
  mStart: Integer;
begin
  mPattern := Trim(APattern);
  mRoutine := Trim(ARoutine);
  Result := False;
  if (mPattern = '') or (mRoutine = '') then
  begin
    Exit;
  end;
  mStart := 1;
  while mStart > 0 do
  begin
    if TailMatches(mPattern, Copy(mRoutine, mStart, MaxInt)) then
    begin
      Exit(True);
    end;
    mStart := PosEx('.', mRoutine, mStart);
    if mStart > 0 then
    begin
      Inc(mStart);
    end;
  end;
end;

class function TAtlasRoutinePattern.FirstMatch(const APattern: string; const ARoutines: TArray<string>;
  AFirst: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := Max(0, AFirst) to High(ARoutines) do
  begin
    if Matches(APattern, ARoutines[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasRoutinePattern.Glob(const APattern, AText: string): Boolean;
var
  mPattern, mText: string;
  mP, mT, mStar, mResume: Integer;
begin
  // AnsiLowerCase: auch Umlaute in Meldungen (#2549).
  mPattern := AnsiLowerCase(APattern);
  mText := AnsiLowerCase(AText);
  mP := 1;
  mT := 1;
  // Letzter * im Muster und die Stelle im Text, ab der er gerade steht.
  mStar := 0;
  mResume := 0;
  while mT <= Length(mText) do
  begin
    if (mP <= Length(mPattern)) and (mPattern[mP] = cWildcard) then
    begin
      mStar := mP;
      mResume := mT;
      Inc(mP);
    end
    else if (mP <= Length(mPattern)) and (mPattern[mP] = mText[mT]) then
    begin
      Inc(mP);
      Inc(mT);
    end
    else if mStar = 0 then
    begin
      Exit(False);
    end
    else
    begin
      // Der * schluckt ein Zeichen mehr.
      Inc(mResume);
      mT := mResume;
      mP := mStar + 1;
    end;
  end;
  while (mP <= Length(mPattern)) and (mPattern[mP] = cWildcard) do
  begin
    Inc(mP);
  end;
  Result := mP > Length(mPattern);
end;

end.
