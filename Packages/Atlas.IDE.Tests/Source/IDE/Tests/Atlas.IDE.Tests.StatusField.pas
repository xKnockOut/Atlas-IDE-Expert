unit Atlas.IDE.Tests.StatusField;

// Teststand als Feld der Atlas-Statusleiste (#1777, editor.statusBar.tests):
// - Ein Zeitgeber (500 ms) bestimmt das Testprojekt der aktuellen Datei
//   (Testunit: ihr Testprojekt; sonst wie „Tests ausführen“ das aktive bzw.
//   das erste der Projektgruppe, ohne Rückfrage) und setzt das Zusatzfeld
//   „Tests 41/42“ mit Ampelpunkt über TAtlasIdeHost.SetStatusItem; Text,
//   Ampel und Tooltip aus Atlas.Core.Tests.StatusField, die Ergebnisse aus dem
//   Fenster „Atlas-Tests“ (TAtlasIdeTestExplorer.StatusInput). Ohne
//   Testprojekt kein Feld.
// - Klick: fehlgeschlagene Tests dieses Testprojekts erneut ausführen, sind
//   alle grün bzw. ist noch nichts gelaufen, alle.
// - Rechtsklick: Menü Alle ausführen, Fehlgeschlagene erneut ausführen,
//   Betroffene ausführen (#1353), Fenster „Atlas-Tests“ (#1776), Ergebnisse
//   auf der Willkommensseite (#763), jeweils über die Befehle.
// - Das Feld wird nur neu gesetzt, wenn sich etwas geändert hat; beim Abbau
//   entfernt dieses Objekt sein Feld (danach hält Base keinen Klick mehr).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Tests.StatusField,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Explorer;

type
  TAtlasIdeTestStatusField = class
  private const
    cId = 'atlas.tests';
    cTickMs = 500;
  private
    FTests: TAtlasIdeTests;
    FExplorer: TAtlasIdeTestExplorer;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    /// <summary>Testprojekt (.dproj) des letzten Takts; '' = keins.</summary>
    FProject: string;
    /// <summary>Datei und aktives Projekt, für die FProject bestimmt wurde.</summary>
    FResolvedFor: string;
    /// <summary>Zuletzt gesetzter Inhalt (Text, Zustand, Tooltip); '' = kein Feld.</summary>
    FShown: string;
    FRerunFailed: Boolean;
    procedure Tick(Sender: TObject);
    procedure Refresh;
    procedure ResolveProject;
    procedure Show(const AStatus: TAtlasTestStatus);
    procedure Clear;
    // Ohne const: TProc<TPoint> nimmt keine Methode mit const-Parameter (E2010).
    procedure Clicked(APoint: TPoint);
    procedure ContextClicked(APoint: TPoint);
    procedure MenuClicked(Sender: TObject);
    procedure RunAll;
    procedure RunFailed;
  public
    /// <summary>ATests und AExplorer gehören dem Aufrufer und leben länger als dieses Objekt.</summary>
    constructor Create(ATests: TAtlasIdeTests; AExplorer: TAtlasIdeTestExplorer);
    destructor Destroy; override;
    /// <summary>Feld gewünscht (tests.run, editor.statusBar und editor.statusBar.tests)?</summary>
    class function Wanted: Boolean; static;
    /// <summary>Einstellungen geändert: Feld neu bzw. weg.</summary>
    procedure ApplySettings;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Status.Contract,
  Atlas.Text.TestResults,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Projects,
  Atlas.UI.Tests.Strings;

type
{$SCOPEDENUMS ON}
  TMenuAction = (RunAll, RunFailed, Affected, Window, Welcome);
{$SCOPEDENUMS OFF}

const
  cMenuTexts: array[TMenuAction] of TAtlasTestsTextId = (TAtlasTestsTextId.StatusMenuRunAll,
    TAtlasTestsTextId.StatusMenuRunFailed, TAtlasTestsTextId.StatusMenuAffected, TAtlasTestsTextId.StatusMenuWindow,
    TAtlasTestsTextId.StatusMenuWelcome);
  cCommandAffected = 'Atlas.RunAffectedTests';
  cCommandWindow = 'Atlas.TestExplorer';
  cCommandWelcome = 'Atlas.WelcomeStart';

function Texts: TAtlasTestStatusTexts;
begin
  Result := Default(TAtlasTestStatusTexts);
  Result.Field := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldText);
  Result.Running := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldRunning);
  Result.NotRun := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldNotRun);
  Result.Project := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldProject);
  Result.LastRun := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldLastRun);
  Result.NoRunYet := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldNoRun);
  Result.Counts := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldCounts);
  Result.Stale := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldStale);
  Result.ClickFailed := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldClickFailed);
  Result.ClickAll := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldClickAll);
  Result.Context := TAtlasTestsStrings.Text(TAtlasTestsTextId.StatusFieldContext);
  Result.DecimalSeparator := FormatSettings.DecimalSeparator;
end;

/// <summary>Datei im obersten Editor; '' ohne.</summary>
function TopFileName: string;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    Result := mView.Buffer.FileName;
  end;
end;

/// <summary>Datei des aktiven Projekts; '' ohne.</summary>
function ActiveProjectFile: string;
begin
  Result := '';
  if GetActiveProject <> nil then
  begin
    Result := GetActiveProject.FileName;
  end;
end;

{ TAtlasIdeTestStatusField }

constructor TAtlasIdeTestStatusField.Create(ATests: TAtlasIdeTests; AExplorer: TAtlasIdeTestExplorer);
var
  mAction: TMenuAction;
  mItem: TMenuItem;
