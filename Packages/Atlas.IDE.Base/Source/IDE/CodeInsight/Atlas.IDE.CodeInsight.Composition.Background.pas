unit Atlas.IDE.CodeInsight.Composition.Background;

// Teile ohne eigenes Fenster, die im Hintergrund beobachten: Einfrier-Wächter (#501), Neuladen extern geänderter
// Dateien (#536) mit Prüfung nach dem Speichern (#548), offene Formulare an den Server (#402), uses nachziehen nach
// dem Umbenennen einer Unit (#512), Hinweis „Prüfregeln sind aus“ (#1454) und die Dateiwege der schreibenden
// MCP-Werkzeuge (#61, #397).

interface

procedure StartWatchdog;
procedure StopWatchdog;
function WatchdogStarted: Boolean;
procedure StartReloader;
procedure StopReloader;
function ReloaderStarted: Boolean;
/// <summary>Designer-Notifier (#402) nur im normalen Betrieb (#722).</summary>
procedure StartForms;
procedure StopForms;
function FormsStarted: Boolean;
procedure StartUnitRename;
procedure StopUnitRename;
function UnitRenameStarted: Boolean;
procedure StartRuleChecksNotice;
procedure StopRuleChecksNotice;
function RuleChecksNoticeStarted: Boolean;
/// <summary>Einmaliger Hinweis ohne Kommandozeilen-Compiler (#1822).</summary>
procedure StartEditionNotice;
procedure StopEditionNotice;
function EditionNoticeStarted: Boolean;
/// <summary>Ungespeicherte Dateien für schreibende MCP-Werkzeuge (#61).</summary>
procedure StartDirtyExport;
procedure StopDirtyExport;
function DirtyExportStarted: Boolean;
/// <summary>Schreibende MCP-Werkzeuge ändern offene Dateien über das Plugin (#397).</summary>

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Files.Reloader,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Editor.UnitRename,
  Atlas.IDE.Settings.RuleChecksNotice,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Diagnostics.Edition,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Build;

const
  // Ab dieser Dauer ein Hinweis im Meldungsfenster (#501).
  cHangHintMs = 2000;

var
  Watchdog: TAtlasWatchdog;
  Hangs: TAtlasHangMonitor;
  Reloader: TAtlasFileReloader;
  Forms: TAtlasIdeForms;
  UnitRename: TAtlasIdeUnitRename;
  RuleChecksNotice: TAtlasIdeRuleChecksNotice;
  EditionNotice: TAtlasIdeEditionNotice;
  DirtyExport: TAtlasDirtyExport;

/// <summary>Hänger (#501) ins Protokoll und ab cHangHintMs als Zeile ins Meldungsfenster, nie als Dialog und ohne
/// das Meldungsfenster nach vorn zu holen.</summary>
procedure ReportHang(const AHang: TAtlasHang);
var
  mHang: TAtlasHang;
  mText, mActivity: string;
begin
  if (Hangs = nil) or (Manager = nil) then
  begin
    Exit;
  end;
  mHang := AHang;
  if Compile <> nil then
  begin
    mHang.CodeInsightCount := Compile.Events.CodeInsightCount;
    mHang.CodeInsightMs := Compile.Events.CodeInsightMs;
  end;
  Hangs.ThresholdMs := TAtlasIdeSettings.Current.HangThresholdMs;
  mText := Hangs.Finish(mHang);
  if mText = '' then
  begin
    Exit;
  end;
  Manager.Report(mText);
  if not TAtlasIdeSettings.Current.HangHint or (mHang.DurationMs < cHangHintMs) then
  begin
    Exit;
  end;
  mActivity := '';
  if mHang.Activity <> '' then
  begin
    mActivity := ' (' + mHang.Activity + ')';
  end;
  MessageLine(TAtlasStrings.Fmt(TAtlasTextId.HangHint, [mHang.DurationMs, mActivity]));
end;

procedure StartWatchdog;
begin
  Hangs := TAtlasHangMonitor.Create(TAtlasIdeSettings.Current.HangThresholdMs);
  Watchdog := TAtlasWatchdog.Create(
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.HangThresholdMs;
    end);
  Watchdog.OnHang := ReportHang;
end;

procedure StopWatchdog;
begin
  FreeAndNil(Watchdog);
  if (Hangs <> nil) and (Hangs.Count > 0) and (Manager <> nil) then
  begin
    Manager.Report(Hangs.Summary);
  end;
  FreeAndNil(Hangs);
end;

function WatchdogStarted: Boolean;
begin
  Result := Watchdog <> nil;
end;

/// <summary>Gespeichert: Prüfung des Servers mit dcc (#40), Prüfung in der IDE nur, wenn eingeschaltet (#548), und
/// gewählte Kodierung und Zeilenenden schreiben (#591).</summary>
procedure FileSaved(const AFileName: string);
begin
  if Manager <> nil then
  begin
    Manager.NotifySaved(AFileName);
  end;
  if CheckOnSave <> nil then
  begin
    CheckOnSave.Saved(AFileName);
  end;
  if StatusLines <> nil then
  begin
    StatusLines.Saved(AFileName);
  end;
end;

procedure StartReloader;
begin
  Reloader := TAtlasFileReloader.Create(Reports());
  // Gespeichert: Compilerprüfung vormerken (#548).
  Reloader.OnSaved :=
    procedure(AFileName: string)
    begin
      FileSaved(AFileName);
    end;
end;

procedure StopReloader;
begin
  FreeAndNil(Reloader);
end;

function ReloaderStarted: Boolean;
begin
  Result := Reloader <> nil;
end;

procedure StartForms;
begin
  Forms := TAtlasIdeForms.Create(RunningSession, Reports());
end;

procedure StopForms;
begin
  FreeAndNil(Forms);
end;

function FormsStarted: Boolean;
begin
  Result := Forms <> nil;
end;

procedure StartUnitRename;
begin
  UnitRename := TAtlasIdeUnitRename.Create(ActiveSession, Reports());
end;

procedure StopUnitRename;
begin
  FreeAndNil(UnitRename);
end;

function UnitRenameStarted: Boolean;
begin
  Result := UnitRename <> nil;
end;

procedure StartRuleChecksNotice;
begin
  RuleChecksNotice := TAtlasIdeRuleChecksNotice.Create;
end;

procedure StopRuleChecksNotice;
begin
  FreeAndNil(RuleChecksNotice);
end;

function RuleChecksNoticeStarted: Boolean;
begin
  Result := RuleChecksNotice <> nil;
end;

procedure StartEditionNotice;
begin
  EditionNotice := TAtlasIdeEditionNotice.Create(
    procedure
    begin
      TAtlasOptionsRegistration.ShowSetting('DiagnosticsEditionCheck');
    end);
end;

procedure StopEditionNotice;
begin
  FreeAndNil(EditionNotice);
end;

function EditionNoticeStarted: Boolean;
begin
  Result := EditionNotice <> nil;
end;

procedure StartDirtyExport;
begin
  DirtyExport := TAtlasDirtyExport.Create;
end;

procedure StopDirtyExport;
begin
  FreeAndNil(DirtyExport);
end;

function DirtyExportStarted: Boolean;
begin
  Result := DirtyExport <> nil;
end;

end.
