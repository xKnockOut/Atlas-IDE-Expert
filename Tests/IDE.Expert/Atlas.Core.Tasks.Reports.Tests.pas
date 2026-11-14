unit Atlas.Core.Tasks.Reports.Tests;

// Tests für Befunde von Projektaufgaben als Probleme (#900): Quelle,
// Schwere, 0-basierte Lage, Bereich mit und ohne Spalte, Fundstellen ohne
// Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskReportsTests = class
  public
    [Test]
    procedure FindingsBecomeProblemsOfTheTask;
    [Test]
    procedure RangeFollowsColumnOrLine;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Reports;

function Finding(const AFileName: string; ALine, AColumn: Integer; ASeverity: TAtlasTaskSeverity;
  const AMessage: string): TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskFinding);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Severity := ASeverity;
  Result.Message := AMessage;
end;

function Lines: TAtlasTaskReadLine;
begin
  Result :=
    function(const AFileName: string; ALine: Integer; out AText: string): Boolean
    begin
      AText := '';
      Result := SameText(AFileName, 'C:\p\Kunde.pas');
      if Result then
        case ALine of
          0: AText := 'unit Kunde;';
          87: AText := '    if X is not TFoo then  ';
        else
          AText := '';
        end;
    end;
end;

{ TAtlasTaskReportsTests }

procedure TAtlasTaskReportsTests.FindingsBecomeProblemsOfTheTask;
var
  mFound: TArray<TPair<string, TAtlasProblem>>;
begin
  mFound := TAtlasTaskReports.Problems('Delphi-12-Prüfung', TArray<TAtlasTaskFinding>.Create(
    Finding('C:\p\Kunde.pas', 88, 0, TAtlasTaskSeverity.Error, '„is not“ gibt es erst ab Delphi 13'),
    Finding('', 0, 0, TAtlasTaskSeverity.Error, 'ohne Datei'),
    Finding('C:\p\Kunde.pas', 0, 0, TAtlasTaskSeverity.Warning, ''),
    Finding('C:\p\Fremd.pas', 3, 0, TAtlasTaskSeverity.Info, 'Hinweis')), Lines());
  Assert.AreEqual(3, Integer(Length(mFound)), 'Fundstellen ohne Datei zählen nur in der Ausgabe');
  Assert.AreEqual('C:\p\Kunde.pas', mFound[0].Key);
  Assert.AreEqual('Delphi-12-Prüfung', mFound[0].Value.Source);
  Assert.AreEqual(87, mFound[0].Value.StartLine, '0-basiert');
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, mFound[0].Value.Severity);
  Assert.AreEqual(0, mFound[1].Value.StartLine, 'ohne Zeile die erste');
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Warning, mFound[1].Value.Severity);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Information, mFound[2].Value.Severity);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error,
    TAtlasTaskReports.Severity(TAtlasTaskSeverity.Error));
end;

procedure TAtlasTaskReportsTests.RangeFollowsColumnOrLine;
var
  mFound: TArray<TPair<string, TAtlasProblem>>;
begin
  mFound := TAtlasTaskReports.Problems('t', TArray<TAtlasTaskFinding>.Create(
    Finding('C:\p\Kunde.pas', 88, 0, TAtlasTaskSeverity.Error, 'a'),
    Finding('C:\p\Kunde.pas', 88, 10, TAtlasTaskSeverity.Error, 'b'),
    Finding('C:\p\Kunde.pas', 88, 9, TAtlasTaskSeverity.Error, 'c'),
    Finding('C:\p\Fremd.pas', 3, 5, TAtlasTaskSeverity.Error, 'd'),
    Finding('C:\p\Fremd.pas', 3, 0, TAtlasTaskSeverity.Error, 'e')), Lines());
  Assert.AreEqual(4, mFound[0].Value.StartCharacter, 'ohne Einrückung');
  Assert.AreEqual(25, mFound[0].Value.EndCharacter, 'ohne Leerraum am Ende');
  Assert.AreEqual(9, mFound[1].Value.StartCharacter);
  Assert.AreEqual(11, mFound[1].Value.EndCharacter, 'das Wort „is“');
  Assert.AreEqual(9, mFound[2].Value.EndCharacter, 'Leerzeichen: ein Zeichen');
  Assert.AreEqual(4, mFound[3].Value.StartCharacter, 'Datei nicht lesbar');
  Assert.AreEqual(5, mFound[3].Value.EndCharacter);
  Assert.AreEqual(0, mFound[4].Value.StartCharacter);
  Assert.AreEqual(1, mFound[4].Value.EndCharacter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskReportsTests);

end.
