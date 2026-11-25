unit Atlas.Core.Commands.CustomKeys.Tests;

// Tests für frei zugewiesene Tastenkürzel der Palettenbefehle (#2938): Lesen
// und Schreiben der Einstellung keys.commands, Unlesbares fällt weg, eine
// Kennung gilt einmal, Zuweisen ersetzt und Taste 0 entfernt. Dazu, welcher
// Tastendruck im Dialog als Taste gilt, und die Zeilen im Fenster
// „Tastenkürzel“: Befehle ohne Taste, Zuweisen in die richtige Einstellung,
// andere Belegungen einer Taste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommandKeysTests = class
  public
    [Test]
    procedure ParseAndFormatRoundTrip;
    [Test]
    procedure ParseDropsInvalidEntries;
    [Test]
    procedure LastEntryWinsIgnoringCase;
    [Test]
    procedure AssignReplacesAndZeroRemoves;
    [Test]
    procedure KeyOfWithoutEntryIsZero;
    [Test]
    procedure CaptureNeedsCtrlOrAltExceptFunctionKeys;
  end;

  [TestFixture]
  TAtlasCommandKeyRowsTests = class
  public
    [Test]
    procedure KeylessItemsSkipKeyedAndForeignCommands;
    [Test]
    procedure AssignWritesCustomOrFunctionSetting;
    [Test]
    procedure HoldersOfNamesOtherRowsOnly;
    [Test]
    procedure CommandItemHoldsFreeKey;
    [Test]
    procedure UnitSearchActionNotAssignable;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Commands.KeyScan,
  Atlas.Core.Commands.CustomKeys;

const
  cCtrlD = $4044;
  cCtrlAltM = $C04D;

{ TAtlasCommandKeysTests }

procedure TAtlasCommandKeysTests.ParseAndFormatRoundTrip;
var
  mKeys: TArray<TAtlasCommandKey>;
begin
  mKeys := TAtlasCommandKeys.Parse('Atlas.FindMethod=16452;Atlas.Outline=49229');
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual('Atlas.FindMethod', mKeys[0].CommandId);
  Assert.AreEqual(cCtrlD, Integer(mKeys[0].Key));
  Assert.AreEqual(cCtrlAltM, Integer(mKeys[1].Key));
  Assert.AreEqual('Atlas.FindMethod=16452;Atlas.Outline=49229', TAtlasCommandKeys.Format(mKeys));
  Assert.AreEqual('', TAtlasCommandKeys.Format(nil), 'leer');
end;

procedure TAtlasCommandKeysTests.ParseDropsInvalidEntries;
var
  mKeys: TArray<TAtlasCommandKey>;
begin
  mKeys := TAtlasCommandKeys.Parse(';=16452;Ohne;A=;B=x;C=0;D=70000;E=-1; Atlas.FindMethod = 16452 ;');
  Assert.AreEqual(1, Integer(Length(mKeys)));
  Assert.AreEqual('Atlas.FindMethod', mKeys[0].CommandId, 'Leerraum am Rand weg');
  Assert.AreEqual(cCtrlD, Integer(mKeys[0].Key));
end;

procedure TAtlasCommandKeysTests.LastEntryWinsIgnoringCase;
var
  mKeys: TArray<TAtlasCommandKey>;
begin
  mKeys := TAtlasCommandKeys.Parse('Atlas.FindMethod=16452;atlas.findmethod=49229');
  Assert.AreEqual(1, Integer(Length(mKeys)));
  Assert.AreEqual(cCtrlAltM, Integer(TAtlasCommandKeys.KeyOf(mKeys, 'ATLAS.FINDMETHOD')));
end;

procedure TAtlasCommandKeysTests.AssignReplacesAndZeroRemoves;
var
  mText: string;
begin
  mText := TAtlasCommandKeys.Assign('', 'Atlas.FindMethod', cCtrlD);
  Assert.AreEqual('Atlas.FindMethod=16452', mText);
  mText := TAtlasCommandKeys.Assign(mText, 'Atlas.Outline', cCtrlAltM);
  Assert.AreEqual('Atlas.FindMethod=16452;Atlas.Outline=49229', mText);
  mText := TAtlasCommandKeys.Assign(mText, 'atlas.findmethod', cCtrlAltM);
  Assert.AreEqual('Atlas.FindMethod=49229;Atlas.Outline=49229', mText, 'ersetzt an derselben Stelle');
  mText := TAtlasCommandKeys.Assign(mText, 'Atlas.FindMethod', 0);
  Assert.AreEqual('Atlas.Outline=49229', mText, 'Taste 0 entfernt');
  Assert.AreEqual(mText, TAtlasCommandKeys.Assign(mText, '  ', cCtrlD), 'ohne Kennung nichts');
