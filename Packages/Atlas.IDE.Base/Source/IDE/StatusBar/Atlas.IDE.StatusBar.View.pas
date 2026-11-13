unit Atlas.IDE.StatusBar.View;

// Inhalt der Atlas-Statusleiste (#1155) für eine Editoransicht, wie ihn TAtlasIdeStatusBar je Takt setzt:
// - Status aus dem Atlas-Feld (Text, Zustand, Tooltip) samt Plakette der Benachrichtigungen (#1234) und den
//   Zusatzfeldern der Module (z. B. „interface-Änderung“ der Unit-Beziehungen), die dann nicht in der Statuszeile
//   stehen.
// - Zähler der Befunde der Unit aus dem Speicher der Probleme.
// - Live-Prüfung: Stand, Ruhe beim Debuggen (#1241), Lauf der Projektprüfung des Servers (#1247) oder bei
//   älteren Servern Fortschritt aus den Befunden (#1232).
// - Methode am Cursor aus der Gliederung mit Zeilen und CC aus atlas.server.metrics.
// Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.StatusBar.Content,
  Atlas.UI.StatusBar.Bar,
  Atlas.IDE.Status.Field;

type
  /// <summary>Letzte Metriken der Datei; False ohne.</summary>
  TAtlasStatusMetricsFunc = reference to function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;

  /// <summary>Methode am Cursor der obersten Leiste: Ziel des Klicks auf die Methode.</summary>
  TAtlasStatusBarMethodTarget = record
    FileName: string;
    Method: TAtlasStatusMethod;
  end;

  TAtlasStatusBarViews = class
  public
    /// <summary>Probleme an (wie Wellenlinien und „Atlas-Prüfung“)?</summary>
    class function ProblemsOn(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Caret der Ansicht als 0-basierte Zeile und Zeichenindex; False ohne Ansicht.</summary>
    class function CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean; static;
    /// <summary>Status und Plakette aus AField; ohne Feld nur „Atlas“.</summary>
    class procedure StatusInto(AField: TAtlasStatusField; var AView: TAtlasStatusBarView); static;
    /// <summary>Ganze Ansicht für AView mit den Elementen AItems; ATarget: Methode am Cursor (leer ohne).</summary>
    class function ViewFor(const AView: IOTAEditView; const AItems: TArray<string>; AField: TAtlasStatusField;
      const AMetrics: TAtlasStatusMetricsFunc; out ATarget: TAtlasStatusBarMethodTarget): TAtlasStatusBarView;
      static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.UI.Strings,
  Atlas.UI.StatusBar.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Status.ServerWindow;

function LiveTexts: TAtlasStatusLiveTexts;
begin
  Result.Live := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLive);
  Result.Manual := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarManual);
  Result.LiveHint := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLiveOnHint);
  Result.OnSaveHint := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLiveOffHint);
  Result.ManualHint := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLiveManualHint);
  Result.RecheckClick := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarRecheckClick);
  Result.CheckFileClick := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarCheckFileClick);
  Result.OnSave := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarOnSave);
  Result.Checking := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarChecking);
  Result.CheckedAgo := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarCheckedAgo);
  Result.Seconds := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarSeconds);
  Result.Minutes := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarMinutes);
  Result.Hours := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarHours);
  Result.Separator := TAtlasStatusSummary.cSeparator;
  Result.ProjectProgress := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarProjectProgress);
  Result.ProjectDone := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarProjectDone);
  Result.ProjectPaused := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarProjectPaused);
end;

/// <summary>Zähler der Befunde von AFileName.</summary>
procedure FindingsInto(var AView: TAtlasStatusBarView; const AFileName: string;
  const ASettings: TAtlasPluginSettings);
var
  mProblems: TArray<TAtlasProblem>;
begin
  AView.FindingsShown := True;
  mProblems := nil;
  if AFileName <> '' then
  begin
    mProblems := TAtlasProblemsController.Current.ForFile(AFileName);
  end;
  AView.Counts := TAtlasStatusBarContent.CountsOf(mProblems, ASettings.ProblemsWindowCompiler);
  AView.FindingsHint := TAtlasStatusBarStrings.Fmt(TAtlasStatusBarTextId.StatusBarFindingsHint,
    [AView.Counts[TAtlasFindingKind.Error], AView.Counts[TAtlasFindingKind.Warning],
    AView.Counts[TAtlasFindingKind.Info]]);
end;

/// <summary>Stand der Projektprüfung hinter dem Text der Live-Prüfung; AChecked/ATotal: geprüfte und alle Units
/// (0 ohne). Nur mit eingeschalteten Problemen.</summary>
procedure ProgressInto(var AView: TAtlasStatusBarView; out AChecked, ATotal: Integer);
var
  mRun: TLspWorkspaceRun;
  mFinishedAgo: UInt64;
