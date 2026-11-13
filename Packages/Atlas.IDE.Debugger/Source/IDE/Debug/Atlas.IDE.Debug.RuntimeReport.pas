unit Atlas.IDE.Debug.RuntimeReport;

// Befehle „Absturz- oder Leckbericht einfügen …“ und „Markierungen des Laufzeitberichts entfernen“ (#74) des
// Moduls Debugger: Der Text der Zwischenablage (madExcept, EurekaLog, JclDebug, Meldung einer Exception, FastMM-Log
// oder Meldung von ReportMemoryLeaksOnShutdown) geht mit dem aktiven Projekt an atlas.server.runtimeReport. Der
// Server hängt die Diagnosen an die Stellen im Projekt; hier erscheinen die Stapel in der Meldungsansicht, Zeilen
// im Projekt anklickbar. Antworten kommen über TAtlasIdeHost und nur, solange der Scope des Moduls offen ist.

interface

uses
  Atlas.Core.Modules.Contract;

type
  TAtlasIdeRuntimeReport = class
  public const
    cTimeoutMs = 30000;
    /// <summary>Höchstens so viele Leckgruppen bzw. Threads in der Meldungsansicht.</summary>
    cMaxStacks = 50;
  public
    /// <summary>Bericht aus der Zwischenablage auswerten lassen.</summary>
    class procedure Paste(const AScope: IAtlasModuleScope); static;
    /// <summary>Diagnosen des letzten Berichts entfernen.</summary>
    class procedure Clear(const AScope: IAtlasModuleScope); static;
    /// <summary>Leckbericht mit Aufrufstapeln vom Ende einer Debug-Sitzung an den Server geben, damit er die
    /// Erzeugungsstellen im Editor markiert. Die Stapel zeigt das Fenster „Atlas-Lecks“; hier kommen nur der Stand
    /// der Map und die Zahl der Markierungen.</summary>
    class procedure Mark(const AScope: IAtlasModuleScope; const AProject, AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.RuntimeReport,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Files,
  Atlas.UI.Debug.Strings;

const
  cMessageGroup = 'Atlas';
  cFrameIndent = '    ';

procedure Say(AId: TAtlasDebugTextId; const AArgs: array of const);
begin
  TAtlasIdeHost.Message(TAtlasDebugStrings.Fmt(AId, AArgs));
end;

function Group(const AMessages: IOTAMessageServices): IOTAMessageGroup;
begin
  Result := AMessages.GetGroup(cMessageGroup);
  if Result = nil then
  begin
    Result := AMessages.AddMessageGroup(cMessageGroup);
  end;
end;

{ Ausgabe }

function FrameText(const AFrame: TAtlasRuntimeFrame; AIsSite: Boolean; AKind: TAtlasRuntimeReportKind): string;
begin
  Result := AFrame.Location;
  if (AFrame.Line > 0) and (AFrame.FileName = '') then
  begin
    Result := Result + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RuntimeReportLine, [AFrame.Line]);
  end;
  if not AIsSite then
  begin
    Exit;
  end;
  if AKind = TAtlasRuntimeReportKind.Crash then
  begin
    Result := Result + TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportCrashSite);
  end
  else
  begin
    Result := Result + TAtlasDebugStrings.Text(TAtlasDebugTextId.RuntimeReportLeakSite);
  end;
end;

procedure AddFrame(const AMessages: IOTAMessageServices; const AReport: TAtlasRuntimeReport;
  const AFrame: TAtlasRuntimeFrame; AIsSite: Boolean);
var
  mLineRef: Pointer;
begin
  if (AFrame.FileName <> '') and (AFrame.Line > 0) then
  begin
    AMessages.AddToolMessage(AFrame.FileName, FrameText(AFrame, AIsSite, AReport.Kind), AReport.Source, AFrame.Line,
      1, nil, mLineRef, Group(AMessages));
  end
  else
  begin
    AMessages.AddTitleMessage(cFrameIndent + Trim(AFrame.Address + ' ' + AFrame.Module) + '  ' +
      FrameText(AFrame, AIsSite, AReport.Kind), Group(AMessages));
  end;
end;

function StackTitle(const AReport: TAtlasRuntimeReport; const AStack: TAtlasRuntimeStack): string;
begin
  if AReport.Kind = TAtlasRuntimeReportKind.Leaks then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RuntimeReportGroup, [AStack.Name, AStack.Count, AStack.Size]);
  end
  else if AStack.Crashed then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RuntimeReportCrashedThread, [AStack.Name]);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RuntimeReportThread, [AStack.Name]);
  end;
end;

procedure AddStacks(const AMessages: IOTAMessageServices; const AReport: TAtlasRuntimeReport);
var
  mStack, mFrame: Integer;
