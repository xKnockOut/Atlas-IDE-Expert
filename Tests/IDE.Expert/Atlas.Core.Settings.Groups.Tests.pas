unit Atlas.Core.Settings.Groups.Tests;

// Gruppen und Sperren der Optionsseite (#890): Präfixregel, x-parent, x-node,
// Zyklen und unbekannte Angaben, Sperrgründe, dazu ein Wächter über den echten
// Plugin-Katalog (jede Einstellung genau ein Unterpunkt, Hauptschalter
// boolesch und bekannt, keine Schemafehler).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsGroupsTests = class
  public
    [Test]
    procedure PrefixRuleFindsSwitchOrEnabled;
    [Test]
    procedure PrefixRuleSkipsNonBoolean;
    [Test]
    procedure ExplicitParentWins;
    [Test]
    procedure NodeExplicitAndInherited;
    [Test]
    procedure ReportsUnknownAndNonBooleanParent;
    [Test]
    procedure ReportsUnknownNode;
    [Test]
    procedure ReportsAndCutsCycle;
    [Test]
    procedure MastersHaveFrames;
    [Test]
    procedure LockFollowsOutermostOffMaster;
    [Test]
    procedure LockForExperimental;
    [Test]
    procedure RealCatalogMapsEveryKey;
    [Test]
    procedure RealCatalogKnownGroups;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Settings.Groups;

/// <summary>Eine Plugin-Einstellung als JSON; AExtra hängt weitere Angaben an (mit führendem Komma).</summary>
function Prop(const AName, AKey, AType, AExtra: string): string;
var
  mValue: string;
begin
  mValue := '0';
  if AType = 'boolean' then
  begin
    mValue := 'true';
  end;
  if AType = 'string' then
  begin
    mValue := '""';
  end;
  Result := Format('"%s":{"type":"%s","default":%s,"x-key":"%s","x-area":"general","x-page":"Allgemein"%s}',
    [AName, AType, mValue, AKey, AExtra]);
end;

function Schema(const AProps: array of string): string;
begin
  Result := '{"x-areas":{"general":{"caption":"Allgemein"}},' +
    '"x-nodes":{"n1":{"caption":"Eins","captionEn":"One"},"n2":{"caption":"Zwei"}},' +
    '"properties":{' + string.Join(',', AProps) + '}}';
end;

function Groups(const AProps: array of string): TAtlasSettingsGroups;
var
  mCatalog: TAtlasSettingsCatalog;
begin
  mCatalog := TAtlasSettingsCatalog.Create(Schema(AProps), '{}');
  try
    Result := TAtlasSettingsGroups.Create(mCatalog);
  finally
    mCatalog.Free;
  end;
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(',', AItems);
end;

