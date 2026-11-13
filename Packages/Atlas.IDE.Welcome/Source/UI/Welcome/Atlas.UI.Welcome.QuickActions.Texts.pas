unit Atlas.UI.Welcome.QuickActions.Texts;

// Texte und Farben der Schnellaktionen auf der Willkommensseite (#764) ohne Steuerelement: Beschriftung der
// Knöpfe („baut … 12 s“ während eine Aktion läuft), Stand als Marke mit Farbe, Tooltips mit Taste und Sperrgrund
// und der Titel einer Aktion. Die Knopfleiste selbst steht in Atlas.UI.Welcome.QuickActions.

interface

uses
  Vcl.Graphics,
  Atlas.Core.Welcome.QuickActions;

type
  /// <summary>Texte und Farben der Schnellaktionen ohne Steuerelement: Beschriftung, Marke und Tooltip.</summary>
  TAtlasQuickActionTexts = class
  public const
    /// <summary>Pfeil hinter Knöpfen mit Auswahl.</summary>
    cMenuArrow = #$25BE;
  public
    /// <summary>Beschriftung des Knopfs; während seine Aktion läuft „baut … 12 s“.</summary>
    class function Caption(const AButton: TAtlasQuickActionButton; const AState: TAtlasQuickActionState;
      ANowMs: UInt64): string; static;
    /// <summary>Stand als Text der Marke; '' = keine Marke (etwa nach einem Build: die Build-Marke zeigt ihn).
    /// AUpdate: SVN („aktualisiert …“).</summary>
    class function StateText(const AState: TAtlasQuickActionState; ANowMs: UInt64; AUpdate: Boolean): string;
      static;
    class function StateColor(const AState: TAtlasQuickActionState): TColor; static;
    /// <summary>Tooltip eines Knopfs; AKey: Taste der Aktion (0 = keine), AConsole: Programm der Konsole.</summary>
    class function ButtonHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean; AKey: Integer;
      const AConsole: string): string; static;
  end;

/// <summary>Beschriftung der Aktion AAction (Knopf, Kontextmenü, Optionsdialog) ohne Zustand.</summary>
function QuickActionTitle(AAction: TAtlasQuickAction): string;

implementation

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Pull,
  Atlas.UI.Welcome.Strings;

const
  /// <summary>Farben der Marken wie im Bereich „Projekte“ (#592): grün, gelb, rot, grau.</summary>
  cSucceededColor = TColor($0043A02E);
  cWarningColor = TColor($001A8CC9);
  cFailedColor = TColor($002E22CF);
  cNeutralColor = TColor($00817666);

function RunningText(AAction: TAtlasQuickAction; ASeconds: Integer; AUpdate: Boolean): string;
begin
  case AAction of
    TAtlasQuickAction.Build:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickBuilding, [ASeconds]);
    TAtlasQuickAction.Tests:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTesting, [ASeconds]);
    TAtlasQuickAction.Run:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickStarting, [ASeconds]);
    TAtlasQuickAction.Pull:
      if AUpdate then
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickUpdating, [ASeconds]);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickPulling, [ASeconds]);
      end;
    TAtlasQuickAction.Tasks:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTasking, [ASeconds]);
  else
    Result := '';
  end;
end;

/// <summary>Gebaut: Die Marke „Build 0/0/0“ des Bereichs zeigt das Ergebnis; nur Abgelehnt und Fehlgeschlagen.
/// </summary>
function BuildDoneText(const AState: TAtlasQuickActionState): string;
begin
  Result := '';
  if AState.Phase = TAtlasQuickActionPhase.Refused then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuildRefused);
  end
  else if AState.Phase = TAtlasQuickActionPhase.Failed then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuildFailed);
  end;
end;

function TestsDoneText(const AState: TAtlasQuickActionState): string;
begin
  if AState.Phase = TAtlasQuickActionPhase.Succeeded then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTestsPassed, [AState.Passed]);
  end
  else if (AState.Phase = TAtlasQuickActionPhase.Failed) and (AState.Failed > 0) then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTestsFailed, [AState.Failed]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTestsNotRun);
  end;
end;

function RunDoneText(const AState: TAtlasQuickActionState): string;
begin
  if AState.Phase = TAtlasQuickActionPhase.Succeeded then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRunStarted);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRunRefused);
  end;
end;

function PullDoneText(const AState: TAtlasQuickActionState; AUpdate: Boolean): string;
begin
  if (AState.Phase = TAtlasQuickActionPhase.Succeeded) and (AState.Pull = TAtlasPullOutcome.Updated) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullUpdated);
  end
  else if AState.Phase = TAtlasQuickActionPhase.Succeeded then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullUpToDate);
  end
  else if AState.Pull = TAtlasPullOutcome.Blocked then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullBlocked);
  end
  else if AUpdate then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateFailed);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullFailed);
  end;
end;

