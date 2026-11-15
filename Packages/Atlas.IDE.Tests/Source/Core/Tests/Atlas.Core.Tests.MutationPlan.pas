unit Atlas.Core.Tests.MutationPlan;

// Was ein Mutationslauf prüft (#1460), ohne VCL und Open Tools API:
// - Anfrage an den Server (atlas.server.mutants): URI und Operatoren aus
//   tests.mutation.operators (Kennungen, getrennt durch Komma, Semikolon
//   oder Leerraum; leer = alle).
// - Auswahl der Mutanten: die Methode an einer Zeile (die innerste Routine,
//   deren Zeilen sie enthalten), die ganze Unit oder nur Routinen ohne
//   gültiges Ergebnis (neu oder seit dem letzten Lauf geändert).
// - Ausgang eines Testlaufs gegen einen Mutanten: Zeitüberschreitung,
//   sonst der XML-Bericht (ein fehlgeschlagener Test erkennt den Mutanten,
//   alle grün heißt überlebt); ohne Bericht zählt ein Exitcode ungleich 0 als
//   erkannt (Absturz), sonst ist der Lauf nicht bewertbar.

interface

uses
  Atlas.Core.Tests.Mutants,
  Atlas.Core.Tests.MutationResults;

type
{$SCOPEDENUMS ON}
  TAtlasMutationScope = (Routine, WholeUnit, Changed);
  /// <summary>Wie ein erkannter Mutant beschrieben wird: ohne Angabe, mit dem Exitcode (Absturz ohne Bericht) oder
  /// mit dem ersten fehlgeschlagenen Test.</summary>
  TAtlasMutationKilledText = (Plain, ExitCode, ByTest);
{$SCOPEDENUMS OFF}

  /// <summary>Ausgewählte Mutanten mit ihrer Routine und Nummer darin.</summary>
  TAtlasMutationJob = record
    Mutant: TAtlasMutant;
    Routine: TAtlasMutantRoutine;
    /// <summary>Der wievielte Mutant seiner Routine (ab 0).</summary>
    Index: Integer;
  end;

  TAtlasMutationPlan = class
  public const
    cCommand = 'atlas.server.mutants';
  public
    /// <summary>Kennungen aus dem Text der Einstellung (Komma, Semikolon, Leerraum), klein, ohne doppelte.</summary>
    class function OperatorsOf(const ASetting: string): TArray<string>; static;
    /// <summary>Argumente für atlas.server.mutants als JSON-Array.</summary>
    class function RequestJson(const AUri: string; const AOperators: TArray<string>): string; static;
    /// <summary>Innerste Routine von AList, deren Zeilen ALine (ab 0) enthalten; False ohne.</summary>
    class function RoutineAt(const AList: TAtlasMutantList; ALine: Integer;
      out ARoutine: TAtlasMutantRoutine): Boolean; static;
    /// <summary>Mutanten für AScope in Reihenfolge des Quelltexts. ALine gilt für Routine; AResults und ALines
    /// (Text der Unit) für Changed; AFileName ist die Datei der Unit.</summary>
    class function Select(const AList: TAtlasMutantList; AScope: TAtlasMutationScope; ALine: Integer;
      const AFileName: string; const ALines: TArray<string>; AResults: TAtlasMutationResults):
      TArray<TAtlasMutationJob>; static;
    /// <summary>Ausgang eines Testlaufs: ATimedOut, Exitcode AExitCode und XML-Bericht AXml ('' = keiner). ABy
    /// nennt beim Erkennen den ersten fehlgeschlagenen Test bzw. ohne Bericht den Exitcode als Zahl; ein Bericht
    /// ohne Tests ist nicht bewertbar (Invalid).</summary>
    class function StatusOf(ATimedOut: Boolean; AExitCode: Integer; const AXml: string; out ABy: string):
      TAtlasMutationStatus; static;
  end;

  /// <summary>Ablauf eines Mutationslaufs: Lauf ohne Mutation, Ausgang je Mutant, Zahlen und Ergebnisse je Routine.
  /// APosition ist -1 für den Lauf ohne Mutation, sonst der Index in den Jobs.</summary>
  TAtlasMutationSteps = class
  public
    /// <summary>Geprüfte Mutanten beim Stand APosition.</summary>
    class function Done(APosition: Integer): Integer; static;
    /// <summary>Scheitert der Lauf ohne Mutation mit AStatus? Rot, nicht gebaut oder nicht bewertbar: Jeder Mutant
    /// wäre sonst „erkannt“. Bei APosition ab 0 immer False.</summary>
    class function BaselineFailed(APosition: Integer; AStatus: TAtlasMutationStatus): Boolean; static;
    /// <summary>Ausgang des Mutanten AJob mit AStatus, ABy und der Dauer AMilliseconds; die Zeile gilt relativ zum
    /// Kopf der Routine.</summary>
    class function OutcomeOf(const AJob: TAtlasMutationJob; AStatus: TAtlasMutationStatus; const ABy: string;
      AMilliseconds: Integer): TAtlasMutationOutcome; static;
    /// <summary>Zahlen über die ersten ADone Ausgänge.</summary>
    class function Totals(const AOutcomes: TArray<TAtlasMutationOutcome>; ADone: Integer): TAtlasMutationTotals;
      static;
    /// <summary>Indizes der überlebenden unter den ersten ADone Ausgängen.</summary>
    class function Survivors(const AOutcomes: TArray<TAtlasMutationOutcome>; ADone: Integer): TArray<Integer>;
      static;
    /// <summary>Ist AJobs[AIndex] der erste Job seiner Routine (nach Namen)?</summary>
    class function FirstOfRoutine(const AJobs: TArray<TAtlasMutationJob>; AIndex: Integer): Boolean; static;
    /// <summary>Ergebnis der Routine von AJobs[AFirst] aus allen Mutanten dieser Routine; AComplete, wenn alle vor
    /// ADone liegen (geprüft sind). Eine lokale Routine kann die Mutanten der äußeren teilen: nach Namen, nicht
    /// nach Nachbarschaft.</summary>
    class function RoutineResult(const AJobs: TArray<TAtlasMutationJob>;
      const AOutcomes: TArray<TAtlasMutationOutcome>; AFirst, ADone: Integer;
      out AComplete: Boolean): TAtlasMutationRoutineResult; static;
    /// <summary>Beschreibung eines erkannten Mutanten nach ABy aus StatusOf.</summary>
    class function KilledText(const ABy: string): TAtlasMutationKilledText; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.TestResults;

