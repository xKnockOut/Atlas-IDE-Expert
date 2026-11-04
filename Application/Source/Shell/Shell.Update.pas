unit Shell.Update;

// Host-Rolle Shell von AtlasUpdate.exe (#1519): Befehlszeile lesen, das
// Update-System aus den Windows-Adaptern zusammensetzen und den Befehl
// ausführen.
// - prepare: unsichtbar aus der laufenden IDE; Stand in state.json.
// - apply: sichtbare Konsole nach dem Schließen der IDE; Ergebnis in
//   result.json. Ist der Atlas-Ordner nicht beschreibbar, wird nicht erhöht
//   neu gestartet: Ein anderes Administratorkonto hätte ein anderes
//   HKEY_CURRENT_USER und träfe die Known Packages des Benutzers nicht. Das
//   Ergebnis ist dann elevation, und das Plugin rät zur Installation unter
//   %LOCALAPPDATA%\Programs\Atlas.
// - install: Erstinstallation aus dem entpackten Paket (Shell.Update.Install).
// Die Adapter setzt Shell.Update.System zusammen.

interface

type
  TShellUpdate = class
  public
    /// <summary>Exit-Code: 0 Erfolg, 1 Fehler, 2 falscher Aufruf.</summary>
    class function Run: Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Text.UpdateRun,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Updates.Contract,
  Atlas.Common.Updates.Prepare,
  Atlas.Common.Updates.Apply,
  Shell.Bootstrap,
  Shell.Update.System,
  Shell.Update.Install;

type
{$SCOPEDENUMS ON}
  TShellUpdateText = (Usage, NotReady, NotWritable, PressEnter);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TShellUpdateText] of TAtlasText = (
    (De: 'Aufruf: AtlasUpdate install | prepare | apply --name Wert …'#13#10 +
    '  install  Atlas aus diesem Ordner in eine Delphi-IDE installieren'#13#10 +
    '  prepare  Update laden und prüfen (startet das Plugin)'#13#10 +
    '  apply    Update nach dem Schließen der IDE einspielen (startet das Plugin)';
    En: 'Usage: AtlasUpdate install | prepare | apply --name value …'#13#10 +
    '  install  install Atlas from this folder into a Delphi IDE'#13#10 +
    '  prepare  download and verify an update (started by the plugin)'#13#10 +
    '  apply    apply an update after the IDE has closed (started by the plugin)'),
    (De: 'Das Update ist nicht vorbereitet.'; En: 'The update has not been prepared.'),
    (De: 'In %s darf AtlasUpdate nicht schreiben.'; En: 'AtlasUpdate may not write to %s.'),
    (De: 'Eingabetaste schließt das Fenster.'; En: 'Press Enter to close this window.'));

function CommandArgs: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, ParamCount);
  for mIndex := 1 to ParamCount do
  begin
    Result[mIndex - 1] := ParamStr(mIndex);
  end;
end;

function Prepare(const AArgs: TUpdateArguments): Integer;
var
  mPreparation: TUpdatePreparation;
begin
  mPreparation := TUpdatePreparation.Create(TShellUpdateSystem.NewSystem(TUpdateLayout.Join(AArgs.Staging,
    TUpdateLayout.LogFile)), AArgs, ParamStr(0));
  try
    Result := mPreparation.Run;
  finally
    mPreparation.Free;
  end;
end;

/// <summary>Ergebnis ohne Tausch (nicht vorbereitet, keine Schreibrechte) für das Plugin festhalten.</summary>
function Refuse(const ASystem: TUpdateSystem; const AStage: TUpdateStage; const ARootDir, AReason,
  ADetail: string): Integer;
var
  mOutcome: TUpdateOutcome;
begin
  mOutcome := Default(TUpdateOutcome);
  mOutcome.Kind := TUpdateOutcomeKind.Failed;
  mOutcome.Version := AStage.Version;
  mOutcome.Reason := AReason;
  mOutcome.Detail := ADetail;
  ASystem.Files.WriteText(TUpdateLayout.Join(ARootDir, TUpdateLayout.ResultFile), mOutcome.ToJson);
  Result := 1;
end;

function Install(const ASystem: TUpdateSystem; const AArgs: TUpdateArguments; const AStage: TUpdateStage): Integer;
var
  mInput: TUpdateApplyInput;
  mInstallation: TUpdateInstallation;
begin
  mInput := Default(TUpdateApplyInput);
  mInput.FilesDir := TUpdateFolders.FilesDir(AArgs.Staging);
  mInput.WorkDir := AArgs.Staging;
  mInput.RootDir := TUpdateFolders.RootOf(AArgs.Staging);
  mInput.Version := AStage.Version;
  mInput.Previous := AStage.Previous;
  mInput.Candidates := AStage.Candidates;
  mInstallation := TUpdateInstallation.Create(ASystem, AArgs, mInput);
  try
    Result := mInstallation.Run;
  finally
    mInstallation.Free;
  end;
end;

function Apply(const AArgs: TUpdateArguments): Integer;
var
  mSystem: TUpdateSystem;
  mStage: TUpdateStage;
begin
  mSystem := TShellUpdateSystem.NewSystem(TUpdateLayout.Join(AArgs.Staging, TUpdateLayout.LogFile));
  mStage := TUpdateStage.FromJson(mSystem.Files.ReadText(TUpdateLayout.Join(AArgs.Staging,
    TUpdateLayout.StateFile)));
  if mStage.Phase <> TUpdatePhase.Ready then
  begin
    mSystem.Log(cTexts[TShellUpdateText.NotReady].Text);
    Exit(Refuse(mSystem, mStage, TUpdateFolders.RootOf(AArgs.Staging), TUpdateErrors.Unexpected,
      TUpdateLayout.StateFile));
  end;
  if not mSystem.Files.CanWrite(AArgs.Target) then
  begin
    mSystem.Log(cTexts[TShellUpdateText.NotWritable].Fmt([AArgs.Target]));
    Result := Refuse(mSystem, mStage, TUpdateFolders.RootOf(AArgs.Staging), TUpdateErrors.Elevation, AArgs.Target);
  end
  else
  begin
    Result := Install(mSystem, AArgs, mStage);
  end;
  if Result <> 0 then
  begin
    // Die Konsole schließt sonst sofort, und niemand liest den Grund.
    TShellUpdateSystem.Say(cTexts[TShellUpdateText.PressEnter].Text);
    Readln;
  end;
end;

class function TShellUpdate.Run: Integer;
var
  mArgs: TUpdateArguments;
begin
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
  TShellBootstrap.UseTextLanguage('');
  mArgs := TUpdateArguments.Parse(CommandArgs);
  if SameText(mArgs.Command, 'prepare') and (mArgs.Staging <> '') and (mArgs.ManifestUrl <> '') then
  begin
    Result := Prepare(mArgs);
  end
  else if SameText(mArgs.Command, 'apply') and (mArgs.Staging <> '') and (mArgs.Target <> '') then
  begin
    Result := Apply(mArgs);
  end
  else if SameText(mArgs.Command, 'install') or (mArgs.Command = '') then
  begin
    Result := TShellUpdateInstall.Run(mArgs);
  end
  else
  begin
    TShellUpdateSystem.Say(cTexts[TShellUpdateText.Usage].Text);
    Result := 2;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Update', cTexts);

end.
