unit Atlas.Core.Tracker.Contract.TestResults;

// Vertrag der Kachel „Testergebnisse“ (#763, #1443): Zeilen, Fehlschläge und
// Ansicht, die Atlas.Core.Tracker.TestResults berechnet, die IDE-Seite liefert
// und Atlas.UI.Tracker.TestResults zeichnet. Nur Datentypen.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Contract.Summary;

type
{$SCOPEDENUMS ON}
  /// <summary>Ampel: Unknown grau, Passed grün, Warning gelb, Failed rot.</summary>
  TAtlasTestLevel = (Unknown, Passed, Warning, Failed);
  TAtlasTestMismatch = (None, LocalGreenServerRed, LocalRedServerGreen);
{$SCOPEDENUMS OFF}

  TAtlasTestRow = record
    /// <summary>Projektdatei; Schlüssel der Auswahl.</summary>
    Project: string;
    /// <summary>Name des Testprojekts, sonst des Projekts, ohne Endung.</summary>
    Name: string;
    /// <summary>Testprojekt des letzten Laufs (.dproj); '' ohne lokalen Lauf.</summary>
    TestProject: string;
    Local: TAtlasProjectTests;
    LocalLevel: TAtlasTestLevel;
    /// <summary>Für das Projekt ist ein Build-Server eingetragen (und welcomePage.tests.ci an).</summary>
    HasCi: Boolean;
    Job: TAtlasCiJob;
    /// <summary>Stand vom Server, nur wenn er zum Job passt; sonst Empty.</summary>
    Ci: TAtlasProjectCi;
    CiLevel: TAtlasTestLevel;
    /// <summary>Der letzte Abruf schlug fehl, gezeigt wird der Stand vom Ci.At.</summary>
    CiStale: Boolean;
    CiQuerying: Boolean;
    Mismatch: TAtlasTestMismatch;
    /// <summary>Höchste Ampel aus lokal und Server.</summary>
    function Level: TAtlasTestLevel;
  end;

  TAtlasTestFailureItem = record
    /// <summary>Voller Name (Unit.Fixture.Methode).</summary>
    Test: string;
    Message: string;
    /// <summary>Nur lokal: Datei (absolut) und Zeile ab 1; sonst '' und 0.</summary>
    FileName: string;
    Line: Integer;
    /// <summary>Im letzten lokalen Lauf fehlgeschlagen.</summary>
    Local: Boolean;
    /// <summary>Im letzten Build auf dem Server fehlgeschlagen.</summary>
    Server: Boolean;
  end;

  TAtlasTestResultsView = record
    Rows: TArray<TAtlasTestRow>;
    /// <summary>Index der gewählten Zeile; -1 ohne Zeilen.</summary>
    Selected: Integer;
    /// <summary>Fehlschläge der gewählten Zeile.</summary>
    Failures: TArray<TAtlasTestFailureItem>;
    /// <summary>Weitere Fehlschläge, die nicht in der Liste stehen.</summary>
    More: Integer;
    /// <summary>Namen für „Fehlgeschlagene erneut ausführen“.</summary>
    Rerun: TArray<string>;
    /// <summary>Die langsamsten Tests des lokalen Laufs der gewählten Zeile (#1772).</summary>
    Slowest: TArray<TAtlasProjectSlowTest>;
    function Empty: Boolean;
    function SelectedRow(out ARow: TAtlasTestRow): Boolean;
  end;

implementation

{ TAtlasTestRow }

function TAtlasTestRow.Level: TAtlasTestLevel;
begin
  Result := LocalLevel;
  if Ord(CiLevel) > Ord(Result) then
  begin
    Result := CiLevel;
  end;
end;

{ TAtlasTestResultsView }

function TAtlasTestResultsView.Empty: Boolean;
begin
  Result := Length(Rows) = 0;
end;

function TAtlasTestResultsView.SelectedRow(out ARow: TAtlasTestRow): Boolean;
begin
  Result := (Selected >= 0) and (Selected < Length(Rows));
  if Result then
  begin
    ARow := Rows[Selected];
  end
  else
  begin
    ARow := Default(TAtlasTestRow);
  end;
end;

end.