begin
  for mStack := 0 to High(AReport.Stacks) do
  begin
    if mStack >= TAtlasIdeRuntimeReport.cMaxStacks then
    begin
      AMessages.AddTitleMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RuntimeReportMore,
        [Length(AReport.Stacks) - mStack]), Group(AMessages));
      Break;
    end;
    AMessages.AddTitleMessage(StackTitle(AReport, AReport.Stacks[mStack]), Group(AMessages));
    for mFrame := 0 to High(AReport.Stacks[mStack].Frames) do
    begin
      AddFrame(AMessages, AReport, AReport.Stacks[mStack].Frames[mFrame], mFrame = AReport.Stacks[mStack].Site);
    end;
  end;
end;

procedure SayMapStatus(const AReport: TAtlasRuntimeReport);
begin
  // Passt die Map oder fehlt sie ganz (Zeilen mit Debug-Informationen), gibt es nichts zu sagen.
  if AReport.MapStatus = TAtlasRuntimeMapStatus.Missing then
  begin
    Say(TAtlasDebugTextId.RuntimeReportMapMissing, [AReport.MapName]);
  end
  else if AReport.MapStatus = TAtlasRuntimeMapStatus.Differs then
  begin
    Say(TAtlasDebugTextId.RuntimeReportMapDiffers, [AReport.MapName]);
  end;
end;

procedure Show(const AReport: TAtlasRuntimeReport);
var
  mMessages: IOTAMessageServices;
begin
  if AReport.Kind = TAtlasRuntimeReportKind.None then
  begin
    Say(TAtlasDebugTextId.RuntimeReportNone, []);
    Exit;
  end;
  if AReport.Kind = TAtlasRuntimeReportKind.Crash then
  begin
    Say(TAtlasDebugTextId.RuntimeReportCrashTitle, [AReport.Source, AReport.Title]);
  end
  else
  begin
    Say(TAtlasDebugTextId.RuntimeReportLeakTitle, [AReport.Source, AReport.Title]);
  end;
  SayMapStatus(AReport);
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    AddStacks(mMessages, AReport);
  end;
  Say(TAtlasDebugTextId.RuntimeReportMarked, [AReport.Diagnostics]);
  TAtlasIdeHost.ShowMessages;
end;

/// <summary>Antwort des Servers (Hauptthread); eigene Routine, damit der Rahmen nichts weiter hält.</summary>
function ReportAnswer: TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mReport: TAtlasRuntimeReport;
    begin
      if not TAtlasRuntimeReports.FromJson(AAnswer, mReport) then
      begin
        Say(TAtlasDebugTextId.RuntimeReportNoServer, []);
        Exit;
      end;
      Show(mReport);
    end;
end;

/// <summary>Antwort auf Mark: nur Stand der Map und Zahl der Markierungen, ohne Stapel.</summary>
function MarkAnswer: TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mReport: TAtlasRuntimeReport;
    begin
      if not TAtlasRuntimeReports.FromJson(AAnswer, mReport) or (mReport.Kind = TAtlasRuntimeReportKind.None) then
      begin
        Exit;
      end;
      SayMapStatus(mReport);
      if mReport.Diagnostics > 0 then
      begin
        Say(TAtlasDebugTextId.RuntimeReportMarked, [mReport.Diagnostics]);
      end;
    end;
end;

function ClearAnswer: TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      Say(TAtlasDebugTextId.RuntimeReportCleared, []);
    end;
end;

{ Befehle }

class procedure TAtlasIdeRuntimeReport.Paste(const AScope: IAtlasModuleScope);
var
  mProject, mText: string;
begin
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    Say(TAtlasDebugTextId.RuntimeReportNoProject, []);
    Exit;
  end;
  mText := Clipboard.AsText;
  if Trim(mText) = '' then
  begin
    Say(TAtlasDebugTextId.RuntimeReportEmpty, []);
    Exit;
  end;
  if (TAtlasIdeHost.ActiveSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger,
    TAtlasRuntimeReports.cCommand, TAtlasRuntimeReports.ArgumentsJson(mProject, mText), cTimeoutMs, ReportAnswer) then
  begin
    Say(TAtlasDebugTextId.RuntimeReportNoServer, []);
  end;
end;

class procedure TAtlasIdeRuntimeReport.Clear(const AScope: IAtlasModuleScope);
var
  mProject: string;
begin
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if (TAtlasIdeHost.RunningSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger,
    TAtlasRuntimeReports.cClearCommand, TAtlasRuntimeReports.ClearArgumentsJson(mProject), cTimeoutMs,
    ClearAnswer) then
  begin
    Say(TAtlasDebugTextId.RuntimeReportNoServer, []);
  end;
end;

class procedure TAtlasIdeRuntimeReport.Mark(const AScope: IAtlasModuleScope; const AProject, AText: string);
begin
  if (AProject = '') or (Trim(AText) = '') then
  begin
    Exit;
  end;
  if (TAtlasIdeHost.ActiveSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger,
    TAtlasRuntimeReports.cCommand, TAtlasRuntimeReports.ArgumentsJson(AProject, AText), cTimeoutMs, MarkAnswer) then
  begin
    Say(TAtlasDebugTextId.RuntimeReportNoServer, []);
  end;
end;

end.