{ TAtlasMutationPlan }

class function TAtlasMutationPlan.OperatorsOf(const ASetting: string): TArray<string>;
var
  mPart, mId: string;
begin
  Result := nil;
  for mPart in ASetting.Split([',', ';', ' ', #9]) do
  begin
    mId := LowerCase(Trim(mPart));
    if (mId <> '') and (IndexStr(mId, Result) < 0) then
    begin
      Result := Result + [mId];
    end;
  end;
end;

class function TAtlasMutationPlan.RequestJson(const AUri: string; const AOperators: TArray<string>): string;
var
  mArguments, mOperators: TJSONArray;
  mOptions: TJSONObject;
  mId: string;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mOptions := TJSONObject.Create;
    mArguments.AddElement(mOptions);
    if AOperators <> nil then
    begin
      mOperators := TJSONArray.Create;
      mOptions.AddPair('operators', mOperators);
      for mId in AOperators do
      begin
        mOperators.Add(mId);
      end;
    end;
    Result := mArguments.ToJSON([]);
  finally
    mArguments.Free;
  end;
end;

class function TAtlasMutationPlan.RoutineAt(const AList: TAtlasMutantList; ALine: Integer;
  out ARoutine: TAtlasMutantRoutine): Boolean;
var
  mRoutine: TAtlasMutantRoutine;
begin
  ARoutine := Default(TAtlasMutantRoutine);
  Result := False;
  for mRoutine in AList.Routines do
  begin
    if (ALine < mRoutine.Line) or (ALine > mRoutine.EndLine) then
    begin
      Continue;
    end;
    // Lokale Routinen liegen in der äußeren: die kürzere gewinnt.
    if not Result or (mRoutine.EndLine - mRoutine.Line < ARoutine.EndLine - ARoutine.Line) then
    begin
      ARoutine := mRoutine;
      Result := True;
    end;
  end;
end;

/// <summary>Hat die Routine ARoutine ein Ergebnis mit der Prüfsumme von jetzt?</summary>
function HasValidResult(AResults: TAtlasMutationResults; const AFileName: string; const ALines: TArray<string>;
  const ARoutine: TAtlasMutantRoutine): Boolean;
var
  mResult: TAtlasMutationRoutineResult;
begin
  Result := (AResults <> nil) and AResults.Lookup(AFileName, ARoutine.Name,
    TAtlasMutants.RoutineBody(ALines, ARoutine), mResult);
end;

class function TAtlasMutationPlan.Select(const AList: TAtlasMutantList; AScope: TAtlasMutationScope;
  ALine: Integer; const AFileName: string; const ALines: TArray<string>; AResults: TAtlasMutationResults):
  TArray<TAtlasMutationJob>;
var
  mIndex: Integer;
  mWanted: TAtlasMutantRoutine;
  mJob: TAtlasMutationJob;
  mValid: TDictionary<string, Boolean>;
  mIsValid: Boolean;
begin
  Result := nil;
  if (AScope = TAtlasMutationScope.Routine) and not RoutineAt(AList, ALine, mWanted) then
  begin
    Exit;
  end;
  mValid := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AList.Mutants) do
    begin
      mJob := Default(TAtlasMutationJob);
      mJob.Mutant := AList.Mutants[mIndex];
      if not AList.RoutineOf(mJob.Mutant.Routine, mJob.Routine) or
        ((AScope = TAtlasMutationScope.Routine) and (mJob.Routine.Name <> mWanted.Name)) then
      begin
        Continue;
      end;
      if AScope = TAtlasMutationScope.Changed then
      begin
        if not mValid.TryGetValue(mJob.Routine.Name, mIsValid) then
        begin
          mIsValid := HasValidResult(AResults, AFileName, ALines, mJob.Routine);
          mValid.Add(mJob.Routine.Name, mIsValid);
        end;
        if mIsValid then
        begin
          Continue;
        end;
      end;
      mJob.Index := AList.IndexInRoutine(mIndex);
      Result := Result + [mJob];
    end;
  finally
    mValid.Free;
  end;
end;

class function TAtlasMutationPlan.StatusOf(ATimedOut: Boolean; AExitCode: Integer; const AXml: string;
  out ABy: string): TAtlasMutationStatus;
var
  mRun: TTestRunResult;
begin
  ABy := '';
  if ATimedOut then
  begin
    Exit(TAtlasMutationStatus.TimedOut);
  end;
  mRun := Default(TTestRunResult);
  if Trim(AXml) <> '' then
  begin
    mRun := TTestResults.Parse(AXml);
  end;
  if mRun.Valid and (Length(mRun.Failures) > 0) then
  begin
    ABy := mRun.Failures[0].FullName;
    Result := TAtlasMutationStatus.Killed;
  end
  else if mRun.Valid and (mRun.Total > 0) then
  begin
    Result := TAtlasMutationStatus.Survived;
  end
  else if not mRun.Valid and (AExitCode <> 0) then
  begin
    ABy := IntToStr(AExitCode);
    Result := TAtlasMutationStatus.Killed;
  end
  else
  begin
    Result := TAtlasMutationStatus.Invalid;
  end;
end;

{ TAtlasMutationSteps }

class function TAtlasMutationSteps.Done(APosition: Integer): Integer;
begin
  Result := APosition;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

class function TAtlasMutationSteps.BaselineFailed(APosition: Integer; AStatus: TAtlasMutationStatus): Boolean;
begin
  Result := (APosition < 0) and (AStatus <> TAtlasMutationStatus.Survived);
end;

class function TAtlasMutationSteps.OutcomeOf(const AJob: TAtlasMutationJob; AStatus: TAtlasMutationStatus;
  const ABy: string; AMilliseconds: Integer): TAtlasMutationOutcome;
begin
  Result := Default(TAtlasMutationOutcome);
  Result.Index := AJob.Index;
  Result.OperatorId := AJob.Mutant.OperatorId;
  Result.Original := AJob.Mutant.Original;
  Result.Replacement := AJob.Mutant.Replacement;
  Result.Description := AJob.Mutant.Description;
  Result.Line := AJob.Mutant.Line - 1 - AJob.Routine.Line;
  Result.Status := AStatus;
  Result.By := ABy;
  Result.Milliseconds := AMilliseconds;
end;

class function TAtlasMutationSteps.Totals(const AOutcomes: TArray<TAtlasMutationOutcome>;
  ADone: Integer): TAtlasMutationTotals;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasMutationTotals);
  for mIndex := 0 to Min(ADone, Length(AOutcomes)) - 1 do
  begin
    Result.Add(AOutcomes[mIndex].Status);
  end;
