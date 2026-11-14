unit Atlas.Core.Designer.DesktopSwitch.Tests;

// Tests für das eigene Desktop-Layout im Designer (#2079): Entprellen,
// Wechsel in den Designer und zurück (vorheriges bzw. Standard-Layout),
// schon aktives und fehlendes Layout, im Designer selbst gewähltes Layout,
// Debug-Sitzung, ladendes Projekt und Ausschalten; Layoutnamen des
// Auswahlfelds und der Registry.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.DesktopSwitch;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesktopSwitchTests = class
  private
    FSwitch: TAtlasDesktopSwitch;
    function Step(const AOptions: TAtlasDesktopSwitchOptions; AView: TAtlasDesktopView; ATicks: UInt64;
      const ACurrent: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WaitsForDelay;
    [Test]
    procedure QuickToggleDoesNothing;
    [Test]
    procedure BackToPrevious;
    [Test]
    procedure BackToIdeDefault;
    [Test]
    procedure AlreadyActive;
    [Test]
    procedure MissingReportedOnce;
    [Test]
    procedure OwnChoiceInDesignerStays;
    [Test]
    procedure DebuggingWaitsAndRechecks;
    [Test]
    procedure DebuggingAllowed;
    [Test]
    procedure ProjectLoadingWaits;
    [Test]
    procedure DisabledForgets;
    [Test]
    procedure EmptyNameDoesNothing;
    [Test]
    procedure UsableSkipsNone;
    [Test]
    procedure DisplayNameOfStoredLayout;
  end;

implementation

uses
  System.SysUtils;

const
  cDefault = 'Default Layout';
  cDesigner = 'Designer';
  cClassic = 'Classic Undocked';

function Options: TAtlasDesktopSwitchOptions;
begin
  Result := TAtlasDesktopSwitchOptions.Defaults;
  Result.Enabled := True;
  Result.DesignerLayout := cDesigner;
end;

function State(AView: TAtlasDesktopView; ATicks: UInt64; const ACurrent: string): TAtlasDesktopState;
begin
  Result := Default(TAtlasDesktopState);
  Result.View := AView;
  Result.Ticks := ATicks;
  Result.CurrentLayout := ACurrent;
  Result.DefaultLayout := cDefault;
  Result.Layouts := TArray<string>.Create(cDefault, 'Debug Layout', cDesigner, cClassic);
end;

function ActionText(const AAction: TAtlasDesktopAction): string;
begin
  case AAction.Kind of
    TAtlasDesktopActionKind.Load:
      begin
        Result := 'laden ' + AAction.Layout;
        if AAction.ToDesigner then
        begin
          Result := Result + ' (Designer)';
        end;
      end;
    TAtlasDesktopActionKind.Missing:
      Result := 'fehlt ' + AAction.Layout;
  else
    Result := '-';
  end;
end;

procedure TAtlasDesktopSwitchTests.Setup;
begin
  FSwitch := TAtlasDesktopSwitch.Create;
end;

procedure TAtlasDesktopSwitchTests.TearDown;
begin
  FreeAndNil(FSwitch);
end;

function TAtlasDesktopSwitchTests.Step(const AOptions: TAtlasDesktopSwitchOptions; AView: TAtlasDesktopView;
  ATicks: UInt64; const ACurrent: string): string;
begin
  Result := ActionText(FSwitch.Step(AOptions, State(AView, ATicks, ACurrent)));
end;

procedure TAtlasDesktopSwitchTests.WaitsForDelay;
begin
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 1000, cClassic), 'Code beim Start');
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 1400, cClassic), 'Code bleibt Code');
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Designer, 2000, cClassic), 'gerade gewechselt');
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Designer, 2299, cClassic), 'noch keine 300 ms');
  Assert.AreEqual('laden Designer (Designer)', Step(Options, TAtlasDesktopView.Designer, 2300, cClassic));
  Assert.AreEqual(cClassic, FSwitch.Remembered, 'vorheriges Layout gemerkt');
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Designer, 2400, cDesigner), 'nur einmal');
end;

procedure TAtlasDesktopSwitchTests.QuickToggleDoesNothing;
var
  mTicks: UInt64;
begin
  mTicks := 1000;
  Step(Options, TAtlasDesktopView.Code, mTicks, cDefault);
  Step(Options, TAtlasDesktopView.Code, mTicks + 500, cDefault);
  // F12 im 100-ms-Takt hin und her: keine Ansicht bleibt 300 ms stehen.
  while mTicks < 3000 do
  begin
    Inc(mTicks, 100);
    Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Designer, mTicks, cDefault));
    Inc(mTicks, 100);
    Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, mTicks, cDefault));
  end;
