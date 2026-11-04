unit Atlas.Core.Settings.Plugin.Store.Tests;

// Laden und Speichern der Plugin-Einstellungen über TAtlasSettingsExchange (#227, Records je Bereich):
// Lesen behält ohne gespeicherten Wert die Vorgabe, Schreiben legt Wahrheitswerte als 0/1 ab,
// jeder Wert steht genau einmal in einem Bereich, XmlDocFull wird übernommen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSettingsExchangeTests = class
  public
    [Test]
    procedure ReaderKeepsValueWithoutStoredValue;
    [Test]
    procedure ReaderTakesStoredValues;
    [Test]
    procedure WriterStoresFlagsAsNumbers;
    [Test]
    procedure TrimmedTextTrimsBothWays;
    /// <summary>Speichern schreibt jeden Namen einmal, und zwar genau die Namen der Bereichs-Records.</summary>
    [Test]
    procedure EveryValueBelongsToOneArea;
    /// <summary>Ohne XmlDocExpand gilt XmlDocFull von vor #770.</summary>
    [Test]
    procedure XmlDocFullIsAdopted;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.Core.Settings.Plugin.Bookmarks,
  Atlas.Core.Settings.Plugin.Build,
  Atlas.Core.Settings.Plugin.CodeActions,
  Atlas.Core.Settings.Plugin.Completion,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Core.Settings.Plugin.Editor,
  Atlas.Core.Settings.Plugin.General,
  Atlas.Core.Settings.Plugin.Highlighting,
  Atlas.Core.Settings.Plugin.Issues,
  Atlas.Core.Settings.Plugin.Keys,
  Atlas.Core.Settings.Plugin.Rules,
  Atlas.Core.Settings.Plugin.Snippets,
  Atlas.Core.Settings.Plugin.Vcs,
  Atlas.Core.Settings.Plugin.Welcome,
  Atlas.Core.Settings.TestSupport;

type
  /// <summary>Zählt, wie oft jeder Name geschrieben wird.</summary>
  TCountingStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FCounts: TDictionary<string, Integer>;
    procedure Count(const AName: string);
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    property Counts: TDictionary<string, Integer> read FCounts;
  end;

constructor TCountingStore.Create;
begin
  inherited Create;
  FCounts := TDictionary<string, Integer>.Create;
end;

destructor TCountingStore.Destroy;
begin
  FCounts.Free;
  inherited Destroy;
end;

procedure TCountingStore.Count(const AName: string);
var
  mCount: Integer;
begin
  if not FCounts.TryGetValue(AName, mCount) then
  begin
    mCount := 0;
  end;
  FCounts.AddOrSetValue(AName, mCount + 1);
end;

function TCountingStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
end;

procedure TCountingStore.WriteInteger(const AName: string; AValue: Integer);
begin
  Count(AName);
end;

function TCountingStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
end;

procedure TCountingStore.WriteString(const AName, AValue: string);
begin
  Count(AName);
end;

/// <summary>Schreibt die Vorgaben der Bereichs-Records Lesezeichen, Build, Code-Aktionen, Vervollständigung, Debuggen, Tippen über AWriter.</summary>
procedure WriteCodingAreas(const AWriter: TAtlasSettingsExchange);
var
  mBookmarks: TAtlasPluginBookmarksSettings;
  mBuild: TAtlasPluginBuildSettings;
  mCodeActions: TAtlasPluginCodeActionsSettings;
  mCompletion: TAtlasPluginCompletionSettings;
  mDebug: TAtlasPluginDebugSettings;
  mEditorTyping: TAtlasPluginEditorTypingSettings;
begin
  mBookmarks := TAtlasPluginBookmarksSettings.Defaults;
  mBookmarks.Exchange(AWriter);
  mBuild := TAtlasPluginBuildSettings.Defaults;
  mBuild.Exchange(AWriter);
  mCodeActions := TAtlasPluginCodeActionsSettings.Defaults;
  mCodeActions.Exchange(AWriter);
  mCompletion := TAtlasPluginCompletionSettings.Defaults;
  mCompletion.Exchange(AWriter);
  mDebug := TAtlasPluginDebugSettings.Defaults;
  mDebug.Exchange(AWriter);
  mEditorTyping := TAtlasPluginEditorTypingSettings.Defaults;
  mEditorTyping.Exchange(AWriter);
end;

/// <summary>Schreibt die Vorgaben der Bereichs-Records Hinweise, Navigation, Units suchen, Sticky Scroll, Ansicht, Server über AWriter.</summary>
procedure WriteEditorAreas(const AWriter: TAtlasSettingsExchange);
var
  mEditorInsight: TAtlasPluginEditorInsightSettings;
  mEditorNavigation: TAtlasPluginEditorNavigationSettings;
  mUnitSearch: TAtlasPluginUnitSearchSettings;
  mStickyScroll: TAtlasPluginStickyScrollSettings;
  mEditorView: TAtlasPluginEditorViewSettings;
  mGeneralServer: TAtlasPluginGeneralServerSettings;
