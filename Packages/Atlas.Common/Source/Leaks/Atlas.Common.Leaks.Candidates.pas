unit Atlas.Common.Leaks.Candidates;

// Kandidaten zu einem Leckbericht ohne Aufrufstapel (#1875): Welche Stellen
// erzeugen eine geleakte Klasse, und wie wahrscheinlich ist dort das Leck?
//
// Gesucht wird nach „TKlasse.Create…“ (jeder Konstruktor, dessen Name mit
// Create beginnt) für die Klassen aus dem Bericht; der Aufrufer gibt die
// Namen vor. Kommentare und Strings zählen nicht, ebenso
// die Kopfzeile „constructor TKlasse.Create“ und „raise EFehler.Create“.
//
// Bewertung je Stelle, nach Dringlichkeit:
//   NeverFreed    ohne Zuweisung, oder Variable bzw. Feld ohne Free
//   Returned      Rückgabe an den Aufrufer (Result := …, Exit(…), Result := X)
//   Passed        als Argument weitergereicht (Liste.Add(TKlasse.Create))
//   FieldFreed    Feld, das ein Destruktor derselben Unit freigibt
//   Owned         Owner im Konstruktor (Self, Owner, Application …)
//   LocalFreed    Variable, die dieselbe Routine freigibt (Free, FreeAndNil,
//                 DisposeOf)
//   NotInProgram  Datei gehört nicht zum Programm (Testunits, andere Projekte)
// Die Einstufung ist eine Schätzung aus dem Text; die Leck-Regeln prüfen
// genauer.

interface

uses
  Atlas.Common.Documents.Contract;

type
{$SCOPEDENUMS ON}
  TLeakRating = (NeverFreed, Returned, Passed, FieldFreed, Owned, LocalFreed, NotInProgram);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Datei für die Suche.</summary>
  TLeakSourceFile = record
    FileName: string;
    Text: string;
    /// <summary>False für Testunits und Dateien anderer Projekte.</summary>
    InProgram: Boolean;
  end;

  TLeakCandidate = record
    FileName: string;
    /// <summary>Stelle des Klassennamens (0-basiert).</summary>
    Position: TTextPosition;
    ClassName: string;
    Rating: TLeakRating;
    /// <summary>Variable oder Feld, dem das Objekt zugewiesen wird; '' ohne.</summary>
    Target: string;
    /// <summary>Routine um die Stelle, z. B. TKundenListe.Lade; '' außerhalb.</summary>
    Routine: string;
  end;

  TLeakCandidates = class
  public const
    cRatingNames: array[TLeakRating] of string = ('neverFreed', 'returned', 'passed', 'fieldFreed', 'owned',
      'localFreed', 'notInProgram');
  public
    /// <summary>Stellen in AFile, die eine Klasse aus AClassNames erzeugen, in Reihenfolge des Texts.</summary>
    class function InFile(const AFile: TLeakSourceFile; const AClassNames: TArray<string>): TArray<TLeakCandidate>;
      static;
    /// <summary>Stellen aller Dateien, nach Bewertung, dann Datei und Zeile.</summary>
    class function Find(const AFiles: TArray<TLeakSourceFile>; const AClassNames: TArray<string>):
      TArray<TLeakCandidate>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Leaks.Internals.CreateScan;

/// <summary>Bewertung einer Zuweisung: Feld frei im Destruktor, Variable frei in der Routine, Rückgabe.</summary>
function AssignedRating(const AScan: TLeakCreateScan; const ASite: TLeakCreateSite): TLeakRating;
begin
  if ASite.TargetIsField and AScan.DestructorFrees(LowerCase(ASite.Target)) then
  begin
    Result := TLeakRating.FieldFreed;
  end
  else if ASite.RoutineFrees then
  begin
    Result := TLeakRating.LocalFreed;
  end
  else if ASite.RoutineReturns then
  begin
    Result := TLeakRating.Returned;
  end
  else
  begin
    Result := TLeakRating.NeverFreed;
  end;
end;

/// <summary>Bewertung einer Stelle im Programm aus dem, was der Text hergibt.</summary>
function RatingOf(const AScan: TLeakCreateScan; const ASite: TLeakCreateSite): TLeakRating;
begin
  if ASite.Owned then
  begin
    Exit(TLeakRating.Owned);
  end;
  case ASite.Use of
    TLeakCreateUse.Returned:
      Result := TLeakRating.Returned;
    TLeakCreateUse.Argument:
      Result := TLeakRating.Passed;
    TLeakCreateUse.Assigned:
      Result := AssignedRating(AScan, ASite);
  else
    Result := TLeakRating.NeverFreed;
  end;
end;

class function TLeakCandidates.InFile(const AFile: TLeakSourceFile;
  const AClassNames: TArray<string>): TArray<TLeakCandidate>;
var
  mScan: TLeakCreateScan;
  mSite: TLeakCreateSite;
  mCandidate: TLeakCandidate;
  mCount: Integer;
begin
  mScan := TLeakCreateScan.Run(AFile.Text, AClassNames);
  SetLength(Result, Length(mScan.Sites));
  mCount := 0;
  for mSite in mScan.Sites do
  begin
    mCandidate := Default(TLeakCandidate);
    mCandidate.FileName := AFile.FileName;
    mCandidate.Position := mSite.Position;
    mCandidate.ClassName := mSite.ClassName;
    mCandidate.Target := mSite.Target;
    mCandidate.Routine := mSite.Routine;
    if AFile.InProgram then
    begin
      mCandidate.Rating := RatingOf(mScan, mSite);
    end
    else
    begin
      mCandidate.Rating := TLeakRating.NotInProgram;
    end;
    Result[mCount] := mCandidate;
    Inc(mCount);
  end;
end;

/// <summary>Kommt A vor B? Bewertung, dann Datei, dann Stelle.</summary>
function CandidateBefore(const A, B: TLeakCandidate): Boolean;
begin
  if A.Rating <> B.Rating then
  begin
    Exit(Ord(A.Rating) < Ord(B.Rating));
  end;
  if not SameFileName(A.FileName, B.FileName) then
  begin
    Exit(CompareText(A.FileName, B.FileName) < 0);
  end;
  if A.Position.Line <> B.Position.Line then
  begin
    Exit(A.Position.Line < B.Position.Line);
  end;
  Result := A.Position.Character < B.Position.Character;
end;

/// <summary>Einfügen sortiert stabil und braucht keinen Vergleicher.</summary>
procedure SortCandidates(var ACandidates: TArray<TLeakCandidate>);
var
  mIndex, mAt: Integer;
  mCandidate: TLeakCandidate;
begin
  for mIndex := 1 to High(ACandidates) do
  begin
    mCandidate := ACandidates[mIndex];
    mAt := mIndex - 1;
    while (mAt >= 0) and CandidateBefore(mCandidate, ACandidates[mAt]) do
    begin
      ACandidates[mAt + 1] := ACandidates[mAt];
      Dec(mAt);
    end;
    ACandidates[mAt + 1] := mCandidate;
  end;
end;

class function TLeakCandidates.Find(const AFiles: TArray<TLeakSourceFile>;
  const AClassNames: TArray<string>): TArray<TLeakCandidate>;
var
  mFile: TLeakSourceFile;
begin
  Result := nil;
  for mFile in AFiles do
  begin
    // Dateien ohne einen der Namen nicht zerlegen.
    if Pos('create', LowerCase(mFile.Text)) > 0 then
    begin
      Result := Result + InFile(mFile, AClassNames);
    end;
  end;
  SortCandidates(Result);
end;

end.
