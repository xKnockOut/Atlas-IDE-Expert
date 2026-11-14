unit Atlas.Core.Tests.Mutants;

// Mutanten einer Unit für den Mutationslauf im Plugin (#1460), ohne VCL und
// Open Tools API:
// - Liste: Antwort des Serverbefehls atlas.server.mutants (Format 1 von
//   TMutationReport.Json mit uri und routines) als Records.
// - Anwenden: Der Mutant ersetzt den Bereich Zeile/Spalte bis Endzeile/
//   Endspalte (ab 1, Ende ausschließlich) in den Zeilen der Unit. Steht dort
//   nicht mehr der Originaltext (Datei inzwischen geändert), wird nichts
//   ersetzt. Über Zeilen statt Offsets, damit CRLF oder LF im Puffer keine
//   Rolle spielt.
// - Prüfsumme je Routine: TDUnitXSource.Fingerprint über die Zeilen der
//   Routine (Kopf bis end). Ändert sich nur Einrückung oder ein Kommentar,
//   bleibt sie gleich; dann gelten gemerkte Ergebnisse weiter.
// - Nummer in der Routine: der wievielte Mutant seiner Routine (ab 0) ein
//   Mutant ist. Mit Routine und Prüfsumme bestimmt sie einen Mutanten auch
//   dann, wenn Code über der Routine dazukommt.

interface

type
  /// <summary>Ein Mutant aus der Antwort des Servers.</summary>
  TAtlasMutant = record
    Id: Integer;
    /// <summary>Kennung des Operators ("boundary", …).</summary>
    OperatorId: string;
    Routine: string;
    /// <summary>Bereich ab 1; EndCharacter zeigt hinter das letzte Zeichen.</summary>
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    Original: string;
    Replacement: string;
    Description: string;
  end;

  /// <summary>Zeilen einer Routine mit Mutanten (ab 0, Kopf bis end).</summary>
  TAtlasMutantRoutine = record
    Name: string;
    Line: Integer;
    EndLine: Integer;
  end;

  TAtlasMutantList = record
    Uri: string;
    Mutants: TArray<TAtlasMutant>;
    Routines: TArray<TAtlasMutantRoutine>;
    /// <summary>Zeilen der Routine AName; False ohne.</summary>
    function RoutineOf(const AName: string; out ARoutine: TAtlasMutantRoutine): Boolean;
    /// <summary>Der wievielte Mutant seiner Routine (ab 0) AMutants[AIndex] ist.</summary>
    function IndexInRoutine(AIndex: Integer): Integer;
    /// <summary>Mutanten der Routine AName.</summary>
    function MutantsOf(const AName: string): TArray<TAtlasMutant>;
  end;

  TAtlasMutants = class
  public
    /// <summary>Antwort von atlas.server.mutants lesen. False bei ungültigem Inhalt oder anderem Format;
    /// unvollständige Mutanten fallen weg.</summary>
    class function Parse(const AJson: string; out AList: TAtlasMutantList): Boolean; static;
    /// <summary>ALines mit dem Mutanten AMutant in AMutated. False, wenn der Bereich nicht in ALines liegt oder
    /// dort nicht mehr der Originaltext steht; AMutated ist dann leer.</summary>
    class function Apply(const ALines: TArray<string>; const AMutant: TAtlasMutant;
      out AMutated: TArray<string>): Boolean; static;
    /// <summary>Prüfsumme der Routine ARoutine in ALines; '' wenn ihre Zeilen nicht in ALines liegen.</summary>
    class function RoutineBody(const ALines: TArray<string>; const ARoutine: TAtlasMutantRoutine): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Text.DUnitX;

const
  cFormat = 1;

{ TAtlasMutantList }

function TAtlasMutantList.RoutineOf(const AName: string; out ARoutine: TAtlasMutantRoutine): Boolean;
var
  mRoutine: TAtlasMutantRoutine;