end;

procedure TAtlasDesktopSwitchTests.BackToPrevious;
begin
  Step(Options, TAtlasDesktopView.Designer, 0, cClassic);
  Assert.AreEqual('laden Designer (Designer)', Step(Options, TAtlasDesktopView.Designer, 300, cClassic));
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 1000, cDesigner));
  Assert.AreEqual('laden Classic Undocked', Step(Options, TAtlasDesktopView.Code, 1300, cDesigner));
  Assert.AreEqual('', FSwitch.Remembered, 'vergessen nach dem Zurückschalten');
end;

procedure TAtlasDesktopSwitchTests.BackToIdeDefault;
var
  mOptions: TAtlasDesktopSwitchOptions;
begin
  mOptions := Options;
  mOptions.ReturnTo := TAtlasDesktopReturn.IdeDefault;
  Step(mOptions, TAtlasDesktopView.Designer, 0, cClassic);
  Step(mOptions, TAtlasDesktopView.Designer, 300, cClassic);
  Step(mOptions, TAtlasDesktopView.Code, 1000, cDesigner);
  Assert.AreEqual('laden Default Layout', Step(mOptions, TAtlasDesktopView.Code, 1300, cDesigner));
end;

procedure TAtlasDesktopSwitchTests.AlreadyActive;
begin
  // Schon im Designer-Layout (etwa von Hand gewählt): kein Laden, und zurück gibt es nichts Gemerktes.
  Step(Options, TAtlasDesktopView.Designer, 0, 'designer');
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Designer, 300, 'designer'), 'ohne Groß-/Kleinschreibung');
  Step(Options, TAtlasDesktopView.Code, 1000, cDesigner);
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 1300, cDesigner));
end;

procedure TAtlasDesktopSwitchTests.MissingReportedOnce;
var
  mOptions: TAtlasDesktopSwitchOptions;
begin
  mOptions := Options;
  mOptions.DesignerLayout := 'Gelöscht';
  Step(mOptions, TAtlasDesktopView.Designer, 0, cDefault);
  Assert.AreEqual('fehlt Gelöscht', Step(mOptions, TAtlasDesktopView.Designer, 300, cDefault));
  Step(mOptions, TAtlasDesktopView.Code, 1000, cDefault);
  Assert.AreEqual('-', Step(mOptions, TAtlasDesktopView.Code, 1300, cDefault));
  Step(mOptions, TAtlasDesktopView.Designer, 2000, cDefault);
  Assert.AreEqual('-', Step(mOptions, TAtlasDesktopView.Designer, 2300, cDefault), 'nur einmal melden');
end;

procedure TAtlasDesktopSwitchTests.OwnChoiceInDesignerStays;
begin
  Step(Options, TAtlasDesktopView.Designer, 0, cDefault);
  Step(Options, TAtlasDesktopView.Designer, 300, cDefault);
  // Im Designer selbst ein anderes Layout gewählt: zurück im Code bleibt es.
  Step(Options, TAtlasDesktopView.Code, 1000, cClassic);
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 1300, cClassic));
end;

procedure TAtlasDesktopSwitchTests.DebuggingWaitsAndRechecks;
var
  mState: TAtlasDesktopState;
begin
  Step(Options, TAtlasDesktopView.Designer, 0, cDefault);
  Step(Options, TAtlasDesktopView.Designer, 300, cDefault);
  // Debuggen aus dem Designer: die IDE lädt ihr Debug-Layout, Atlas hält still, auch im Code.
  mState := State(TAtlasDesktopView.Code, 1000, 'Debug Layout');
  mState.Debugging := True;
  Assert.AreEqual('-', ActionText(FSwitch.Step(Options, mState)));
  mState.Ticks := 1500;
  Assert.AreEqual('-', ActionText(FSwitch.Step(Options, mState)));
  mState.View := TAtlasDesktopView.Designer;
  mState.Ticks := 2000;
  FSwitch.Step(Options, mState);
  mState.Ticks := 2500;
  Assert.AreEqual('-', ActionText(FSwitch.Step(Options, mState)));
  // Ende der Sitzung: die IDE kehrt zum Standard-Layout zurück, der Designer ist vorn: neu prüfen.
  Assert.AreEqual('laden Designer (Designer)', Step(Options, TAtlasDesktopView.Designer, 2600, cDefault));
end;

procedure TAtlasDesktopSwitchTests.DebuggingAllowed;
var
  mOptions: TAtlasDesktopSwitchOptions;
  mState: TAtlasDesktopState;
