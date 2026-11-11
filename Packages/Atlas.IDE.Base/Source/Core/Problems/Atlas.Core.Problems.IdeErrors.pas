unit Atlas.Core.Problems.IdeErrors;

// Fehler der IDE neben den Atlas-Befunden (#1819, problems.ideErrors), ohne
// VCL und Open Tools API.
// - ToProblem: ein Fehler aus Error Insight (TAtlasIdeError, Werte wie in
//   TOTAError) als TAtlasProblem mit Quelle "IDE"; Zeilen 0-basiert wie im
//   LSP. Art aus Severity wie im LSP (1 Fehler, 2 Warnung, 3 Info, 4 Hinweis),
//   unbekannte Werte gelten als Fehler: Error Insight meldet Fehler.
// - Merge: Abgleich mit den Atlas-Befunden der Datei. Ein Fehler der IDE an
//   derselben Zeile, mit überlappendem Bereich und derselben Art bestätigt
//   den Atlas-Befund (IdeConfirmed, Quelle „Atlas + IDE“) und fällt weg; der
//   Rest bleibt als „nur IDE“ stehen.
// - OriginOf: Quelle für Spalte und Filter „Quelle“ im Fenster
//   „Atlas-Prüfung“ (Atlas, Atlas + IDE, IDE; Compiler, Tests und Aufgaben
//   gehören zu keiner der beiden und heißen Other).
// - TAtlasIdeErrorJournal: Befunde „nur Atlas“ der Regeln für undeklarierte
//   Bezeichner und unbekannte Typen sind Kandidaten für Fehlalarme. Je Stelle
//   einmal eine Zeile fürs Protokoll, ohne Datei- und Bezeichnernamen (#1478):
//   Regel, Art und Zeile.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Quelle eines Befunds (#1819): nur Atlas, Atlas und IDE, nur IDE, anderes (Compiler, Tests,
  /// Aufgaben).</summary>
  TAtlasProblemOrigin = (Atlas, Both, Ide, Other);
  {$SCOPEDENUMS OFF}

  TAtlasIdeErrors = class
  public const
    /// <summary>Quelle der Diagnosen des Servers.</summary>
    cAtlasSource = 'Atlas';
    /// <summary>Text der Quelle eines von der IDE bestätigten Befunds.</summary>
    cBothSource = 'Atlas + IDE';
    /// <summary>Regeln, deren Befunde „nur Atlas“ Fehlalarme sein können (undeklariert, unbekannter Typ).</summary>
    cFalseAlarmRules: array[0..2] of string = ('unresolved-identifier', 'unresolved-type', 'unresolved-attribute');
    /// <summary>Werte von Severity wie im LSP; alle anderen gelten als Fehler.</summary>
    cSeverityWarning = 2;
    cSeverityInformation = 3;
    cSeverityHint = 4;
  public
    /// <summary>Fehler der IDE als Problem mit Quelle "IDE", Zeilen und Spalten 0-basiert.</summary>
    class function ToProblem(const AError: TAtlasIdeError): TAtlasProblem; static;
    class function ToProblems(const AErrors: TArray<TAtlasIdeError>): TArray<TAtlasProblem>; static;
    /// <summary>Severity der IDE als Schweregrad; unbekannt = Fehler.</summary>
    class function SeverityOf(AValue: Integer): TAtlasProblemSeverity; static;
    /// <summary>Befund von Atlas (Quelle "Atlas", auch vom Compiler bestätigt)?</summary>
    class function IsAtlas(const AProblem: TAtlasProblem): Boolean; static;
    /// <summary>Bestätigt AIde den Atlas-Befund AAtlas? Gleiche Zeile, überlappender Bereich (leere Bereiche
    /// zählen als ein Zeichen), gleiche Art (Fehler, Warnung, Info und Hinweis zusammen).</summary>
    class function Matches(const AAtlas, AIde: TAtlasProblem): Boolean; static;
    /// <summary>AProblems (Befunde einer Datei) und AIde (Fehler der IDE derselben Datei) zusammen: bestätigte
    /// Atlas-Befunde mit IdeConfirmed, ohne die bestätigenden Fehler der IDE; nach Position sortiert.</summary>
    class function Merge(const AProblems, AIde: TArray<TAtlasProblem>): TArray<TAtlasProblem>; static;
    class function OriginOf(const AProblem: TAtlasProblem): TAtlasProblemOrigin; static;
    /// <summary>Text der Spalte „Quelle“: "Atlas", "Atlas + IDE", "IDE" bzw. die Quelle selbst.</summary>
    class function OriginText(const AProblem: TAtlasProblem): string; static;
    /// <summary>Gehört die Regel zu den möglichen Fehlalarmen (cFalseAlarmRules)?</summary>
    class function IsFalseAlarmRule(const ACode: string): Boolean; static;
  end;

  /// <summary>Protokoll möglicher Fehlalarme (#1819): Befunde „nur Atlas“ aus cFalseAlarmRules, je Stelle einmal.
  /// Nur im Hauptthread.</summary>
  TAtlasIdeErrorJournal = class
  private
    FSeen: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Zeilen fürs Protokoll aus den abgeglichenen Befunden AMerged der Datei AFileName (Ergebnis
    /// von Merge), ohne Namen: „Error Insight: nur Atlas, Regel unresolved-identifier, Fehler, Zeile 12“.</summary>
    function NewLines(const AFileName: string; const AMerged: TArray<TAtlasProblem>): TArray<string>;
    /// <summary>Gemerkte Stellen vergessen (Speicher geleert).</summary>
    procedure Clear;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  /// <summary>Bits der Spalte in PositionOf; die Zeile steht darüber.</summary>
  cLineShift = 32;
  /// <summary>Teile einer Protokollzeile möglicher Fehlalarme, englisch wie die übrigen Protokollzeilen.</summary>
  cJournalRule = 'Error Insight: Atlas only, rule ';
  cJournalSeparator = ', ';
  cJournalLine = ', line ';

{ TAtlasIdeErrors }

class function TAtlasIdeErrors.SeverityOf(AValue: Integer): TAtlasProblemSeverity;
begin
  case AValue of
    cSeverityWarning:
      Result := TAtlasProblemSeverity.Warning;
    cSeverityInformation:
      Result := TAtlasProblemSeverity.Information;
    cSeverityHint:
      Result := TAtlasProblemSeverity.Hint;
  else
    Result := TAtlasProblemSeverity.Error;
  end;
end;

class function TAtlasIdeErrors.ToProblem(const AError: TAtlasIdeError): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := Max(0, AError.StartLine - 1);
  Result.StartCharacter := Max(0, AError.StartCharIndex);
  Result.EndLine := Max(Result.StartLine, AError.StopLine - 1);
  Result.EndCharacter := Max(0, AError.StopCharIndex);
  if (Result.EndLine = Result.StartLine) and (Result.EndCharacter < Result.StartCharacter) then
  begin
    Result.EndCharacter := Result.StartCharacter;
  end;
  Result.Severity := SeverityOf(AError.Severity);
  Result.Source := TAtlasProblem.cIdeSource;
  Result.Message := Trim(AError.Text);
end;

class function TAtlasIdeErrors.ToProblems(const AErrors: TArray<TAtlasIdeError>): TArray<TAtlasProblem>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AErrors));
  for mIndex := 0 to High(AErrors) do
  begin
    Result[mIndex] := ToProblem(AErrors[mIndex]);
  end;