end;

procedure TAtlasCommandKeysTests.KeyOfWithoutEntryIsZero;
begin
  Assert.AreEqual(0, Integer(TAtlasCommandKeys.KeyOf(nil, 'Atlas.FindMethod')));
  Assert.AreEqual(0, Integer(TAtlasCommandKeys.KeyOf(TAtlasCommandKeys.Parse('A=1'), 'B')));
end;

procedure TAtlasCommandKeysTests.CaptureNeedsCtrlOrAltExceptFunctionKeys;
const
  cVkControl = $11;
  cVkLShift = $A0;
  cVkF5 = $74;
var
  mKey: Word;
begin
  Assert.IsTrue(TAtlasCommandKeys.Capture(Ord('D'), TAtlasCommandKeys.cScCtrl, mKey));
  Assert.AreEqual(cCtrlD, Integer(mKey));
  Assert.IsTrue(TAtlasCommandKeys.Capture(Ord('M'), TAtlasCommandKeys.cScCtrl or TAtlasCommandKeys.cScAlt, mKey));
  Assert.AreEqual(cCtrlAltM, Integer(mKey));
  Assert.IsTrue(TAtlasCommandKeys.Capture(cVkF5, 0, mKey), 'F5 allein');
  Assert.AreEqual(cVkF5, Integer(mKey));
  Assert.IsFalse(TAtlasCommandKeys.Capture(Ord('D'), 0, mKey), 'Buchstabe allein');
  Assert.AreEqual(0, Integer(mKey));
  Assert.IsFalse(TAtlasCommandKeys.Capture(Ord('D'), TAtlasCommandKeys.cScShift, mKey), 'nur Umschalt');
  Assert.IsFalse(TAtlasCommandKeys.Capture(cVkControl, TAtlasCommandKeys.cScCtrl, mKey), 'Strg allein');
  Assert.IsFalse(TAtlasCommandKeys.Capture(cVkLShift, TAtlasCommandKeys.cScShift, mKey), 'Umschalt links');
  Assert.IsFalse(TAtlasCommandKeys.Capture(0, TAtlasCommandKeys.cScCtrl, mKey), 'keine Taste');
end;

{ TAtlasCommandKeyRowsTests }

function Command(const AId, ACaption: string; AIsAtlas: Boolean): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.IsAtlas := AIsAtlas;
end;

function NoOwner: TFunc<Word, string>;
begin
  Result :=
    function(AKey: Word): string
    begin
      Result := '';
    end;
end;

procedure TAtlasCommandKeyRowsTests.KeylessItemsSkipKeyedAndForeignCommands;
var
  mCommands: TArray<TAtlasCommand>;
  mKeyed, mRows: TArray<TAtlasKeyItem>;
begin
  mCommands := TArray<TAtlasCommand>.Create(Command('Atlas.FindMethod', 'Atlas: Methode suchen …', True),
    Command('Atlas.Outline', 'Gliederung', True), Command('Ide.Other', 'Fremd', False),
    Command(TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.FormatCode), 'Formatieren', True));
  mKeyed := TArray<TAtlasKeyItem>.Create(TAtlasKeyScan.CommandItem(TAtlasCommandKey.Create('Atlas.FindMethod', $4044),
    'Ctrl+D', 'Methode suchen …', False, NoOwner()));
  mRows := TAtlasKeyMap.KeylessItems(mCommands, mKeyed);
  Assert.AreEqual(2, Integer(Length(mRows)), 'ohne den Befehl mit Taste und den fremden');
  Assert.AreEqual('Atlas.Outline', mRows[0].CommandId);
  Assert.AreEqual(0, Integer(mRows[0].ShortCut));
  Assert.IsTrue(mRows[0].Custom, 'ohne eigene Einstellung');
  Assert.IsTrue(mRows[0].Assignable);
  Assert.IsFalse(mRows[1].Custom, 'Formatieren hat keys.format');
  Assert.IsTrue(mRows[1].Func = TAtlasKeyFunction.FormatCode);
  Assert.AreEqual('Methode suchen …', TAtlasKeyMap.CommandCaption(mCommands, 'atlas.findmethod'), 'ohne „Atlas: “');
  Assert.AreEqual('Unbekannt', TAtlasKeyMap.CommandCaption(mCommands, 'Unbekannt'));
end;

