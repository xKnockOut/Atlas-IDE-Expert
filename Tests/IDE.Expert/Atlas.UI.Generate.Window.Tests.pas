unit Atlas.UI.Generate.Window.Tests;

// Tests für das Fenster des Erzeugen-Menüs (#719): Beschriftungen wie im
// Entwurf (AC7), Gruppenköpfe, Ziffern, Entf blendet aus und der zweite
// Schritt mit Auswahl. Das Fenster wird dafür nicht gezeigt.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasGenerateWindowTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Entwurf AC7: Kopf „Erzeugen“, Zeilen 1–6.</summary>
    [Test]
    procedure CaptionsLikeMockup;
    [Test]
    procedure EveryCatalogCommandHasCaption;
    [Test]
    procedure DeleteHidesEntry;
    [Test]
    procedure StepWithChoicesPrechecksAll;
  end;

implementation

uses
  Atlas.UI.Generate.Strings,
  System.SysUtils,
  Winapi.Windows,
  Atlas.Core.Style.Palette,
  Atlas.Core.Generate.Menu,
  Atlas.UI.Generate.Window;

const
  cMockupNames: array[0..5] of string = ('ctor', 'dtor', 'prop', 'override', 'implement', 'equals');
  // Alle Schnellbefehle des Menükatalogs (Atlas.Common.Editing.SlashMenu) plus „implement“.
  cCatalogNames: array[0..51] of string = ('ctor', 'dtor', 'prop', 'override', 'implement', 'equals', 'impl', 'field',
    'encapsulate', 'clone', 'assign', 'json', 'msg', 'notify', 'changed', 'loaded', 'notification', 'singleton',
    'list', 'dict', 'dict!', 'operator', 'guid', 'var', 'const', 'const!', 'guard', 'raise', 'log', 'sql', 'params',
    'record', 'enum', 'enum!', 'helper', 'exception', 'thread', 'external', 'exports', 'todo', 'try', 'except',
    'lock', 'sync', 'sync!', 'ifdef', 'region', 'measure', 'task', 'future', 'loop', 'transaction');

type
  /// <summary>Zugriff auf die geschützten Tastenmethoden.</summary>
  TWindowAccess = class(TAtlasGenerateWindow);

function Slash(const AName: string; AGroup: TAtlasGenerateGroup): TAtlasGenerateEntry;
begin
  Result := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Slash, AGroup, AName, 'Server: ' + AName);
end;

function MockupEntries: TArray<TAtlasGenerateEntry>;
var
  mName: string;
begin
  Result := nil;
  for mName in cMockupNames do
  begin
    Result := Result + [Slash(mName, TAtlasGenerateGroup.Generate)];
  end;
  Result[0].HasChoices := True;
  Result[0].Multi := True;
  Result[0].Separator := ', ';
  Result[0].Argument := TAtlasGenerateArgument.Optional;
end;

procedure TAtlasGenerateWindowTests.WarmUpFirstUse;
begin
  Setup;
  try
    CaptionsLikeMockup;
  finally
    TearDown;
  end;
  Setup;
  try
    DeleteHidesEntry;
  finally
    TearDown;
  end;
end;

procedure TAtlasGenerateWindowTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasGenerateWindowTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasGenerateWindowTests.CaptionsLikeMockup;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mWindow: TAtlasGenerateWindow;
  mCaptions: TArray<string>;
  mRow: TAtlasGenerateRow;
