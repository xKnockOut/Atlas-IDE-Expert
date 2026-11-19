unit Atlas.Core.Debug.WatchStore.Tests;

// Tests für die Ablage der Überwachungsliste mit Bindung an Klasse oder Unit (#2550): Reihenfolge, Grenze,
// Bindung ändern, Dateiformat mit und ohne scope; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasWatchStoreTests = class
  public
    [Test]
    procedure ItemsInOrderOfAdding;
    [Test]
    procedure AddKeepsExistingAndLimit;
    [Test]
    procedure SetScopeAndRemove;
    [Test]
    procedure ProjectsIgnoreCase;
    [Test]
    procedure WritesStringsWithoutScope;
    [Test]
    procedure ReadsOldFileWithoutScope;
    [Test]
    procedure ReadsScopedEntriesAndSkipsJunk;
    [Test]
    procedure BrokenTextIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.WatchScopes,
  Atlas.Core.Debug.WatchStore;

function ExpressionsOf(const AWatches: TAtlasScopedWatches): string;
var
  mWatch: TAtlasScopedWatch;
begin
  Result := '';
  for mWatch in AWatches do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mWatch.Expression;
    if mWatch.Scope.Kind <> TAtlasWatchScopeKind.Everywhere then
    begin
      Result := Result + '@' + mWatch.Scope.ToText;
    end;
  end;
end;

{ TAtlasWatchStoreTests }

procedure TAtlasWatchStoreTests.ItemsInOrderOfAdding;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    Assert.IsTrue(mStore.Add('P', 'A', TAtlasWatchScope.Everywhere));
    Assert.IsTrue(mStore.Add('P', ' B ', TAtlasWatchScope.ForClass('TB')));
    Assert.IsFalse(mStore.Add('P', '', TAtlasWatchScope.Everywhere), 'leer');
    Assert.AreEqual('A,B@class:TB', ExpressionsOf(mStore.Items('P')));
    Assert.AreEqual('', ExpressionsOf(mStore.Items('Q')));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.AddKeepsExistingAndLimit;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(2);
  try
    mStore.Add('P', 'A', TAtlasWatchScope.ForUnit('U'));
    Assert.IsFalse(mStore.Add('P', 'A', TAtlasWatchScope.Everywhere), 'schon da: Bindung bleibt');
    mStore.Add('P', 'B', TAtlasWatchScope.Everywhere);
    mStore.Add('P', 'C', TAtlasWatchScope.Everywhere);
    Assert.AreEqual('B,C', ExpressionsOf(mStore.Items('P')), 'der älteste fällt weg');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.SetScopeAndRemove;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    mStore.Add('P', 'A', TAtlasWatchScope.Everywhere);
    mStore.Add('P', 'B', TAtlasWatchScope.Everywhere);
    Assert.IsTrue(mStore.SetScope('P', 'A', TAtlasWatchScope.ForClass('TA')));
    Assert.IsFalse(mStore.SetScope('P', 'A', TAtlasWatchScope.ForClass('ta')), 'unverändert');
    Assert.IsFalse(mStore.SetScope('P', 'X', TAtlasWatchScope.ForClass('TA')), 'gibt es nicht');
    Assert.AreEqual('A@class:TA,B', ExpressionsOf(mStore.Items('P')));
    Assert.IsTrue(mStore.Remove('P', 'A'));
    Assert.IsFalse(mStore.Remove('P', 'A'));
    Assert.AreEqual('B', ExpressionsOf(mStore.Items('P')));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.ProjectsIgnoreCase;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    mStore.Add('C:\P\Haupt.dproj', 'A', TAtlasWatchScope.Everywhere);
    Assert.AreEqual('A', ExpressionsOf(mStore.Items('c:\p\HAUPT.dproj')));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.WritesStringsWithoutScope;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    mStore.Add('p', 'Now', TAtlasWatchScope.Everywhere);
    mStore.Add('p', 'FFilter', TAtlasWatchScope.ForClass('TAuftragsLauf'));
    // Jüngster zuerst wie bisher.
    Assert.AreEqual('{"projects":{"p":[{"expression":"FFilter","scope":"class:TAuftragsLauf"},"Now"]}}',
      mStore.ToText);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.ReadsOldFileWithoutScope;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    Assert.IsTrue(mStore.LoadFromText('{"projects":{"p":["B","A"]}}'));
    Assert.AreEqual('A,B', ExpressionsOf(mStore.Items('p')), 'alle gelten überall');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.ReadsScopedEntriesAndSkipsJunk;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    Assert.IsTrue(mStore.LoadFromText('{"projects":{"p":[{"expression":"F","scope":"unit:Auftrag.Lauf"},' +
      '{"expression":"G","scope":"irgendwas"},{"scope":"class:TA"},12,"F","",null],"q":"kaputt"}}'));
    Assert.AreEqual('G,F@unit:Auftrag.Lauf', ExpressionsOf(mStore.Items('p')));
    Assert.AreEqual('', ExpressionsOf(mStore.Items('q')));
    // Unverändert wieder geschrieben: Die Datei ändert sich nur mit der Liste.
    Assert.AreEqual('{"projects":{"p":[{"expression":"F","scope":"unit:Auftrag.Lauf"},"G"]}}', mStore.ToText);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasWatchStoreTests.BrokenTextIsEmpty;
var
  mStore: TAtlasWatchStore;
begin
  mStore := TAtlasWatchStore.Create(10);
  try
    mStore.Add('p', 'A', TAtlasWatchScope.Everywhere);
    Assert.IsFalse(mStore.LoadFromText('{kaputt'));
    Assert.IsFalse(mStore.LoadFromText('[]'));
    Assert.AreEqual('', ExpressionsOf(mStore.Items('p')));
  finally
    mStore.Free;
  end;
end;

end.