begin
  ARoutine := Default(TAtlasMutantRoutine);
  for mRoutine in Routines do
  begin
    if mRoutine.Name = AName then
    begin
      ARoutine := mRoutine;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasMutantList.IndexInRoutine(AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to AIndex - 1 do
  begin
    if Mutants[mIndex].Routine = Mutants[AIndex].Routine then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasMutantList.MutantsOf(const AName: string): TArray<TAtlasMutant>;
var
  mMutant: TAtlasMutant;
begin
  Result := nil;
  for mMutant in Mutants do
  begin
    if mMutant.Routine = AName then
    begin
      Result := Result + [mMutant];
    end;
  end;
end;

{ TAtlasMutants }

/// <summary>Mutant aus einem Eintrag von "mutants"; False ohne Bereich.</summary>
function MutantOf(AObject: TJSONObject; out AMutant: TAtlasMutant): Boolean;
begin
  AMutant := Default(TAtlasMutant);
  AMutant.Id := TJsonRead.IntOr(AObject, 'id', 0);
  AMutant.OperatorId := TJsonRead.Text(AObject, 'operator');
  AMutant.Routine := TJsonRead.Text(AObject, 'routine');
  AMutant.Line := TJsonRead.IntOr(AObject, 'line', 0);
  AMutant.Character := TJsonRead.IntOr(AObject, 'character', 0);
  AMutant.EndLine := TJsonRead.IntOr(AObject, 'endLine', 0);
  AMutant.EndCharacter := TJsonRead.IntOr(AObject, 'endCharacter', 0);
  AMutant.Original := TJsonRead.Text(AObject, 'original');
  AMutant.Replacement := TJsonRead.Text(AObject, 'replacement');
  AMutant.Description := TJsonRead.Text(AObject, 'description');
  Result := (AMutant.Line > 0) and (AMutant.Character > 0) and (AMutant.EndLine >= AMutant.Line) and
    (AMutant.EndCharacter > 0) and (AMutant.Original <> '');
end;

/// <summary>Routinen aus "routines"; Einträge ohne Namen fallen weg.</summary>
function RoutinesOf(AItems: TJSONArray): TArray<TAtlasMutantRoutine>;
var
  mItem: TJSONValue;
  mObject: TJSONObject;
  mRoutine: TAtlasMutantRoutine;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    mObject := TJsonRead.AsObject(mItem);
    if mObject = nil then
    begin
      Continue;
    end;
    mRoutine := Default(TAtlasMutantRoutine);
    mRoutine.Name := TJsonRead.Text(mObject, 'name');
    mRoutine.Line := TJsonRead.IntOr(mObject, 'line', -1);
    mRoutine.EndLine := TJsonRead.IntOr(mObject, 'endLine', -1);
    if (mRoutine.Name <> '') and (mRoutine.Line >= 0) and (mRoutine.EndLine >= mRoutine.Line) then
    begin
      Result := Result + [mRoutine];
    end;
  end;
end;

class function TAtlasMutants.Parse(const AJson: string; out AList: TAtlasMutantList): Boolean;
var
  mRoot: TJSONObject;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mObject: TJSONObject;
  mMutant: TAtlasMutant;
begin
  AList := Default(TAtlasMutantList);
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    Exit(False);
  end;
  try
    Result := TJsonRead.IntOr(mRoot, 'format', 0) = cFormat;
    if not Result then
    begin
      Exit;
    end;
    AList.Uri := TJsonRead.Text(mRoot, 'uri');
    mItems := TJsonRead.Items(mRoot, 'mutants');
    if mItems <> nil then
    begin
      for mItem in mItems do
      begin
        mObject := TJsonRead.AsObject(mItem);
        if (mObject <> nil) and MutantOf(mObject, mMutant) then
        begin
          AList.Mutants := AList.Mutants + [mMutant];
        end;
      end;
    end;
    AList.Routines := RoutinesOf(TJsonRead.Items(mRoot, 'routines'));
  finally
    mRoot.Free;
  end;
end;

/// <summary>AText mit LF als einzigem Zeilenende.</summary>
function Unified(const AText: string): string;
begin
  // Erst das Paar ersetzen, sonst würde aus CRLF zweimal LF.
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

class function TAtlasMutants.Apply(const ALines: TArray<string>; const AMutant: TAtlasMutant;
  out AMutated: TArray<string>): Boolean;
var
  mFirst, mLast: Integer;
  mSpan, mHead, mTail, mText: string;
  mParts: TArray<string>;
begin
  AMutated := nil;
  mFirst := AMutant.Line - 1;
  mLast := AMutant.EndLine - 1;
  if (mFirst < 0) or (mLast > High(ALines)) or (mLast < mFirst) or
    (AMutant.Character - 1 > Length(ALines[mFirst])) or (AMutant.EndCharacter - 1 > Length(ALines[mLast])) then
  begin
    Exit(False);
  end;
  // Bereich mit LF zwischen den Zeilen; das Original kann CRLF enthalten.
  mHead := Copy(ALines[mFirst], 1, AMutant.Character - 1);
  mTail := Copy(ALines[mLast], AMutant.EndCharacter, MaxInt);
  // Erst das Ende kürzen, dann den Anfang: bei einer Zeile zählt die Endspalte vom Zeilenanfang.
  mParts := Copy(ALines, mFirst, mLast - mFirst + 1);
  mParts[High(mParts)] := Copy(mParts[High(mParts)], 1, AMutant.EndCharacter - 1);
  mParts[0] := Copy(mParts[0], AMutant.Character, MaxInt);
  mSpan := string.Join(#10, mParts);
  if mSpan <> Unified(AMutant.Original) then
  begin
    Exit(False);
  end;
  mText := mHead + Unified(AMutant.Replacement) + mTail;
  // Split liefert für '' kein Element: Die Zeile bleibt dann leer stehen, damit die Zeilen darunter bleiben.
  mParts := mText.Split([#10]);
  if Length(mParts) = 0 then
  begin
    mParts := TArray<string>.Create('');
  end;
  AMutated := Copy(ALines, 0, mFirst) + mParts + Copy(ALines, mLast + 1, MaxInt);
  Result := True;
end;

class function TAtlasMutants.RoutineBody(const ALines: TArray<string>; const ARoutine: TAtlasMutantRoutine): string;
begin
  Result := '';
  if (ARoutine.Line >= 0) and (ARoutine.EndLine <= High(ALines)) and (ARoutine.EndLine >= ARoutine.Line) then
  begin
    Result := TDUnitXSource.Fingerprint(ALines, ARoutine.Line, ARoutine.EndLine);
  end;
end;

end.