procedure TAtlasSettingsGroupsTests.PrefixRuleFindsSwitchOrEnabled;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('B', 'a.b', 'boolean', ''),
    Prop('C', 'a.b.c', 'integer', ''), Prop('X', 'a.x', 'integer', ''), Prop('Z', 'z', 'integer', ''),
    Prop('BC', 'a.bc', 'integer', '')]);
  try
    Assert.AreEqual('B', mSubject.ParentOf('C'), 'längstes Präfix mit Schalter');
    Assert.AreEqual('A', mSubject.ParentOf('B'), 'Präfix + .enabled');
    Assert.AreEqual('A', mSubject.ParentOf('X'));
    Assert.AreEqual('', mSubject.ParentOf('A'), 'nie die Einstellung selbst');
    Assert.AreEqual('', mSubject.ParentOf('Z'));
    Assert.AreEqual('A', mSubject.ParentOf('BC'), 'nur ganze Glieder: a.bc gehört nicht zu a.b');
    Assert.AreEqual('B,A', Joined(mSubject.AncestorsOf('C')));
    Assert.AreEqual('B,X,BC', Joined(mSubject.ChildrenOf('A')));
    Assert.AreEqual(0, Integer(Length(mSubject.Issues)));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.PrefixRuleSkipsNonBoolean;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('Mode', 'a.mode', 'string', ''),
    Prop('Scope', 'a.mode.scope', 'string', '')]);
  try
    Assert.AreEqual('A', mSubject.ParentOf('Scope'), 'a.mode ist kein Schalter');
    Assert.AreEqual('A', mSubject.ParentOf('Mode'));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ExplicitParentWins;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('Other', 'other', 'boolean', ''),
    Prop('X', 'a.x', 'integer', ',"x-parent":"other"'), Prop('Y', 'a.y', 'integer', ',"x-parent":""'),
    Prop('Key', 'keys.a', 'integer', ',"x-parent":"a.enabled"')]);
  try
    Assert.AreEqual('Other', mSubject.ParentOf('X'));
    Assert.AreEqual('', mSubject.ParentOf('Y'), '"" hebt die Präfixregel auf');
    Assert.AreEqual('A', mSubject.ParentOf('Key'));
    Assert.AreEqual(0, Integer(Length(mSubject.Issues)));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.NodeExplicitAndInherited;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''),
    Prop('B', 'a.b', 'boolean', ',"x-node":"n1"'), Prop('C', 'a.b.c', 'integer', ''),
    Prop('D', 'a.b.d', 'integer', ',"x-node":""'), Prop('E', 'a.b.e', 'integer', ',"x-node":"n2"'),
    Prop('F', 'a.f', 'integer', '')]);
  try
    Assert.AreEqual('', mSubject.NodeOf('A'), 'ohne x-node: Hauptknoten');
    Assert.AreEqual('n1', mSubject.NodeOf('B'));
    Assert.AreEqual('n1', mSubject.NodeOf('C'), 'erbt vom Hauptschalter');
    Assert.AreEqual('', mSubject.NodeOf('D'), '"" = ausdrücklich Hauptknoten');
    Assert.AreEqual('n2', mSubject.NodeOf('E'));
    Assert.AreEqual('', mSubject.NodeOf('F'));
    Assert.AreEqual('B,C', Joined(mSubject.NamesOfNode('n1')));
    Assert.AreEqual('A,D,F', Joined(mSubject.NamesOfNode('')));
    Assert.AreEqual('Eins', mSubject.NodeCaption('n1', False));
    Assert.AreEqual('One', mSubject.NodeCaption('n1', True));
    Assert.AreEqual('Zwei', mSubject.NodeCaption('n2', True), 'ohne captionEn die deutsche');
    Assert.AreEqual(2, Integer(Length(mSubject.Nodes)));
    Assert.IsTrue(mSubject.HasNode('N1'));
    Assert.IsFalse(mSubject.HasNode('n3'));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsUnknownAndNonBooleanParent;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('N', 'n', 'integer', ''),
    Prop('X', 'a.x', 'integer', ',"x-parent":"gibt.es.nicht"'), Prop('Y', 'a.y', 'integer', ',"x-parent":"n"')]);
  try
    Assert.AreEqual(2, Integer(Length(mSubject.Issues)));
    Assert.IsTrue(mSubject.Issues[0].Contains('a.x') and mSubject.Issues[0].Contains('unbekannt'), mSubject.Issues[0]);
    Assert.IsTrue(mSubject.Issues[1].Contains('a.y') and mSubject.Issues[1].Contains('nicht boolesch'),
      mSubject.Issues[1]);
    Assert.AreEqual('', mSubject.ParentOf('X'), 'fehlerhafte Angabe gilt als kein Hauptschalter');
    Assert.AreEqual('', mSubject.ParentOf('Y'));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsUnknownNode;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a', 'boolean', ',"x-node":"n9"')]);
  try
    Assert.AreEqual(1, Integer(Length(mSubject.Issues)));
    Assert.IsTrue(mSubject.Issues[0].Contains('n9'), mSubject.Issues[0]);
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsAndCutsCycle;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a', 'boolean', ',"x-parent":"b"'), Prop('B', 'b', 'boolean', ',"x-parent":"a"'),
    Prop('C', 'c', 'boolean', ',"x-parent":"c"')]);
  try
    Assert.AreEqual(2, Integer(Length(mSubject.Issues)), string.Join(' | ', mSubject.Issues));
    Assert.IsTrue(mSubject.Issues[0].Contains('Zyklus') and mSubject.Issues[0].Contains('a → b → a'),
      mSubject.Issues[0]);
    Assert.IsTrue(mSubject.Issues[1].Contains('c → c'), mSubject.Issues[1]);
    // Nach dem Kappen endet jede Kette.
    Assert.AreEqual('', mSubject.ParentOf('A'));
    Assert.AreEqual('A', mSubject.ParentOf('B'));
    Assert.AreEqual('', mSubject.ParentOf('C'));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.MastersHaveFrames;
