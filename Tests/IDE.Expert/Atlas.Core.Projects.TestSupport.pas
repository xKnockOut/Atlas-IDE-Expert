unit Atlas.Core.Projects.TestSupport;

// Gemeinsame Hilfen der Tests rund um Projektübersichten (Projekte, Startseite, Testergebnisse).

interface

uses
  Atlas.Plugin.Projects.Contract.Summary;

/// <summary>Fehlgeschlagener Test ATest mit Meldung und Fundstelle.</summary>
function Failure(const ATest, AMessage, AFile: string; ALine: Integer): TAtlasProjectTestFailure;
/// <summary>Übersicht von C:\Projekte\Demo.dproj auf dem Zweig main ohne Änderungen.</summary>
function OnMain: TAtlasProjectSummary;

implementation

function Failure(const ATest, AMessage, AFile: string; ALine: Integer): TAtlasProjectTestFailure;
begin
  Result.Test := ATest;
  Result.Message := AMessage;
  Result.FileName := AFile;
  Result.Line := ALine;
end;

function OnMain: TAtlasProjectSummary;
begin
  Result := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Result.Vcs.Known := True;
  Result.Vcs.Kind := 'git';
  Result.Vcs.Branch := 'main';
  Result.Vcs.Revision := 'abcdef0123456789';
  Result.Vcs.Changed := 0;
  Result.Vcs.Ahead := 0;
  Result.Vcs.Behind := 0;
end;

end.