begin
  mOptions := Options;
  mOptions.SkipWhileDebugging := False;
  mState := State(TAtlasDesktopView.Designer, 0, 'Debug Layout');
  mState.Debugging := True;
  FSwitch.Step(mOptions, mState);
  mState.Ticks := 300;
  Assert.AreEqual('laden Designer (Designer)', ActionText(FSwitch.Step(mOptions, mState)));
end;

procedure TAtlasDesktopSwitchTests.ProjectLoadingWaits;
var
  mState: TAtlasDesktopState;
begin
  mState := State(TAtlasDesktopView.Designer, 0, cDefault);
  mState.ProjectLoading := True;
  FSwitch.Step(Options, mState);
  mState.Ticks := 1000;
  Assert.AreEqual('-', ActionText(FSwitch.Step(Options, mState)));
  Assert.AreEqual('laden Designer (Designer)', Step(Options, TAtlasDesktopView.Designer, 1100, cDefault));
end;

procedure TAtlasDesktopSwitchTests.DisabledForgets;
var
  mOff: TAtlasDesktopSwitchOptions;
begin
  Step(Options, TAtlasDesktopView.Designer, 0, cClassic);
  Step(Options, TAtlasDesktopView.Designer, 300, cClassic);
  mOff := Options;
  mOff.Enabled := False;
  Assert.AreEqual('-', Step(mOff, TAtlasDesktopView.Code, 1000, cDesigner));
  Assert.AreEqual('-', Step(mOff, TAtlasDesktopView.Code, 2000, cDesigner));
  Assert.AreEqual('', FSwitch.Remembered, 'ausgeschaltet vergessen');
  // Wieder an, im Code: das Designer-Layout ist noch aktiv, aber nichts gemerkt.
  Step(Options, TAtlasDesktopView.Code, 3000, cDesigner);
  Assert.AreEqual('-', Step(Options, TAtlasDesktopView.Code, 3300, cDesigner));
  // Wieder an, im Designer: zählt wie ein frischer Wechsel.
  Step(Options, TAtlasDesktopView.Designer, 4000, cDefault);
  Assert.AreEqual('laden Designer (Designer)', Step(Options, TAtlasDesktopView.Designer, 4300, cDefault));
end;

procedure TAtlasDesktopSwitchTests.EmptyNameDoesNothing;
var
  mOptions: TAtlasDesktopSwitchOptions;
begin
  mOptions := Options;
  mOptions.DesignerLayout := '';
  Step(mOptions, TAtlasDesktopView.Designer, 0, cDefault);
  Assert.AreEqual('-', Step(mOptions, TAtlasDesktopView.Designer, 1000, cDefault));
end;

procedure TAtlasDesktopSwitchTests.UsableSkipsNone;
var
  mLayouts: TArray<string>;
begin
  mLayouts := TAtlasDesktopLayouts.Usable(TArray<string>.Create('<kein>', 'Debug-Layout', '', 'Standard-Layout'));
  Assert.AreEqual(2, Integer(Length(mLayouts)));
  Assert.AreEqual('Debug-Layout', mLayouts[0]);
  Assert.AreEqual('Standard-Layout', mLayouts[1]);
end;

procedure TAtlasDesktopSwitchTests.DisplayNameOfStoredLayout;
var
  mGerman: TArray<string>;
  mEnglish: TArray<string>;
begin
  mGerman := TArray<string>.Create('Debug-Layout', 'Designer', 'Standard-Layout', 'Start-Layout');
  mEnglish := TArray<string>.Create('Debug Layout', 'Default Layout', 'Startup Layout');
  Assert.AreEqual('Standard-Layout', TAtlasDesktopLayouts.DisplayName(mGerman, 'Default Layout'));
  Assert.AreEqual('Start-Layout', TAtlasDesktopLayouts.DisplayName(mGerman, 'Startup Layout'));
  Assert.AreEqual('Debug-Layout', TAtlasDesktopLayouts.DisplayName(mGerman, 'Debug Layout'));
  Assert.AreEqual('Designer', TAtlasDesktopLayouts.DisplayName(mGerman, 'designer'));
  Assert.AreEqual('Default Layout', TAtlasDesktopLayouts.DisplayName(mEnglish, 'Default Layout'));
  Assert.AreEqual('', TAtlasDesktopLayouts.DisplayName(mEnglish, 'Fehlt'));
  Assert.AreEqual('', TAtlasDesktopLayouts.DisplayName(mGerman, ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesktopSwitchTests);

end.