var
  mSubject: TAtlasSettingsGroups;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('X', 'a.x', 'integer', ''),
    Prop('Head', 'head', 'boolean', ',"x-node":"n1"'), Prop('Exp', 'exp', 'boolean', ',"x-experimental":true'),
    Prop('Plain', 'plain', 'boolean', ''), Prop('Choice', 'choice', 'string', ',"x-node":"n2"')]);
  try
    Assert.IsTrue(mSubject.IsMaster('A'), 'mit Unteroptionen');
    Assert.IsTrue(mSubject.IsMaster('Head'), 'Kopf eines Unterpunkts, auch ohne Unteroptionen');
    Assert.IsTrue(mSubject.IsMaster('Exp'), 'experimentell: Rahmen mit Grund');
    Assert.IsFalse(mSubject.IsMaster('Plain'));
    Assert.IsFalse(mSubject.IsMaster('X'));
    Assert.IsFalse(mSubject.IsMaster('Choice'), 'nur boolesche Einstellungen');
    Assert.IsFalse(mSubject.IsMaster('GibtEsNicht'));
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.LockFollowsOutermostOffMaster;
var
  mSubject: TAtlasSettingsGroups;
  mOff: TList<string>;
  mIsOn: TAtlasSettingIsOn;
  mLock: TAtlasSettingsLock;
begin
  mSubject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('B', 'a.b', 'boolean', ''),
    Prop('C', 'a.b.c', 'integer', '')]);
  mOff := TList<string>.Create;
  try
    mIsOn :=
      function(const AName: string): Boolean
      begin
        Result := not mOff.Contains(AName);
      end;
    Assert.IsFalse(mSubject.LockOf('C', mIsOn, True).Locked, 'alles an');
    mOff.Add('B');
    mLock := mSubject.LockOf('C', mIsOn, True);
    Assert.AreEqual<TAtlasLockReason>(lrMasterOff, mLock.Reason);
    Assert.AreEqual('B', mLock.Master);
    Assert.IsFalse(mSubject.LockOf('B', mIsOn, True).Locked, 'der Hauptschalter selbst bleibt bedienbar');
    mOff.Add('A');
    mLock := mSubject.LockOf('C', mIsOn, True);
    Assert.AreEqual('A', mLock.Master, 'der äußerste ausgeschaltete Hauptschalter');
    Assert.AreEqual('A', mSubject.LockOf('B', mIsOn, True).Master, 'verschachtelte Gruppe mit gesperrt');
    mOff.Remove('B');
    Assert.AreEqual('A', mSubject.LockOf('C', mIsOn, True).Master);
    Assert.IsFalse(mSubject.LockOf('GibtEsNicht', mIsOn, True).Locked);
  finally
    mOff.Free;
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.LockForExperimental;
var
  mSubject: TAtlasSettingsGroups;
  mIsOn: TAtlasSettingIsOn;
  mLock: TAtlasSettingsLock;
begin
  mSubject := Groups([Prop('ExperimentalEnabled', 'experimental.enabled', 'boolean', ''),
    Prop('Exp', 'exp', 'boolean', ',"x-experimental":true'), Prop('ExpWidth', 'exp.width', 'integer', ''),
    Prop('Plain', 'plain', 'boolean', '')]);
  try
    mIsOn :=
      function(const AName: string): Boolean
      begin
        Result := True;
      end;
    mLock := mSubject.LockOf('Exp', mIsOn, False);
    Assert.AreEqual<TAtlasLockReason>(lrExperimental, mLock.Reason, 'auch der Hauptschalter der Funktion');
    Assert.AreEqual(TAtlasExperimental.cMasterName, mLock.Master);
    Assert.AreEqual<TAtlasLockReason>(lrExperimental,
      mSubject.LockOf('ExpWidth', mIsOn, False).Reason, 'Unteroption mit gesperrt');
    Assert.IsTrue(mSubject.IsExperimental('ExpWidth'));
    Assert.IsFalse(mSubject.LockOf('Plain', mIsOn, False).Locked);
    Assert.IsFalse(mSubject.LockOf('ExperimentalEnabled', mIsOn, False).Locked, 'der Hauptschalter nie');
    Assert.IsFalse(mSubject.LockOf('Exp', mIsOn, True).Locked, 'mit experimental.enabled frei');
    mIsOn :=
      function(const AName: string): Boolean
      begin
        Result := AName <> 'Exp';
      end;
    Assert.AreEqual<TAtlasLockReason>(lrExperimental,
      mSubject.LockOf('ExpWidth', mIsOn, False).Reason, 'experimentell geht vor');
    Assert.AreEqual<TAtlasLockReason>(lrMasterOff, mSubject.LockOf('ExpWidth', mIsOn, True).Reason);
  finally
    mSubject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.RealCatalogMapsEveryKey;
