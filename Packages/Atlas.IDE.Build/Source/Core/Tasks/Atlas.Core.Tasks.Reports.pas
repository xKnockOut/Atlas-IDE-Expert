unit Atlas.Core.Tasks.Reports;

// Befunde einer Projektaufgabe als Probleme (#900), ohne Open Tools API:
// - Je Fundstelle mit Datei ein Problem mit Quelle = Aufgabenname; Zeile und
//   Spalte der Ausgabe sind 1-basiert, Probleme 0-basiert. Ohne Zeile steht
//   das Problem in der ersten Zeile.
// - Bereich: ab der Spalte das Wort dort (sonst ein Zeichen), ohne Spalte die
//   Zeile ohne Einrückung und Leerraum am Ende, wie die Fehlschläge der
//   Tests. Den Text der Zeile liefert AReadLine (Puffer oder Platte); ohne
//   ihn ein Zeichen ab der Spalte.
// - Höchstens MaxProblems Probleme je Lauf; die übrigen Fundstellen bleiben
//   in der Ausgabe.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers;

type
  /// <summary>Text der Zeile ALine (0-basiert) der Datei AFileName; False, wenn nicht lesbar.</summary>
  TAtlasTaskReadLine = reference to function(const AFileName: string; ALine: Integer; out AText: string): Boolean;

  TAtlasTaskReports = class
  public const
    cMaxProblems = 2000;
  public
    class function Severity(ASeverity: TAtlasTaskSeverity): TAtlasProblemSeverity; static;
    /// <summary>Probleme der Fundstellen AFindings der Aufgabe ATask (Quelle).</summary>
    class function Problems(const ATask: string; const AFindings: TAtlasTaskFindings;
      const AReadLine: TAtlasTaskReadLine): TArray<TPair<string, TAtlasProblem>>; static;
  end;

implementation

uses
  Atlas.Text.Chars;

{ TAtlasTaskReports }

class function TAtlasTaskReports.Severity(ASeverity: TAtlasTaskSeverity): TAtlasProblemSeverity;
begin
  case ASeverity of
    TAtlasTaskSeverity.Warning:
      Result := TAtlasProblemSeverity.Warning;
    TAtlasTaskSeverity.Info:
      Result := TAtlasProblemSeverity.Information;
  else
    Result := TAtlasProblemSeverity.Error;
  end;
end;

/// <summary>Bereich ab der Spalte AColumn (0-basiert): das Wort dort, sonst ein Zeichen.</summary>
procedure ColumnRange(var AProblem: TAtlasProblem; AColumn: Integer; AKnown: Boolean; const AText: string);
var
  mStop: Integer;
begin
  AProblem.StartCharacter := AColumn;
  mStop := AColumn;
  if AKnown then
  begin
    while (mStop < Length(AText)) and TTextChars.IsIdentChar(AText[mStop + 1]) do
    begin
      Inc(mStop);
    end;
  end;
  if mStop = AColumn then
  begin
    mStop := AColumn + 1;
  end;
  AProblem.EndCharacter := mStop;
end;

/// <summary>Bereich der ganzen Zeile ohne Einrückung und Leerraum am Ende.</summary>
procedure LineRange(var AProblem: TAtlasProblem; const AText: string);
var
  mStop: Integer;
begin
  mStop := 0;
  while (mStop < Length(AText)) and CharInSet(AText[mStop + 1], [' ', #9]) do
  begin
    Inc(mStop);
  end;
  AProblem.StartCharacter := mStop;
  AProblem.EndCharacter := Length(TrimRight(AText));
end;

function FindingProblem(const ATask: string; const AFinding: TAtlasTaskFinding;
  const AReadLine: TAtlasTaskReadLine): TAtlasProblem;
var
  mText: string;
  mKnown: Boolean;
begin
  Result := Default(TAtlasProblem);
  if AFinding.Line > 0 then
  begin
    Result.StartLine := AFinding.Line - 1;
  end;
  Result.EndLine := Result.StartLine;
  mKnown := Assigned(AReadLine) and AReadLine(AFinding.FileName, Result.StartLine, mText);
  if AFinding.Column > 0 then
  begin
    ColumnRange(Result, AFinding.Column - 1, mKnown, mText);
  end
  else if mKnown and (Trim(mText) <> '') then
  begin
    LineRange(Result, mText);
  end
  else
  begin
    Result.EndCharacter := 1;
  end;
  Result.Severity := TAtlasTaskReports.Severity(AFinding.Severity);
  Result.Code := AFinding.Code;
  Result.Source := ATask;
  Result.Message := AFinding.Message;
end;

class function TAtlasTaskReports.Problems(const ATask: string; const AFindings: TAtlasTaskFindings;
  const AReadLine: TAtlasTaskReadLine): TArray<TPair<string, TAtlasProblem>>;
var
  mFinding: TAtlasTaskFinding;
  mPair: TPair<string, TAtlasProblem>;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    if mFinding.FileName = '' then
    begin
      Continue;
    end;
    if Length(Result) >= cMaxProblems then
    begin
      Break;
    end;
    mPair.Key := mFinding.FileName;
    mPair.Value := FindingProblem(ATask, mFinding, AReadLine);
    Result := Result + [mPair];
  end;
end;

end.