procedure TAtlasCommandKeyRowsTests.AssignWritesCustomOrFunctionSetting;
var
  mSettings: TAtlasPluginSettings;
  mItem: TAtlasKeyItem;
  mFunc: TAtlasKeyFunction;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mItem := TAtlasKeyScan.CommandItem(TAtlasCommandKey.Create('Atlas.FindMethod', $4044), 'Ctrl+D',
    'Methode suchen …', False, NoOwner());
  TAtlasKeyMap.Assign(mItem, cCtrlAltM, mSettings);
  Assert.AreEqual('Atlas.FindMethod=' + IntToStr(cCtrlAltM), mSettings.CommandKeys);
  TAtlasKeyMap.Assign(mItem, 0, mSettings);
  Assert.AreEqual('', mSettings.CommandKeys, 'entfernt');
  // Befehl mit eigener Einstellung: dorthin, nicht nach keys.commands.
  Assert.IsTrue(TAtlasKeyMap.FunctionOfCommand(TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.FormatCode), mFunc));
  mItem := Default(TAtlasKeyItem);
  mItem.Origin := TAtlasKeyOrigin.Atlas;
  mItem.Func := mFunc;
  TAtlasKeyMap.Assign(mItem, cCtrlAltM, mSettings);
  Assert.AreEqual(cCtrlAltM, mSettings.FormatCodeKey);
  Assert.AreEqual('', mSettings.CommandKeys);
end;

procedure TAtlasCommandKeyRowsTests.HoldersOfNamesOtherRowsOnly;
var
  mItems: TArray<TAtlasKeyItem>;
  mOwn: TAtlasKeyItem;
begin
  mOwn := TAtlasKeyScan.CommandItem(TAtlasCommandKey.Create('Atlas.FindMethod', $4044), 'Ctrl+D', 'Methode suchen',
    False, NoOwner());
  mItems := TArray<TAtlasKeyItem>.Create(mOwn, TAtlasKeyItem.Create(cCtrlAltM, 'Ctrl+Alt+M', 'Gliederung',
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide, TAtlasKeyMap.cIdeName, TAtlasKeyContext.Global,
    TAtlasKeySource.Action, 'OutlineAction', 1)));
  Assert.AreEqual('', TAtlasKeyMap.HoldersOf(mItems, mOwn, $4044), 'die eigene Zeile zählt nicht');
  Assert.AreEqual('Gliederung (IDE)', TAtlasKeyMap.HoldersOf(mItems, mOwn, cCtrlAltM));
  Assert.AreEqual('', TAtlasKeyMap.HoldersOf(mItems, mOwn, 0), 'keine Taste');
end;

procedure TAtlasCommandKeyRowsTests.CommandItemHoldsFreeKey;
var
  mItem: TAtlasKeyItem;
  mRows: TArray<TAtlasKeyItem>;
  mKeyText: TFunc<Word, string>;
  mTaken: TFunc<Word, string>;
begin
  mItem := TAtlasKeyScan.CommandItem(TAtlasCommandKey.Create('Atlas.FindMethod', $4044), 'Ctrl+D', 'Methode suchen',
    False, NoOwner());
  Assert.IsTrue(mItem.Active, 'frei');
  Assert.IsTrue(mItem.Custom);
  Assert.AreEqual('Atlas.FindMethod', TAtlasKeyScan.UsageIdOf(mItem), 'gezählt beim Palettenbefehl');
  mTaken :=
    function(AKey: Word): string
    begin
      Result := 'Fremd';
    end;
  mItem := TAtlasKeyScan.CommandItem(TAtlasCommandKey.Create('Atlas.FindMethod', $4044), 'Ctrl+D', 'Methode suchen',
    False, mTaken);
  Assert.IsFalse(mItem.Active, 'belegt, ohne Vorrang');
  mKeyText :=
    function(AKey: Word): string
    begin
      Result := IntToStr(AKey);
    end;
  mRows := TAtlasKeyScan.CommandItems('A=16452;B=49229', TArray<TAtlasCommand>.Create(Command('B', 'Atlas: Bee',
    True)), True, mTaken, mKeyText);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('A', mRows[0].Command, 'ohne Palettenbefehl die Kennung');
  Assert.AreEqual('Bee', mRows[1].Command);
  Assert.AreEqual('49229', mRows[1].KeyText);
  Assert.IsTrue(mRows[0].Active and mRows[1].Active, 'mit Vorrang');
end;

procedure TAtlasCommandKeyRowsTests.UnitSearchActionNotAssignable;
var
  mItem: TAtlasKeyItem;
  mFunc: TAtlasKeyFunction;
begin
  mItem := TAtlasKeyScan.UnitSearchItem($407B, 'Ctrl+F12', 'Units', 'Atlas', 3);
  Assert.IsFalse(mItem.Assignable, 'Strg+F12 ist die Aktion der IDE');
  Assert.IsFalse(TAtlasKeyMap.FunctionOfCommand('Unbekannt', mFunc));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommandKeysTests);
  TDUnitX.RegisterTestFixture(TAtlasCommandKeyRowsTests);

end.