var
  mCatalog: TAtlasSettingsCatalog;
  mSubject: TAtlasSettingsGroups;
  mName, mParent, mNode: string;
  mIndex, mFound: Integer;
  mUsed: TDictionary<string, Integer>;
  mEntry: TAtlasCatalogEntry;
begin
  // Wächter (#890): jede Plugin-Einstellung genau ein Unterpunkt und höchstens ein boolescher Hauptschalter.
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mSubject := TAtlasSettingsGroups.Create(mCatalog);
  mUsed := TDictionary<string, Integer>.Create;
  try
    Assert.AreEqual('', string.Join(' | ', mSubject.Issues), 'Schema ohne Fehler');
    for mName in mSubject.Names do
    begin
      mNode := mSubject.NodeOf(mName);
      Assert.IsTrue((mNode = '') or mSubject.HasNode(mNode), mName + ': ' + mNode);
      mUsed.AddOrSetValue(LowerCase(mNode), 0);
      mFound := 0;
      for mIndex := 0 to High(mSubject.Nodes) do
      begin
        if SameText(mSubject.NodeOf(mName), mSubject.Nodes[mIndex].Id) then
        begin
          Inc(mFound);
        end;
      end;
      if mNode <> '' then
      begin
        Assert.AreEqual(1, mFound, mName);
      end;
      mParent := mSubject.ParentOf(mName);
      if mParent <> '' then
      begin
        mIndex := mCatalog.IndexOfName(mParent);
        Assert.IsTrue(mIndex >= 0, mName + ' → ' + mParent);
        mEntry := mCatalog[mIndex];
        Assert.AreEqual<TAtlasSettingKind>(akBoolean, mEntry.Kind, mName + ' → ' + mParent);
      end;
    end;
    for mIndex := 0 to High(mSubject.Nodes) do
    begin
      Assert.IsTrue(mUsed.ContainsKey(LowerCase(mSubject.Nodes[mIndex].Id)), 'Unterpunkt ohne Einstellung: ' +
        mSubject.Nodes[mIndex].Id);
    end;
  finally
    mUsed.Free;
    mSubject.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.RealCatalogKnownGroups;
var
  mCatalog: TAtlasSettingsCatalog;
  mSubject: TAtlasSettingsGroups;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mSubject := TAtlasSettingsGroups.Create(mCatalog);
  try
    // Präfixregel.
    Assert.AreEqual('Minimap', mSubject.ParentOf('MinimapWidth'));
    Assert.AreEqual('WelcomePageSearch', mSubject.ParentOf('WelcomePageSearchKey'));
    Assert.AreEqual('WelcomePage', mSubject.ParentOf('WelcomePageSearch'));
    // x-parent: Abhängigkeit vom Atlas-Hauptschalter und Tasten unter ihrer Funktion.
    Assert.AreEqual('Enabled', mSubject.ParentOf('HoverTooltip'));
    Assert.AreEqual('Enabled', mSubject.ParentOf('PairColors'));
    Assert.AreEqual('PairColors', mSubject.ParentOf('PairGuides'));
    Assert.AreEqual('MultiCursor', mSubject.ParentOf('MultiCursorNextKey'));
    Assert.AreEqual('', mSubject.ParentOf('MetricsReport'), 'Metrikbericht hängt nicht an den Kennzahlen');
    // Unterpunkte.
    Assert.AreEqual('editor.minimap', mSubject.NodeOf('Minimap'));
    Assert.AreEqual('editor.minimap', mSubject.NodeOf('MinimapWidth'));
    Assert.AreEqual('', mSubject.NodeOf('PairColorsLight'), 'Reiter Farben: Hauptknoten');
    Assert.IsTrue(mSubject.IsMaster('Minimap'));
    Assert.IsTrue(mSubject.IsExperimental('MinimapWidth'));
  finally
    mSubject.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsGroupsTests);

end.
