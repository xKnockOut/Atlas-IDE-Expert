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
    MaxProblems = 2000;
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

class function TAtlasTaskReports.Problems(const ATask: string; const AFindings: TAtlasTaskFindings;
  const AReadLine: TAtlasTaskReadLine): TArray<TPair<string, TAtlasProblem>>;
var
  Finding: TAtlasTaskFinding;
  Problem: TAtlasProblem;
  Pair: TPair<string, TAtlasProblem>;
  Text: string;
  Known: Boolean;
  Stop: Integer;
begin
  Result := nil;
  for Finding in AFindings do
  begin
    if Finding.FileName = '' then
      Continue;
    if Length(Result) >= MaxProblems then
      Break;
    Problem := Default(TAtlasProblem);
    if Finding.Line > 0 then
      Problem.StartLine := Finding.Line - 1;
    Problem.EndLine := Problem.StartLine;
    Known := Assigned(AReadLine) and AReadLine(Finding.FileName, Problem.StartLine, Text);
    if Finding.Column > 0 then
    begin
      Problem.StartCharacter := Finding.Column - 1;
      Stop := Problem.StartCharacter;
      if Known then
        while (Stop < Length(Text)) and TTextChars.IsIdentChar(Text[Stop + 1]) do
          Inc(Stop);
      if Stop = Problem.StartCharacter then
        Stop := Problem.StartCharacter + 1;
      Problem.EndCharacter := Stop;
    end
    else if Known and (Trim(Text) <> '') then
    begin
      Stop := 0;
      while (Stop < Length(Text)) and CharInSet(Text[Stop + 1], [' ', #9]) do
        Inc(Stop);
      Problem.StartCharacter := Stop;
      Problem.EndCharacter := Length(TrimRight(Text));
    end
    else
      Problem.EndCharacter := 1;
    Problem.Severity := Severity(Finding.Severity);
    Problem.Code := Finding.Code;
    Problem.Source := ATask;
    Problem.Message := Finding.Message;
    Pair.Key := Finding.FileName;
    Pair.Value := Problem;
    Result := Result + [Pair];
  end;
end;

end.
