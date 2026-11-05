unit Atlas.UI.Settings.Page.Parts.Tests;

// Tests für die Teile der Optionsseite: Jeder Teil ist über Part<T> erreichbar, ein fehlender meldet sich.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPagePartsTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Jeder Teil, den die Seite anlegt, ist genau einmal da und über seine Klasse erreichbar.</summary>
    [Test]
    procedure EveryPartReachable;
    /// <summary>Ein Teil, den die Seite nicht angelegt hat, ist ein Programmierfehler mit Klassennamen.</summary>
    [Test]
    procedure MissingPartRaises;
    /// <summary>Ohne angemeldete Module zeigt die Seite keine Einstellung eines Moduls (#1456): Base baut nur seine
    /// eigenen, die der Module bringen die Module als Abschnitte mit.</summary>
    [Test]
    procedure NoModuleSettingsWithoutModules;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.Host,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.Colors,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.VcsProjects,
  Atlas.UI.Settings.Page.Sections,
  Atlas.UI.Settings.Page.TestSupport;

type
  /// <summary>Teil, den die Seite nie anlegt.</summary>
  TAtlasUnknownPart = class(TAtlasSettingsPagePart)
  end;

procedure TAtlasSettingsPagePartsTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TAtlasSettingsPagePartsTests.EveryPartReachable;
var
  mPage: TAtlasSettingsPage;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsNotNull(mPage.Part<TAtlasSettingsGeneralPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsNotificationsPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsCompletionPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsFavoritesPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsColorsPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsIndexPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsVcsProjectsPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsVcsProjectAddPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsVcsServersPart>);
    Assert.IsNotNull(mPage.Part<TAtlasSettingsSectionsPart>);
    Assert.AreSame(mPage.Part<TAtlasSettingsGeneralPart>, mPage.Part<TAtlasSettingsGeneralPart>, 'derselbe Teil');
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsPagePartsTests.MissingPartRaises;
var
  mPage: TAtlasSettingsPage;
  mMessage: string;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mMessage := '';
    try
      Assert.IsNull(mPage.Part<TAtlasUnknownPart>, 'kein Teil ohne Fehler');
    except
      on mError: EInvalidOperation do
      begin
        mMessage := mError.Message;
      end;
    end;
    Assert.IsTrue(Pos('TAtlasUnknownPart', mMessage) > 0, mMessage);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsPagePartsTests.NoModuleSettingsWithoutModules;
const
  cModuleSettings: array[0..9] of string = ('DebugEnabled', 'TestsEnabled', 'BuildToolsEnabled', 'ReleaseGuard',
    'SearchEnabled', 'AnalysisEnabled', 'BookmarksEnabled', 'DesignerEnabled', 'WelcomePage', 'IssuesEnabled');
var
  mPage: TAtlasSettingsPage;
  mName: string;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    for mName in cModuleSettings do
    begin
      Assert.IsNull(mPage.ControlOfSetting(mName), mName);
    end;
    Assert.IsNotNull(mPage.ControlOfSetting('CheckOnSave'), 'Einstellung von Base');
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPagePartsTests);

end.