begin
  mEntries := MockupEntries;
  mWindow := TAtlasGenerateWindow.CreateMenu(nil, mEntries, TAtlasGenerateOptions.Default, nil, TAtlasColors.Light);
  try
    Assert.AreEqual('Erzeugen', TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateTitle));
    Assert.AreEqual('Erzeugen', TAtlasGenerateTexts.GroupCaption(mWindow.Rows[0].Group));
    Assert.IsTrue(mWindow.Rows[0].IsHeader);
    mCaptions := nil;
    for mRow in mWindow.Rows do
    begin
      if not mRow.IsHeader then
      begin
        mCaptions := mCaptions + [IntToStr(mRow.Digit) + ' ' + TAtlasGenerateTexts.EntryCaption(mEntries[mRow.Entry])];
      end;
    end;
    Assert.AreEqual('1 Konstruktor aus Feldern|2 Destruktor mit Freigabe|3 Property mit Feld|' +
      '4 Methoden überschreiben…|5 Interface implementieren…|6 Equals / GetHashCode', string.Join('|', mCaptions));
    Assert.AreEqual(1, mWindow.Selected, 'erster Eintrag unter dem Kopf gewählt');
  finally
    mWindow.Free;
  end;
  // Ohne eigenen Text: die Kurzbeschreibung des Servers; Vorlagen und Code-Aktionen behalten ihre Beschriftung.
  Assert.AreEqual('Server: neu', TAtlasGenerateTexts.EntryCaption(Slash('neu', TAtlasGenerateGroup.Generate)));
  Assert.AreEqual('try…finally', TAtlasGenerateTexts.EntryCaption(TAtlasGenerateEntry.Create(
    TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates, 'tryf', 'try…finally')));
end;

procedure TAtlasGenerateWindowTests.EveryCatalogCommandHasCaption;
var
  mName: string;
begin
  for mName in cCatalogNames do
  begin
    Assert.IsFalse(TAtlasGenerateTexts.EntryCaption(Slash(mName, TAtlasGenerateGroup.Generate)).StartsWith('Server'),
      mName);
  end;
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Constructor from fields',
    TAtlasGenerateTexts.EntryCaption(Slash('ctor', TAtlasGenerateGroup.Generate)));
end;

procedure TAtlasGenerateWindowTests.DeleteHidesEntry;
var
  mWindow: TAtlasGenerateWindow;
  mHidden: string;
  mKey: Word;
  mCount: Integer;
  mRow: TAtlasGenerateRow;
begin
  mWindow := TAtlasGenerateWindow.CreateMenu(nil, MockupEntries, TAtlasGenerateOptions.Default, nil,
    TAtlasColors.Light);
  try
    mHidden := '';
    mWindow.OnHide :=
      procedure(const AEntry: TAtlasGenerateEntry)
      begin
        mHidden := AEntry.Id;
      end;
    mKey := VK_DOWN;
    TWindowAccess(mWindow).KeyDown(mKey, []);
    mKey := VK_DELETE;
    TWindowAccess(mWindow).KeyDown(mKey, []);
    Assert.AreEqual('slash:dtor', mHidden);
    mCount := 0;
    for mRow in mWindow.Rows do
    begin
      if not mRow.IsHeader then
      begin
        Inc(mCount);
      end;
    end;
    Assert.AreEqual(5, mCount, 'ausgeblendet');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasGenerateWindowTests.StepWithChoicesPrechecksAll;
var
  mWindow: TAtlasGenerateWindow;
  mAsked: string;
  mKey: Word;
begin
  mWindow := TAtlasGenerateWindow.CreateMenu(nil, MockupEntries, TAtlasGenerateOptions.Default, nil,
    TAtlasColors.Light);
  try
    mAsked := '';
    mWindow.OnChoices :=
      function(const AEntry: TAtlasGenerateEntry): TArray<string>
      begin
        mAsked := AEntry.Name;
        Result := ['FName', 'FAlter'];
      end;
    // Enter auf „Konstruktor aus Feldern“: zweiter Schritt mit den Feldern.
    mKey := VK_RETURN;
    TWindowAccess(mWindow).KeyDown(mKey, []);
    Assert.AreEqual('ctor', mAsked);
    Assert.IsTrue(mWindow.InStep);
    // Escape führt zurück zur Liste.
    mKey := VK_ESCAPE;
    TWindowAccess(mWindow).KeyDown(mKey, []);
    Assert.IsFalse(mWindow.InStep);
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateWindowTests);

end.