end;

class function TAtlasIdeErrors.IsAtlas(const AProblem: TAtlasProblem): Boolean;
begin
  Result := SameText(AProblem.Source, cAtlasSource) or SameText(AProblem.Source, TAtlasProblem.cConfirmedSource);
end;

/// <summary>Fehler, Warnung bzw. Info (Information und Hinweis).</summary>
function KindRank(ASeverity: TAtlasProblemSeverity): Integer;
begin
  Result := Min(Ord(ASeverity), Ord(TAtlasProblemSeverity.Information));
end;

/// <summary>Stelle als eine Zahl: Zeile vor Spalte.</summary>
function PositionOf(ALine, ACharacter: Integer): Int64;
begin
  Result := (Int64(ALine) shl cLineShift) + Max(0, ACharacter);
end;

class function TAtlasIdeErrors.Matches(const AAtlas, AIde: TAtlasProblem): Boolean;
var
  mStartA, mEndA, mStartB, mEndB: Int64;
begin
  if (AAtlas.StartLine <> AIde.StartLine) or (KindRank(AAtlas.Severity) <> KindRank(AIde.Severity)) then
  begin
    Exit(False);
  end;
  mStartA := PositionOf(AAtlas.StartLine, AAtlas.StartCharacter);
  mEndA := Max(PositionOf(AAtlas.EndLine, AAtlas.EndCharacter), mStartA + 1);
  mStartB := PositionOf(AIde.StartLine, AIde.StartCharacter);
  mEndB := Max(PositionOf(AIde.EndLine, AIde.EndCharacter), mStartB + 1);
  Result := (mStartA < mEndB) and (mStartB < mEndA);
end;