begin
  AChecked := 0;
  ATotal := 0;
  if TAtlasProblemsController.Paused then
  begin
    // Während des Debuggens ruht die Prüfung (#1241).
    AView.LiveBusy := False;
    AView.LiveText := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarPausedDebugger);
  end
  else if TAtlasProblemsController.ProjectRun(mRun, mFinishedAgo) then
  begin
    // Lauf der Projektprüfung des Servers (#1247): Fortschritt, Pause beim Kompilieren, danach „fertig“.
    AChecked := mRun.Done;
    ATotal := mRun.Total;
    AView.LiveText := AView.LiveText + TAtlasStatusBarContent.RunText(mRun.Active, mRun.Done, mRun.Total,
      mRun.Paused, mFinishedAgo, LiveTexts);
  end
  else if TAtlasIdeProblems.ProjectProgress(AChecked, ATotal) then
  begin
    // Ältere Server ohne Laufstand: Fortschritt aus den Befunden (#1232), solange Units fehlen.
    AView.LiveText := AView.LiveText + TAtlasStatusBarContent.ProgressText(AChecked, ATotal, LiveTexts);
  end;
end;

/// <summary>Tooltip der Live-Prüfung: Modus, Klick, letzte Prüfung und Stand des Projekts.</summary>
function LiveHint(const ASettings: TAtlasPluginSettings; const ACheck: TAtlasProblemsCheck;
  AChecked, ATotal: Integer): string;
begin
  Result := TAtlasStatusBarContent.LiveHint(TAtlasIdeProblems.UpdateMode, TAtlasStatusBarViews.ProblemsOn(ASettings),
    LiveTexts);
  if ACheck.FileName <> '' then
  begin
    Result := Result + sLineBreak + TAtlasStatusBarStrings.Fmt(TAtlasStatusBarTextId.StatusBarLastCheck,
      [ExtractFileName(ACheck.FileName), ACheck.DurationMs, FormatDateTime('hh":"nn":"ss', ACheck.At)]);
  end;
  if ATotal > 0 then
  begin
    Result := Result + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusProject, [AChecked, ATotal]);
  end;
end;

/// <summary>Live-Prüfung für AFileName: Text, Beschäftigt und Tooltip.</summary>
procedure LiveInto(var AView: TAtlasStatusBarView; const AFileName: string; const ASettings: TAtlasPluginSettings);
var
  mCheck: TAtlasProblemsCheck;
  mCheckedAt: TDateTime;
  mChecked, mTotal: Integer;
begin
  mCheck := TAtlasProblemsController.LastCheck;
  mCheckedAt := 0;
  if (AFileName <> '') and SameText(mCheck.FileName, AFileName) then
  begin
    mCheckedAt := mCheck.At;
  end;
  AView.LiveBusy := TAtlasStatusBarViews.ProblemsOn(ASettings) and TAtlasProblemsController.Checking;
  AView.LiveText := TAtlasStatusBarContent.LiveText(TAtlasIdeProblems.UpdateMode, AView.LiveBusy, mCheckedAt, Now,
    LiveTexts);
  mChecked := 0;
  mTotal := 0;
  if TAtlasStatusBarViews.ProblemsOn(ASettings) then
  begin
    ProgressInto(AView, mChecked, mTotal);
  end;
  AView.LiveHint := LiveHint(ASettings, mCheck, mChecked, mTotal);
end;

/// <summary>Methode an ALine (0-basiert) aus der Gliederung; nicht gefunden ohne Pascal-Datei oder Gliederung.
/// </summary>
function MethodAt(const AView: IOTAEditView; const AFileName: string; ALine: Integer;
  const AMetrics: TAtlasStatusMetricsFunc): TAtlasStatusMethod;
var
  mSnapshot: TAtlasOutlineSnapshot;
  mMetrics: TAtlasFileMetrics;
  mKnown: Boolean;
begin
  Result := Default(TAtlasStatusMethod);
  if (AView = nil) or not TAtlasIdeOutlineCache.IsPascal(AFileName) then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(AView);
  if (mSnapshot.Status <> TAtlasOutlineStatus.Ready) or not SameText(mSnapshot.FileName, AFileName) then
  begin
    Exit;
  end;
  mKnown := Assigned(AMetrics) and AMetrics(AFileName, mMetrics);
  if not mKnown then
  begin
    mMetrics := Default(TAtlasFileMetrics);
  end;
  Result := TAtlasStatusBarContent.MethodAt(mSnapshot.Nodes, ALine, mMetrics, mKnown);
end;

/// <summary>Element „Methode“ aus AMethod.</summary>
procedure MethodInto(var AView: TAtlasStatusBarView; const AMethod: TAtlasStatusMethod);
begin
  AView.MethodFound := AMethod.Found;
  if not AMethod.Found then
  begin
    AView.MethodName := TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarNoMethod);
    Exit;
  end;
  AView.MethodName := AMethod.Name;
  AView.MethodDetail := TAtlasStatusBarContent.MethodDetail(AMethod,
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLines),
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarCyclomatic),
    TAtlasStatusSummary.cSeparator);
  AView.MethodOver := AMethod.Over;
  AView.MethodHint := AMethod.Name + sLineBreak + TAtlasStatusBarContent.MethodLimits(AMethod,
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLines),
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarCyclomatic),
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarLimit), TAtlasStatusSummary.cSeparator) + sLineBreak +
    TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarMethodJump);
