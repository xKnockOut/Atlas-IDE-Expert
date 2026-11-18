unit Atlas.UI.Tests.LeakSetup.Tests;

// Dialog „Leckprüfung einrichten …“ (#1880) mit VCL: Der Konstruktor setzt die
// Vorauswahl, bevor die Varianten auf Klicks hören (sonst Zugriffsverletzung
// und kein Dialog); „Bericht als Datei“ nur mit FastMM, „Einrichten …“ nur mit
// einer möglichen Variante, ein Klick auf eine andere Variante passt beides an.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasLeakSetupDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PreselectsFastMM5WithFileReport;
    [Test]
    procedure SimpleWithoutFileReport;
    [Test]
    procedure PackageAllowsNoSetup;
    [Test]
    procedure ClickOnSimpleDisablesFileReport;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Tests.LeakSetup,
  Atlas.UI.Tests.LeakSetup,
  Atlas.UI.Tests.Strings;

type
  /// <summary>Zugriff auf den geschützten Text eines Steuerelements.</summary>
  TControlAccess = class(TControl);

function Info: TAtlasLeakSetupInfo;
begin
  Result := Default(TAtlasLeakSetupInfo);
  Result.Project := 'C:\P\App.dproj';
  Result.MainSource := 'C:\P\App.dpr';
  Result.Platform := 'Win64';
  Result.HasUses := True;
  Result.HasMainBlock := True;
  Result.UsesManager := TAtlasLeakChoice.Simple;
  Result.DllName := 'FastMM_FullDebugMode64.dll';
end;

/// <summary>Steuerelement der Klasse AClass mit Text ACaption unter AParent; nil ohne.</summary>
function FindByCaption(AParent: TWinControl; AClass: TControlClass; const ACaption: string): TControl;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    if (mControl is AClass) and (TControlAccess(mControl).Caption = ACaption) then
    begin
      Exit(mControl);
    end;
    if mControl is TWinControl then
    begin
      Result := FindByCaption(TWinControl(mControl), AClass, ACaption);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

function SetUpButton(ADialog: TAtlasLeakSetupDialog): TButton;
begin
  Result := FindByCaption(ADialog, TButton, TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakSetupButton)) as TButton;
end;

function FileReportBox(ADialog: TAtlasLeakSetupDialog): TCheckBox;
begin
  Result := FindByCaption(ADialog, TCheckBox, TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakFileReportOption)) as
    TCheckBox;
end;

function ChoiceButton(ADialog: TAtlasLeakSetupDialog; AText: TAtlasTestsTextId): TRadioButton;
begin
  Result := FindByCaption(ADialog, TRadioButton, TAtlasTestsStrings.Text(AText)) as TRadioButton;
end;

{ TAtlasLeakSetupDialogTests }

procedure TAtlasLeakSetupDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasLeakSetupDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasLeakSetupDialogTests.PreselectsFastMM5WithFileReport;
var
  mInfo: TAtlasLeakSetupInfo;
  mDialog: TAtlasLeakSetupDialog;
begin
  mInfo := Info;
  mInfo.Sources[TAtlasLeakChoice.FastMM5].FileName := 'C:\Lib\FastMM5.pas';
  mDialog := TAtlasLeakSetupDialog.CreateFor(nil, mInfo);
  try
    mDialog.HandleNeeded;
    Assert.IsTrue(ChoiceButton(mDialog, TAtlasTestsTextId.LeakChoiceFastMM5).Checked, 'Vorauswahl FastMM5');
    Assert.IsTrue(FileReportBox(mDialog).Enabled, 'Bericht als Datei mit FastMM');
    Assert.IsTrue(SetUpButton(mDialog).Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLeakSetupDialogTests.SimpleWithoutFileReport;
var
  mDialog: TAtlasLeakSetupDialog;
begin
  mDialog := TAtlasLeakSetupDialog.CreateFor(nil, Info);
  try
    mDialog.HandleNeeded;
    Assert.IsTrue(ChoiceButton(mDialog, TAtlasTestsTextId.LeakChoiceSimple).Checked, 'Vorauswahl Einfach');
    Assert.IsFalse(FileReportBox(mDialog).Enabled, 'Speichermanager der RTL meldet nur im Fenster');
    Assert.IsTrue(SetUpButton(mDialog).Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLeakSetupDialogTests.PackageAllowsNoSetup;
var
  mInfo: TAtlasLeakSetupInfo;
  mDialog: TAtlasLeakSetupDialog;
begin
  mInfo := Info;
  mInfo.IsPackage := True;
  mDialog := TAtlasLeakSetupDialog.CreateFor(nil, mInfo);
  try
    mDialog.HandleNeeded;
    Assert.IsFalse(SetUpButton(mDialog).Enabled, 'keine Variante möglich');
    Assert.IsFalse(FileReportBox(mDialog).Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLeakSetupDialogTests.ClickOnSimpleDisablesFileReport;
var
  mInfo: TAtlasLeakSetupInfo;
  mDialog: TAtlasLeakSetupDialog;
begin
  mInfo := Info;
  mInfo.Sources[TAtlasLeakChoice.FastMM4].FileName := 'C:\Lib\FastMM4.pas';
  mDialog := TAtlasLeakSetupDialog.CreateFor(nil, mInfo);
  try
    mDialog.HandleNeeded;
    Assert.IsTrue(FileReportBox(mDialog).Enabled, 'Vorauswahl FastMM4');
    ChoiceButton(mDialog, TAtlasTestsTextId.LeakChoiceSimple).Checked := True;
    Assert.IsFalse(FileReportBox(mDialog).Enabled, 'nach Klick auf Einfach');
    Assert.IsTrue(SetUpButton(mDialog).Enabled);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLeakSetupDialogTests);

end.
