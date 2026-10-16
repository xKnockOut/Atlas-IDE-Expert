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
  System.SysUtils,
  Winapi.Windows,
  Atlas.Core.Style.Palette,
  Atlas.Core.Generate.Menu,
  Atlas.UI.Generate.Window;

const
  MockupNames: array[0..5] of string = ('ctor', 'dtor', 'prop', 'override', 'implement', 'equals');
  // Alle Schnellbefehle des Menükatalogs (Atlas.Common.Editing.SlashMenu) plus „implement“.
  CatalogNames: array[0..51] of string = ('ctor', 'dtor', 'prop', 'override', 'implement', 'equals', 'impl', 'field',
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
  Name: string;
begin
  Result := nil;
  for Name in MockupNames do
    Result := Result + [Slash(Name, TAtlasGenerateGroup.Generate)];
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
  Entries: TArray<TAtlasGenerateEntry>;
  Window: TAtlasGenerateWindow;
  Captions: TArray<string>;
  Row: TAtlasGenerateRow;
begin
  Entries := MockupEntries;
  Window := TAtlasGenerateWindow.CreateMenu(nil, Entries, TAtlasGenerateOptions.Default, nil, TAtlasColors.Light);
  try
    Assert.AreEqual('Erzeugen', TAtlasStrings.Text(TAtlasTextId.GenerateTitle));
    Assert.AreEqual('Erzeugen', TAtlasGenerateWindow.GroupCaption(Window.Rows[0].Group));
    Assert.IsTrue(Window.Rows[0].IsHeader);
    Captions := nil;
    for Row in Window.Rows do
      if not Row.IsHeader then
        Captions := Captions + [IntToStr(Row.Digit) + ' ' + TAtlasGenerateWindow.EntryCaption(Entries[Row.Entry])];
    Assert.AreEqual('1 Konstruktor aus Feldern|2 Destruktor mit Freigabe|3 Property mit Feld|' +
      '4 Methoden überschreiben…|5 Interface implementieren…|6 Equals / GetHashCode', string.Join('|', Captions));
    Assert.AreEqual(1, Window.Selected, 'erster Eintrag unter dem Kopf gewählt');
  finally
    Window.Free;
  end;
  // Ohne eigenen Text: die Kurzbeschreibung des Servers; Vorlagen und Code-Aktionen behalten ihre Beschriftung.
  Assert.AreEqual('Server: neu', TAtlasGenerateWindow.EntryCaption(Slash('neu', TAtlasGenerateGroup.Generate)));
  Assert.AreEqual('try…finally', TAtlasGenerateWindow.EntryCaption(TAtlasGenerateEntry.Create(
    TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates, 'tryf', 'try…finally')));
end;

procedure TAtlasGenerateWindowTests.EveryCatalogCommandHasCaption;
var
  Name: string;
begin
  for Name in CatalogNames do
    Assert.IsFalse(TAtlasGenerateWindow.EntryCaption(Slash(Name, TAtlasGenerateGroup.Generate)).StartsWith('Server'),
      Name);
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Constructor from fields',
    TAtlasGenerateWindow.EntryCaption(Slash('ctor', TAtlasGenerateGroup.Generate)));
end;

procedure TAtlasGenerateWindowTests.DeleteHidesEntry;
var
  Window: TAtlasGenerateWindow;
  Hidden: string;
  Key: Word;
  Count: Integer;
  Row: TAtlasGenerateRow;
begin
  Window := TAtlasGenerateWindow.CreateMenu(nil, MockupEntries, TAtlasGenerateOptions.Default, nil,
    TAtlasColors.Light);
  try
    Hidden := '';
    Window.OnHide :=
      procedure(const AEntry: TAtlasGenerateEntry)
      begin
        Hidden := AEntry.Id;
      end;
    Key := VK_DOWN;
    TWindowAccess(Window).KeyDown(Key, []);
    Key := VK_DELETE;
    TWindowAccess(Window).KeyDown(Key, []);
    Assert.AreEqual('slash:dtor', Hidden);
    Count := 0;
    for Row in Window.Rows do
      if not Row.IsHeader then
        Inc(Count);
    Assert.AreEqual(5, Count, 'ausgeblendet');
  finally
    Window.Free;
  end;
end;

procedure TAtlasGenerateWindowTests.StepWithChoicesPrechecksAll;
var
  Window: TAtlasGenerateWindow;
  Asked: string;
  Key: Word;
begin
  Window := TAtlasGenerateWindow.CreateMenu(nil, MockupEntries, TAtlasGenerateOptions.Default, nil,
    TAtlasColors.Light);
  try
    Asked := '';
    Window.OnChoices :=
      function(const AEntry: TAtlasGenerateEntry): TArray<string>
      begin
        Asked := AEntry.Name;
        Result := ['FName', 'FAlter'];
      end;
    // Enter auf „Konstruktor aus Feldern“: zweiter Schritt mit den Feldern.
    Key := VK_RETURN;
    TWindowAccess(Window).KeyDown(Key, []);
    Assert.AreEqual('ctor', Asked);
    Assert.IsTrue(Window.InStep);
    // Escape führt zurück zur Liste.
    Key := VK_ESCAPE;
    TWindowAccess(Window).KeyDown(Key, []);
    Assert.IsFalse(Window.InStep);
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateWindowTests);

end.