begin
  inherited Create;
  FTests := ATests;
  FExplorer := AExplorer;
  FMenu := TPopupMenu.Create(nil);
  for mAction := Low(TMenuAction) to High(TMenuAction) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasTestsStrings.Text(cMenuTexts[mAction]);
    mItem.Tag := Ord(mAction);
    mItem.OnClick := MenuClicked;
    FMenu.Items.Add(mItem);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  ApplySettings;
end;

destructor TAtlasIdeTestStatusField.Destroy;
begin
  // Erst der Zeitgeber, dann das Feld: Danach hält Base keinen Klick dieses Objekts mehr.
  FreeAndNil(FTimer);
  Clear;
  FreeAndNil(FMenu);
  FTests := nil;
  FExplorer := nil;
  inherited;
end;

class function TAtlasIdeTestStatusField.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.EditorStatusBar and
    TAtlasIdeSettings.Current.EditorStatusBarTests;
end;

procedure TAtlasIdeTestStatusField.ApplySettings;
begin
  FTimer.Enabled := Wanted;
  if FTimer.Enabled then
  begin
    // Neue Texte (Sprache) und Einstellungen sofort.
    FShown := '';
    FResolvedFor := '';
    Refresh;
  end
  else
  begin
    Clear;
  end;
end;

procedure TAtlasIdeTestStatusField.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build, Refresh);
end;

procedure TAtlasIdeTestStatusField.ResolveProject;
var
  mFile, mFor: string;
  mFound: TArray<IOTAProject>;
begin
  mFile := TopFileName;
  mFor := AnsiLowerCase(mFile + '|' + ActiveProjectFile);
  if mFor = FResolvedFor then
  begin
    Exit;
  end;
  FResolvedFor := mFor;
  FProject := '';
  mFound := nil;
  if mFile <> '' then
  begin
    mFound := TAtlasIdeTestProjects.TestProjects(mFile);
  end;
  if (Length(mFound) = 0) and TAtlasIdeTestProjects.IsTestProject(GetActiveProject) then
  begin
    FProject := GetActiveProject.FileName;
    Exit;
  end;
  if Length(mFound) = 0 then
  begin
    mFound := TAtlasIdeTestProjects.TestProjects('');
  end;
  if Length(mFound) > 0 then
  begin
    FProject := mFound[0].FileName;
  end;
end;

procedure TAtlasIdeTestStatusField.Refresh;
var
  mInput: TAtlasTestStatusInput;
begin
  ResolveProject;
  if FProject = '' then
  begin
    Clear;
    Exit;
  end;
  mInput := FExplorer.StatusInput(FProject);
  mInput.Project := ChangeFileExt(ExtractFileName(FProject), '');
  Show(TAtlasTestStatusField.Build(mInput, Texts));
end;

procedure TAtlasIdeTestStatusField.Show(const AStatus: TAtlasTestStatus);
var
  mKey: string;
  mExtra: TAtlasStatusExtra;
begin
  mKey := AStatus.Text + #1 + IntToStr(Ord(AStatus.State)) + #1 + AStatus.Hint;
  FRerunFailed := AStatus.RerunFailed;
  if mKey = FShown then
  begin
    Exit;
  end;
  FShown := mKey;
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := cId;
  mExtra.Text := AStatus.Text;
  mExtra.Hint := AStatus.Hint;
  mExtra.State := AStatus.State;
  mExtra.OnClick := Clicked;
  mExtra.OnContext := ContextClicked;
  TAtlasIdeHost.SetStatusItem(mExtra);
end;

procedure TAtlasIdeTestStatusField.Clear;
begin
  if FShown = '' then
  begin
    Exit;
  end;
  FShown := '';
  TAtlasIdeHost.SetStatusExtra(cId, '');
end;

procedure TAtlasIdeTestStatusField.Clicked(APoint: TPoint);
begin
  if FRerunFailed then
  begin
    RunFailed;
  end
  else
  begin
    RunAll;
  end;
end;

procedure TAtlasIdeTestStatusField.ContextClicked(APoint: TPoint);
begin
  FMenu.Items[Ord(TMenuAction.RunFailed)].Enabled := FRerunFailed;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeTestStatusField.MenuClicked(Sender: TObject);
begin
  case TMenuAction((Sender as TMenuItem).Tag) of
    TMenuAction.RunAll:
      RunAll;
    TMenuAction.RunFailed:
      RunFailed;
    TMenuAction.Affected:
      TAtlasIdeHost.ExecuteCommand(cCommandAffected);
    TMenuAction.Window:
      TAtlasIdeHost.ExecuteCommand(cCommandWindow);
    TMenuAction.Welcome:
      TAtlasIdeHost.ExecuteCommand(cCommandWelcome);
  end;
end;

procedure TAtlasIdeTestStatusField.RunAll;
var
  mReason: string;
begin
  if (FProject <> '') and not FTests.RunProject(FProject, mReason) and (mReason <> '') then
  begin
    FTests.Say(mReason);
  end;
end;

procedure TAtlasIdeTestStatusField.RunFailed;
var
  mCase: TTestCaseResult;
  mNames: TArray<string>;
  mFile: string;
begin
  mNames := nil;
  mFile := '';
  for mCase in FExplorer.StatusInput(FProject).Cases do
  begin
    if not mCase.IsFailure then
    begin
      Continue;
    end;
    mNames := mNames + [mCase.FullName];
    if mFile = '' then
    begin
      mFile := TAtlasIdeTests.UnitFileOf(FProject, mCase.UnitName);
    end;
  end;
  if (Length(mNames) = 0) or (mFile = '') then
  begin
    RunAll;
    Exit;
  end;
  // Die Testunit des ersten Fehlschlags bestimmt das Testprojekt wie bei der Testlinse.
  FTests.RunTests(mFile, mNames);
end;

end.