begin
  mEditorInsight := TAtlasPluginEditorInsightSettings.Defaults;
  mEditorInsight.Exchange(AWriter);
  mEditorNavigation := TAtlasPluginEditorNavigationSettings.Defaults;
  mEditorNavigation.Exchange(AWriter);
  mUnitSearch := TAtlasPluginUnitSearchSettings.Defaults;
  mUnitSearch.Exchange(AWriter);
  mStickyScroll := TAtlasPluginStickyScrollSettings.Defaults;
  mStickyScroll.Exchange(AWriter);
  mEditorView := TAtlasPluginEditorViewSettings.Defaults;
  mEditorView.Exchange(AWriter);
  mGeneralServer := TAtlasPluginGeneralServerSettings.Defaults;
  mGeneralServer.Exchange(AWriter);
end;

/// <summary>Schreibt die Vorgaben der Bereichs-Records Allgemein, Hervorhebung, Issues, Tastenkürzel zum Bearbeiten, Vorrang über AWriter.</summary>
procedure WriteGeneralAreas(const AWriter: TAtlasSettingsExchange);
var
  mGeneral: TAtlasPluginGeneralSettings;
  mHighlighting: TAtlasPluginHighlightingSettings;
  mIssues: TAtlasPluginIssuesSettings;
  mIssueWork: TAtlasPluginIssueWorkSettings;
  mEditingKeys: TAtlasPluginEditingKeysSettings;
  mKeyPriorities: TAtlasPluginKeyPrioritiesSettings;
begin
  mGeneral := TAtlasPluginGeneralSettings.Defaults;
  mGeneral.Exchange(AWriter);
  mHighlighting := TAtlasPluginHighlightingSettings.Defaults;
  mHighlighting.Exchange(AWriter);
  mIssues := TAtlasPluginIssuesSettings.Defaults;
  mIssues.Exchange(AWriter);
  mIssueWork := TAtlasPluginIssueWorkSettings.Defaults;
  mIssueWork.Exchange(AWriter);
  mEditingKeys := TAtlasPluginEditingKeysSettings.Defaults;
  mEditingKeys.Exchange(AWriter);
  mKeyPriorities := TAtlasPluginKeyPrioritiesSettings.Defaults;
  mKeyPriorities.Exchange(AWriter);
end;

/// <summary>Schreibt die Vorgaben der Bereichs-Records Navigationstasten, Prüfregeln, Snippets, Versionsverwaltung, Willkommensseite über AWriter.</summary>
procedure WriteRemainingAreas(const AWriter: TAtlasSettingsExchange);
var
  mNavigationKeys: TAtlasPluginNavigationKeysSettings;
  mRules: TAtlasPluginRulesSettings;
  mSnippets: TAtlasPluginSnippetsSettings;
  mVcs: TAtlasPluginVcsSettings;
  mWelcome: TAtlasPluginWelcomeSettings;
  mWelcomeTiles: TAtlasPluginWelcomeTilesSettings;
begin
  mNavigationKeys := TAtlasPluginNavigationKeysSettings.Defaults;
  mNavigationKeys.Exchange(AWriter);
  mRules := TAtlasPluginRulesSettings.Defaults;
  mRules.Exchange(AWriter);
  mSnippets := TAtlasPluginSnippetsSettings.Defaults;
  mSnippets.Exchange(AWriter);
  mVcs := TAtlasPluginVcsSettings.Defaults;
  mVcs.Exchange(AWriter);
  mWelcome := TAtlasPluginWelcomeSettings.Defaults;
  mWelcome.Exchange(AWriter);
  mWelcomeTiles := TAtlasPluginWelcomeTilesSettings.Defaults;
  mWelcomeTiles.Exchange(AWriter);
end;

/// <summary>Schreibt die Vorgaben jedes Bereichs-Records einzeln nach AStore.</summary>
procedure WriteAreas(const AStore: IAtlasSettingsStore);
var
  mWriter: TAtlasSettingsExchange;
begin
  mWriter := TAtlasSettingsExchange.Writer(AStore);
  WriteCodingAreas(mWriter);
  WriteEditorAreas(mWriter);
  WriteGeneralAreas(mWriter);
  WriteRemainingAreas(mWriter);
end;

{ TSettingsExchangeTests }

procedure TSettingsExchangeTests.ReaderKeepsValueWithoutStoredValue;
var
  mStore: IAtlasSettingsStore;
  mReader: TAtlasSettingsExchange;
  mFlag: Boolean;
  mNumber: Integer;
  mText: string;