end;

class function TAtlasMutationSteps.Survivors(const AOutcomes: TArray<TAtlasMutationOutcome>;
  ADone: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to Min(ADone, Length(AOutcomes)) - 1 do
  begin
    if AOutcomes[mIndex].Status = TAtlasMutationStatus.Survived then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasMutationSteps.FirstOfRoutine(const AJobs: TArray<TAtlasMutationJob>; AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  Result := True;
  for mOther := 0 to AIndex - 1 do
  begin
    if AJobs[mOther].Routine.Name = AJobs[AIndex].Routine.Name then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasMutationSteps.RoutineResult(const AJobs: TArray<TAtlasMutationJob>;
  const AOutcomes: TArray<TAtlasMutationOutcome>; AFirst, ADone: Integer;
  out AComplete: Boolean): TAtlasMutationRoutineResult;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasMutationRoutineResult);
  Result.Routine := AJobs[AFirst].Routine.Name;
  Result.Line := AJobs[AFirst].Routine.Line;
  Result.EndLine := AJobs[AFirst].Routine.EndLine;
  AComplete := True;
  for mIndex := AFirst to High(AJobs) do
  begin
    if AJobs[mIndex].Routine.Name = Result.Routine then
    begin
      AComplete := AComplete and (mIndex < ADone);
      Result.Outcomes := Result.Outcomes + [AOutcomes[mIndex]];
    end;
  end;
end;

class function TAtlasMutationSteps.KilledText(const ABy: string): TAtlasMutationKilledText;
begin
  if StrToIntDef(ABy, 0) <> 0 then
  begin
    Result := TAtlasMutationKilledText.ExitCode;
  end
  else if ABy <> '' then
  begin
    Result := TAtlasMutationKilledText.ByTest;
  end
  else
  begin
    Result := TAtlasMutationKilledText.Plain;
  end;
end;

end.
