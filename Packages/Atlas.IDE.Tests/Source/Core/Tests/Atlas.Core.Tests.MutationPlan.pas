unit Atlas.Core.Tests.MutationPlan;

// Was ein Mutationslauf prüft (#1460), ohne VCL und Open Tools API:
// - Anfrage an den Server (atlas.server.mutants): URI und Operatoren aus
//   tests.mutation.operators (Kennungen, getrennt durch Komma, Semikolon
//   oder Leerraum; leer = alle).
// - Auswahl der Mutanten: die Methode an einer Zeile (die innerste Routine,
//   deren Zeilen sie enthalten), die ganze Unit oder nur Routinen ohne
//   gültiges Ergebnis (neu oder seit dem letzten Lauf geändert).

interface

uses
  Atlas.Core.Tests.Mutants,
  Atlas.Core.Tests.MutationResults;

type
{$SCOPEDENUMS ON}
  TAtlasMutationScope = (Routine, WholeUnit, Changed);
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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections;

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

end.
