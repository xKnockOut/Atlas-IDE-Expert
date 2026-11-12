unit Atlas.Core.Tracker.SprintStart;

// Beim Beginnen in den laufenden Sprint aufnehmen (#2128, issues.sprintOnStart),
// ohne VCL und Open Tools API.
// - Quelle ist der zuletzt gelesene Stand des eingestellten Boards
//   (Zwischenspeicher der Sprint-Kachel, sonst des Boards, #1272/#1277); ohne
//   Stand fragt „Beginnen“ nicht und geht nicht ins Netz.
// - Missing: Der Stand ist ein YouTrack-Agile-Board mit einem laufenden
//   Sprint (nicht archiviert, Beginn erreicht, Ende nicht erreicht; fehlende
//   Daten zählen als offen), und das Issue ist keine Karte darin. Ein Stand
//   mit cMaxCards Karten kann unvollständig sein: dann keine Frage.
//   GitHub-Projekte fragen nicht (der Anbieter schreibt keine Iteration).
// - Geschrieben wird mit TAtlasTrackerWrite.Sprint im Befehl des Beginnens.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
  TAtlasSprintStart = class
  public
    /// <summary>Sprint von ASnapshot läuft zum Zeitpunkt ANowUtc.</summary>
    class function Running(const ASnapshot: TAtlasBoardSnapshot; ANowUtc: TDateTime): Boolean; static;
    /// <summary>ASnapshot hat einen laufenden Sprint ohne die Karte AKey; ASprint ist dann dieser Sprint, sonst
    /// TAtlasTrackerSprintRef.None.</summary>
    class function Missing(const ASnapshot: TAtlasBoardSnapshot; const AKey: string; ANowUtc: TDateTime;
      out ASprint: TAtlasTrackerSprintRef): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasSprintStart }

class function TAtlasSprintStart.Running(const ASnapshot: TAtlasBoardSnapshot; ANowUtc: TDateTime): Boolean;
begin
  Result := (ASnapshot.Kind = TAtlasBoardKind.Agile) and (Trim(ASnapshot.Board.Name) <> '') and
    (Trim(ASnapshot.Sprint.Name) <> '') and not ASnapshot.Sprint.Archived;
  if Result and (ASnapshot.Sprint.Start > 0) then
  begin
    Result := ASnapshot.Sprint.Start <= ANowUtc;
  end;
  if Result and (ASnapshot.Sprint.Finish > 0) then
  begin
    Result := ANowUtc < ASnapshot.Sprint.Finish;
  end;
end;

class function TAtlasSprintStart.Missing(const ASnapshot: TAtlasBoardSnapshot; const AKey: string;
  ANowUtc: TDateTime; out ASprint: TAtlasTrackerSprintRef): Boolean;
begin
  ASprint := TAtlasTrackerSprintRef.None;
  Result := (Trim(AKey) <> '') and Running(ASnapshot, ANowUtc) and
    (Length(ASnapshot.Cards) < TAtlasBoardSnapshot.cMaxCards) and (ASnapshot.CardIndex(AKey) < 0);
  if Result then
  begin
    ASprint := TAtlasTrackerSprintRef.Create(ASnapshot.Board.Name, ASnapshot.Sprint.Name, ASnapshot.Sprint.Finish);
  end;
end;

end.
