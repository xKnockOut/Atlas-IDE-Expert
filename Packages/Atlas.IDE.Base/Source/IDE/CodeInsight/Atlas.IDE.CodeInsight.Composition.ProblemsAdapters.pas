unit Atlas.IDE.CodeInsight.Composition.ProblemsAdapters;

// Server und IDE für den Ablauf der Probleme (#398) für die Kompositionswurzel: Sitzung und Holthreads
// (TAtlasIdeProblemsServer) sowie Editor, Module, Debugger und Fehler der IDE (TAtlasIdeProblemsEditors). Nur diese
// Unit erzeugt die Adapter; der Controller bekommt sie über die Fabriken TAtlasProblemsController.ServerFactory und
// EditorsFactory.

interface

/// <summary>Fabriken der Adapter der Probleme einsetzen; ab der Unit-Initialisierung, vor dem ersten
/// Controller.</summary>
procedure InstallProblemsAdapters;

implementation

uses
  Atlas.Core.Problems.Contract.Sync,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Adapters.Editors,
  Atlas.IDE.Problems.Adapters.Server;

procedure InstallProblemsAdapters;
begin
  TAtlasProblemsController.ServerFactory :=
    function(const ASession: TAtlasProblemsSessionFunc; const ADocument: TAtlasProblemsDocumentProc;
      const AWorkspace: TAtlasProblemsWorkspaceProc; const ALog: TAtlasProblemsLogProc): IAtlasProblemsServer
    begin
      Result := TAtlasIdeProblemsServer.Create(ASession, ADocument, AWorkspace, ALog);
    end;
  TAtlasProblemsController.EditorsFactory :=
    function: IAtlasProblemsEditors
    begin
      Result := TAtlasIdeProblemsEditors.Create;
    end;
end;

end.