end;

/// <summary>Zusatzfelder des Atlas-Felds, solange es umgezogen ist (TAtlasStatusField.Relocated); sonst stehen sie
/// in der Statuszeile.</summary>
procedure ExtrasInto(AField: TAtlasStatusField; var AView: TAtlasStatusBarView);
var
  mItems: TArray<TAtlasStatusExtraItem>;
  mIndex: Integer;
begin
  AView.Extras := nil;
  if not TAtlasStatusField.Relocated then
  begin
    Exit;
  end;
  mItems := AField.ExtraItems;
  SetLength(AView.Extras, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    AView.Extras[mIndex].Id := mItems[mIndex].Id;
    AView.Extras[mIndex].Text := mItems[mIndex].Text;
    AView.Extras[mIndex].Hint := mItems[mIndex].Hint;
    AView.Extras[mIndex].Clickable := mItems[mIndex].Clickable;
    AView.Extras[mIndex].State := mItems[mIndex].State;
    AView.Extras[mIndex].HasContext := mItems[mIndex].HasContext;
  end;
end;

{ TAtlasStatusBarViews }

class function TAtlasStatusBarViews.ProblemsOn(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Problems and (TAtlasProblemsController.Current <> nil) and
    not TAtlasGuard.Disabled(TAtlasFeature.Problems);
end;

class function TAtlasStatusBarViews.CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean;
var
  mCursor: TOTAEditPos;
begin
  Result := False;
  ALine := -1;
  ACharacter := -1;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  if mCursor.Line < 1 then
  begin
    Exit;
  end;
  ALine := mCursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result := True;
end;

class procedure TAtlasStatusBarViews.StatusInto(AField: TAtlasStatusField; var AView: TAtlasStatusBarView);
var
  mText: string;
begin
  if AField = nil then
  begin
    AView.StatusText := TAtlasStatusSummary.cFieldCaption;
    AView.StatusHint := '';
    AView.StatusState := TAtlasStatusState.Neutral;
    Exit;
  end;
  mText := AField.Text;
  if mText = '' then
  begin
    mText := TAtlasStatusSummary.cFieldCaption;
  end;
  // Mehr Platz als in der Statuszeile: „Atlas · bereit“ statt nur „Atlas“.
  if (AField.State = TAtlasStatusState.Green) and SameText(mText, TAtlasStatusSummary.cFieldCaption) then
  begin
    mText := mText + TAtlasStatusSummary.cSeparator + TAtlasStatusBarStrings.Text(TAtlasStatusBarTextId.StatusBarReady);
  end;
  AView.StatusText := mText;
  AView.StatusHint := AField.Tooltip + sLineBreak + TAtlasStatusBarStrings.Text(
    TAtlasStatusBarTextId.StatusBarStatusClicks);
  if TAtlasIdeServerWindow.Enabled then
  begin
    AView.StatusHint := AView.StatusHint + sLineBreak + TAtlasStatusBarStrings.Text(
      TAtlasStatusBarTextId.StatusBarStatusServer);
  end;
  AView.StatusState := AField.State;
  // Plakette der Benachrichtigungen (#1234): Das umgezogene Feld ist 0 breit, die Leiste zeigt sie.
  AView.BadgeShown := AField.Badge.Shown;
  AView.BadgeCount := AField.Badge.Count;
  AView.BadgeState := AField.Badge.State;
  AView.BadgeHint := AField.Badge.Hint;
  ExtrasInto(AField, AView);
end;

class function TAtlasStatusBarViews.ViewFor(const AView: IOTAEditView; const AItems: TArray<string>;
  AField: TAtlasStatusField; const AMetrics: TAtlasStatusMetricsFunc;
  out ATarget: TAtlasStatusBarMethodTarget): TAtlasStatusBarView;
var
  mSettings: TAtlasPluginSettings;
  mFileName: string;
  mLine, mCharacter: Integer;
  mMethod: TAtlasStatusMethod;
begin
  Result := Default(TAtlasStatusBarView);
  ATarget := Default(TAtlasStatusBarMethodTarget);
  Result.Items := AItems;
  mSettings := TAtlasIdeSettings.Current;
  StatusInto(AField, Result);
  mFileName := '';
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    mFileName := AView.Buffer.FileName;
  end;
  // Ohne Caret: Zeile -1, keine Methode.
  CaretOf(AView, mLine, mCharacter);
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.cFindings) and ProblemsOn(mSettings) then
  begin
    FindingsInto(Result, mFileName, mSettings);
  end;
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.cLiveCheck) then
  begin
    LiveInto(Result, mFileName, mSettings);
  end;
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.cMethod) then
  begin
    mMethod := MethodAt(AView, mFileName, mLine, AMetrics);
    MethodInto(Result, mMethod);
    if mMethod.Found then
    begin
      ATarget.FileName := mFileName;
      ATarget.Method := mMethod;
    end;
  end;
end;

end.