/// <summary>Index des ersten noch freien Fehlers der IDE, der AAtlas bestätigt; -1 ohne.</summary>
function MatchingIndex(const AAtlas: TAtlasProblem; const AIde: TArray<TAtlasProblem>;
  const AUsed: TArray<Boolean>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AIde) do
  begin
    if not AUsed[mIndex] and TAtlasIdeErrors.Matches(AAtlas, AIde[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure SortByPosition(var AProblems: TArray<TAtlasProblem>);
begin
  TArray.Sort<TAtlasProblem>(AProblems, TComparer<TAtlasProblem>.Construct(
    function(const A, B: TAtlasProblem): Integer
    begin
      Result := A.StartLine - B.StartLine;
      if Result = 0 then
      begin
        Result := A.StartCharacter - B.StartCharacter;
      end;
      if Result = 0 then
      begin
        Result := Ord(A.Severity) - Ord(B.Severity);
      end;
      // Nicht stabil sortiert: bei Gleichstand Atlas vor IDE, dann nach Meldung.
      if Result = 0 then
      begin
        Result := Ord(A.IsIde) - Ord(B.IsIde);
      end;
      if Result = 0 then
      begin
        Result := CompareStr(A.Message, B.Message);
      end;
    end));
end;

class function TAtlasIdeErrors.Merge(const AProblems, AIde: TArray<TAtlasProblem>): TArray<TAtlasProblem>;
var
  mUsed: TArray<Boolean>;
  mIndex, mFound, mCount: Integer;
begin
  Result := Copy(AProblems);
  if AIde = nil then
  begin
    Exit;
  end;
  SetLength(mUsed, Length(AIde));
  for mIndex := 0 to High(Result) do
  begin
    if IsAtlas(Result[mIndex]) then
    begin
      mFound := MatchingIndex(Result[mIndex], AIde, mUsed);
      if mFound >= 0 then
      begin
        mUsed[mFound] := True;
        Result[mIndex].IdeConfirmed := True;
      end;
    end;
  end;
  mCount := Length(Result);
  SetLength(Result, mCount + Length(AIde));
  for mIndex := 0 to High(AIde) do
  begin
    if not mUsed[mIndex] then
    begin
      Result[mCount] := AIde[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
  SortByPosition(Result);
end;

class function TAtlasIdeErrors.OriginOf(const AProblem: TAtlasProblem): TAtlasProblemOrigin;
begin
  if AProblem.IsIde then
  begin
    Result := TAtlasProblemOrigin.Ide;
  end
  else if not IsAtlas(AProblem) then
  begin
    Result := TAtlasProblemOrigin.Other;
  end
  else if AProblem.IdeConfirmed then
  begin
    Result := TAtlasProblemOrigin.Both;
  end
  else
  begin
    Result := TAtlasProblemOrigin.Atlas;
  end;
end;

class function TAtlasIdeErrors.OriginText(const AProblem: TAtlasProblem): string;
begin
  case OriginOf(AProblem) of
    TAtlasProblemOrigin.Atlas:
      Result := cAtlasSource;
    TAtlasProblemOrigin.Both:
      Result := cBothSource;
    TAtlasProblemOrigin.Ide:
      Result := TAtlasProblem.cIdeSource;
  else
    Result := AProblem.Source;
  end;
end;

class function TAtlasIdeErrors.IsFalseAlarmRule(const ACode: string): Boolean;
var
  mRule: string;
begin
  for mRule in cFalseAlarmRules do
  begin
    if SameText(mRule, ACode) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasIdeErrorJournal }

constructor TAtlasIdeErrorJournal.Create;
begin
  inherited Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasIdeErrorJournal.Destroy;
begin
  FSeen.Free;
  inherited Destroy;
end;

/// <summary>Art für das Protokoll, englisch wie die übrigen Protokollzeilen.</summary>
function KindName(ASeverity: TAtlasProblemSeverity): string;
begin
  case KindRank(ASeverity) of
    0:
      Result := 'error';
    1:
      Result := 'warning';
  else
    Result := 'info';
  end;
end;

function TAtlasIdeErrorJournal.NewLines(const AFileName: string;
  const AMerged: TArray<TAtlasProblem>): TArray<string>;
var
  mProblem: TAtlasProblem;
  mKey: string;
begin
  Result := nil;
  for mProblem in AMerged do
  begin
    if (TAtlasIdeErrors.OriginOf(mProblem) <> TAtlasProblemOrigin.Atlas) or
      not TAtlasIdeErrors.IsFalseAlarmRule(mProblem.Code) then
    begin
      Continue;
    end;
    mKey := LowerCase(AFileName) + '|' + LowerCase(mProblem.Code) + '|' + IntToStr(mProblem.StartLine) + ':' +
      IntToStr(mProblem.StartCharacter);
    if FSeen.ContainsKey(mKey) then
    begin
      Continue;
    end;
    FSeen.Add(mKey, True);
    Result := Result + [cJournalRule + LowerCase(mProblem.Code) + cJournalSeparator + KindName(mProblem.Severity) +
      cJournalLine + IntToStr(mProblem.StartLine + 1)];
  end;
end;

procedure TAtlasIdeErrorJournal.Clear;
begin
  FSeen.Clear;
end;

end.