/// <summary>Fertig: Aufgabe und Ergebnis als Text der IDE-Schicht („Delphi-12-Prüfung: 2 Fehler 14:03“).</summary>
function TasksDoneText(const AState: TAtlasQuickActionState): string;
begin
  Result := AState.Detail;
  if (AState.Phase = TAtlasQuickActionPhase.Refused) or (AState.Detail = '') then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTasksRefused);
  end;
end;

function DoneText(const AState: TAtlasQuickActionState; AUpdate: Boolean): string;
begin
  Result := '';
  case AState.Action of
    TAtlasQuickAction.Build:
      Result := BuildDoneText(AState);
    TAtlasQuickAction.Tests:
      Result := TestsDoneText(AState);
    TAtlasQuickAction.Run:
      Result := RunDoneText(AState);
    TAtlasQuickAction.Pull:
      Result := PullDoneText(AState, AUpdate);
    TAtlasQuickAction.Console:
      if AState.Phase <> TAtlasQuickActionPhase.Succeeded then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickConsoleFailed);
      end;
    TAtlasQuickAction.Tasks:
      Result := TasksDoneText(AState);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Grund eines gesperrten Knopfs; '' = nicht gesperrt.</summary>
function BlockedHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean): string;
begin
  case AButton.Block of
    TAtlasPullBlock.LocalChanges:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLocalChanges);
    TAtlasPullBlock.NoWorkingCopy:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullNoWorkingCopy);
    TAtlasPullBlock.Busy:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBusy);
  else
    Result := '';
  end;
  if (Result = '') and not AButton.Enabled then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickIdeBusy);
    if ARunning then
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBusy);
    end;
  end;
end;

function ActionHint(const AButton: TAtlasQuickActionButton; const AConsole: string): string;
begin
  case AButton.Action of
    TAtlasQuickAction.Build:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintTests);
    TAtlasQuickAction.Run:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintRun);
    TAtlasQuickAction.Pull:
      if AButton.Update then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintUpdate);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintPull);
      end;
    TAtlasQuickAction.Folder:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintFolder);
    TAtlasQuickAction.Tasks:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintTasks);
  else
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintConsole,
      [TAtlasWelcomeQuickActions.NormalizedConsole(AConsole)]);
  end;
end;

{ TAtlasQuickActionTexts }

class function TAtlasQuickActionTexts.Caption(const AButton: TAtlasQuickActionButton;
  const AState: TAtlasQuickActionState; ANowMs: UInt64): string;
begin
  if AState.Running and (AState.Action = AButton.Action) then
  begin
    Exit(StateText(AState, ANowMs, AButton.Update));
  end;
  if AButton.Action = TAtlasQuickAction.Pull then
  begin
    if AButton.Update then
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdate);
    end
    else
    begin
      Result := QuickActionTitle(TAtlasQuickAction.Pull);
    end;
    if AButton.AskExternals then
    begin
      Result := Result + ' ' + cMenuArrow;
    end;
  end
  else
  begin
    Result := QuickActionTitle(AButton.Action);
  end;
end;

class function TAtlasQuickActionTexts.StateText(const AState: TAtlasQuickActionState; ANowMs: UInt64;
  AUpdate: Boolean): string;
begin
  if AState.Running then
  begin
    Result := RunningText(AState.Action, AState.ElapsedSeconds(ANowMs), AUpdate);
  end
  else if AState.Phase = TAtlasQuickActionPhase.Idle then
  begin
    Result := '';
  end
  else
  begin
    Result := DoneText(AState, AUpdate);
  end;
end;

class function TAtlasQuickActionTexts.StateColor(const AState: TAtlasQuickActionState): TColor;
begin
  // Farben wie die Marken des Bereichs „Projekte“ (#592): grau, grün, gelb, rot.
  case AState.Phase of
    TAtlasQuickActionPhase.Succeeded:
      Result := cSucceededColor;
    TAtlasQuickActionPhase.Refused:
      Result := cWarningColor;
    TAtlasQuickActionPhase.Failed:
      if (AState.Action = TAtlasQuickAction.Pull) and (AState.Pull = TAtlasPullOutcome.Blocked) then
      begin
        Result := cWarningColor;
      end
      else
      begin
        Result := cFailedColor;
      end;
  else
    Result := cNeutralColor;
  end;
end;

class function TAtlasQuickActionTexts.ButtonHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean;
  AKey: Integer; const AConsole: string): string;
begin
  Result := BlockedHint(AButton, ARunning);
  if Result <> '' then
  begin
    Exit;
  end;
  Result := ActionHint(AButton, AConsole);
  if AKey <> 0 then
  begin
    Result := Result + sLineBreak + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintKey,
      [ShortCutToText(TShortCut(AKey))]);
  end;
end;

function QuickActionTitle(AAction: TAtlasQuickAction): string;
begin
  case AAction of
    TAtlasQuickAction.Build:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTests);
    TAtlasQuickAction.Run:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRun);
    TAtlasQuickAction.Pull:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
    TAtlasQuickAction.Folder:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickFolder);
    TAtlasQuickAction.Tasks:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTasks);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickConsole);
  end;
end;

end.