begin
  mStore := TMemoryStore.Create;
  mReader := TAtlasSettingsExchange.Reader(mStore);
  mFlag := True;
  mNumber := 7;
  mText := 'Vorgabe';
  mReader.Flag('Schalter', mFlag);
  mReader.Number('Zahl', mNumber);
  mReader.Text('Text', mText);
  Assert.IsTrue(mFlag);
  Assert.AreEqual(7, mNumber);
  Assert.AreEqual('Vorgabe', mText);
  Assert.IsFalse(mReader.Writing);
end;

procedure TSettingsExchangeTests.ReaderTakesStoredValues;
var
  mStore: IAtlasSettingsStore;
  mReader: TAtlasSettingsExchange;
  mFlag: Boolean;
  mNumber: Integer;
  mText: string;
begin
  mStore := TMemoryStore.Create;
  mStore.WriteInteger('Schalter', 0);
  mStore.WriteInteger('Zahl', 42);
  mStore.WriteString('Text', 'gespeichert');
  mReader := TAtlasSettingsExchange.Reader(mStore);
  mFlag := True;
  mNumber := 7;
  mText := 'Vorgabe';
  mReader.Flag('Schalter', mFlag);
  mReader.Number('Zahl', mNumber);
  mReader.Text('Text', mText);
  Assert.IsFalse(mFlag);
  Assert.AreEqual(42, mNumber);
  Assert.AreEqual('gespeichert', mText);
end;

procedure TSettingsExchangeTests.WriterStoresFlagsAsNumbers;
var
  mStore: IAtlasSettingsStore;
  mWriter: TAtlasSettingsExchange;
  mOn: Boolean;
  mOff: Boolean;
begin
  mStore := TMemoryStore.Create;
  mWriter := TAtlasSettingsExchange.Writer(mStore);
  mOn := True;
  mOff := False;
  mWriter.Flag('An', mOn);
  mWriter.Flag('Aus', mOff);
  Assert.AreEqual(1, mStore.ReadInteger('An', -1));
  Assert.AreEqual(0, mStore.ReadInteger('Aus', -1));
  Assert.IsTrue(mWriter.Writing);
end;

procedure TSettingsExchangeTests.TrimmedTextTrimsBothWays;
var
  mStore: IAtlasSettingsStore;
  mText: string;
begin
  mStore := TMemoryStore.Create;
  mText := '  C:\Atlas ';
  TAtlasSettingsExchange.Writer(mStore).TrimmedText('Pfad', mText);
  Assert.AreEqual('C:\Atlas', mStore.ReadString('Pfad', ''));
  Assert.AreEqual('  C:\Atlas ', mText, 'Schreiben ändert den Wert nicht');
  mStore.WriteString('Pfad', ' D:\Neu  ');
  TAtlasSettingsExchange.Reader(mStore).TrimmedText('Pfad', mText);
  Assert.AreEqual('D:\Neu', mText);
end;

procedure TSettingsExchangeTests.EveryValueBelongsToOneArea;
var
  mWhole: TCountingStore;
  mWholeStore: IAtlasSettingsStore;
  mAreas: TCountingStore;
  mAreasStore: IAtlasSettingsStore;
  mPair: TPair<string, Integer>;
  mSettings: TAtlasPluginSettings;
begin
  mWhole := TCountingStore.Create;
  mWholeStore := mWhole;
  mAreas := TCountingStore.Create;
  mAreasStore := mAreas;
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.Save(mWholeStore);
  WriteAreas(mAreasStore);
  Assert.IsTrue(mWhole.Counts.Count > 0);
  Assert.AreEqual(mWhole.Counts.Count, mAreas.Counts.Count);
  for mPair in mWhole.Counts do
  begin
    Assert.AreEqual(1, mPair.Value, mPair.Key + ' mehrfach geschrieben');
    Assert.IsTrue(mAreas.Counts.ContainsKey(mPair.Key), mPair.Key + ' in keinem Bereich');
  end;
end;

procedure TSettingsExchangeTests.XmlDocFullIsAdopted;
var
  mStore: IAtlasSettingsStore;
  mSettings: TAtlasPluginSettings;
begin
  mStore := TMemoryStore.Create;
  mStore.WriteInteger('XmlDocFull', 1);
  mSettings.Load(mStore);
  Assert.AreEqual('expanded', mSettings.XmlDocExpand);
  mStore.WriteInteger('XmlDocFull', 0);
  mSettings.Load(mStore);
  Assert.AreEqual('collapsed', mSettings.XmlDocExpand);
  mStore.WriteString('XmlDocExpand', 'last');
  mSettings.Load(mStore);
  Assert.AreEqual('last', mSettings.XmlDocExpand, 'XmlDocExpand hat Vorrang');
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsExchangeTests);

end.
