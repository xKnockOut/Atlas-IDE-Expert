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
  Value: string;
begin
  Value := '0';
  if AType = 'boolean' then
    Value := 'true';
  if AType = 'string' then
    Value := '""';
  Result := Format('"%s":{"type":"%s","default":%s,"x-key":"%s","x-area":"general","x-page":"Allgemein"%s}',
    [AName, AType, Value, AKey, AExtra]);
end;

function Schema(const AProps: array of string): string;
begin
  Result := '{"x-areas":{"general":{"caption":"Allgemein"}},' +
    '"x-nodes":{"n1":{"caption":"Eins","captionEn":"One"},"n2":{"caption":"Zwei"}},' +
    '"properties":{' + string.Join(',', AProps) + '}}';
end;

function Groups(const AProps: array of string): TAtlasSettingsGroups;
var
  Catalog: TAtlasSettingsCatalog;
begin
  Catalog := TAtlasSettingsCatalog.Create(Schema(AProps), '{}');
  try
    Result := TAtlasSettingsGroups.Create(Catalog);
  finally
    Catalog.Free;
  end;
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(',', AItems);
end;

procedure TAtlasSettingsGroupsTests.PrefixRuleFindsSwitchOrEnabled;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('B', 'a.b', 'boolean', ''),
    Prop('C', 'a.b.c', 'integer', ''), Prop('X', 'a.x', 'integer', ''), Prop('Z', 'z', 'integer', ''),
    Prop('BC', 'a.bc', 'integer', '')]);
  try
    Assert.AreEqual('B', Subject.ParentOf('C'), 'längstes Präfix mit Schalter');
    Assert.AreEqual('A', Subject.ParentOf('B'), 'Präfix + .enabled');
    Assert.AreEqual('A', Subject.ParentOf('X'));
    Assert.AreEqual('', Subject.ParentOf('A'), 'nie die Einstellung selbst');
    Assert.AreEqual('', Subject.ParentOf('Z'));
    Assert.AreEqual('A', Subject.ParentOf('BC'), 'nur ganze Glieder: a.bc gehört nicht zu a.b');
    Assert.AreEqual('B,A', Joined(Subject.AncestorsOf('C')));
    Assert.AreEqual('B,X,BC', Joined(Subject.ChildrenOf('A')));
    Assert.AreEqual(0, Integer(Length(Subject.Issues)));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.PrefixRuleSkipsNonBoolean;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('Mode', 'a.mode', 'string', ''),
    Prop('Scope', 'a.mode.scope', 'string', '')]);
  try
    Assert.AreEqual('A', Subject.ParentOf('Scope'), 'a.mode ist kein Schalter');
    Assert.AreEqual('A', Subject.ParentOf('Mode'));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ExplicitParentWins;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('Other', 'other', 'boolean', ''),
    Prop('X', 'a.x', 'integer', ',"x-parent":"other"'), Prop('Y', 'a.y', 'integer', ',"x-parent":""'),
    Prop('Key', 'keys.a', 'integer', ',"x-parent":"a.enabled"')]);
  try
    Assert.AreEqual('Other', Subject.ParentOf('X'));
    Assert.AreEqual('', Subject.ParentOf('Y'), '"" hebt die Präfixregel auf');
    Assert.AreEqual('A', Subject.ParentOf('Key'));
    Assert.AreEqual(0, Integer(Length(Subject.Issues)));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.NodeExplicitAndInherited;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''),
    Prop('B', 'a.b', 'boolean', ',"x-node":"n1"'), Prop('C', 'a.b.c', 'integer', ''),
    Prop('D', 'a.b.d', 'integer', ',"x-node":""'), Prop('E', 'a.b.e', 'integer', ',"x-node":"n2"'),
    Prop('F', 'a.f', 'integer', '')]);
  try
    Assert.AreEqual('', Subject.NodeOf('A'), 'ohne x-node: Hauptknoten');
    Assert.AreEqual('n1', Subject.NodeOf('B'));
    Assert.AreEqual('n1', Subject.NodeOf('C'), 'erbt vom Hauptschalter');
    Assert.AreEqual('', Subject.NodeOf('D'), '"" = ausdrücklich Hauptknoten');
    Assert.AreEqual('n2', Subject.NodeOf('E'));
    Assert.AreEqual('', Subject.NodeOf('F'));
    Assert.AreEqual('B,C', Joined(Subject.NamesOfNode('n1')));
    Assert.AreEqual('A,D,F', Joined(Subject.NamesOfNode('')));
    Assert.AreEqual('Eins', Subject.NodeCaption('n1', False));
    Assert.AreEqual('One', Subject.NodeCaption('n1', True));
    Assert.AreEqual('Zwei', Subject.NodeCaption('n2', True), 'ohne captionEn die deutsche');
    Assert.AreEqual(2, Integer(Length(Subject.Nodes)));
    Assert.IsTrue(Subject.HasNode('N1'));
    Assert.IsFalse(Subject.HasNode('n3'));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsUnknownAndNonBooleanParent;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('N', 'n', 'integer', ''),
    Prop('X', 'a.x', 'integer', ',"x-parent":"gibt.es.nicht"'), Prop('Y', 'a.y', 'integer', ',"x-parent":"n"')]);
  try
    Assert.AreEqual(2, Integer(Length(Subject.Issues)));
    Assert.IsTrue(Subject.Issues[0].Contains('a.x') and Subject.Issues[0].Contains('unbekannt'), Subject.Issues[0]);
    Assert.IsTrue(Subject.Issues[1].Contains('a.y') and Subject.Issues[1].Contains('nicht boolesch'),
      Subject.Issues[1]);
    Assert.AreEqual('', Subject.ParentOf('X'), 'fehlerhafte Angabe gilt als kein Hauptschalter');
    Assert.AreEqual('', Subject.ParentOf('Y'));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsUnknownNode;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a', 'boolean', ',"x-node":"n9"')]);
  try
    Assert.AreEqual(1, Integer(Length(Subject.Issues)));
    Assert.IsTrue(Subject.Issues[0].Contains('n9'), Subject.Issues[0]);
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.ReportsAndCutsCycle;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a', 'boolean', ',"x-parent":"b"'), Prop('B', 'b', 'boolean', ',"x-parent":"a"'),
    Prop('C', 'c', 'boolean', ',"x-parent":"c"')]);
  try
    Assert.AreEqual(2, Integer(Length(Subject.Issues)), string.Join(' | ', Subject.Issues));
    Assert.IsTrue(Subject.Issues[0].Contains('Zyklus') and Subject.Issues[0].Contains('a → b → a'),
      Subject.Issues[0]);
    Assert.IsTrue(Subject.Issues[1].Contains('c → c'), Subject.Issues[1]);
    // Nach dem Kappen endet jede Kette.
    Assert.AreEqual('', Subject.ParentOf('A'));
    Assert.AreEqual('A', Subject.ParentOf('B'));
    Assert.AreEqual('', Subject.ParentOf('C'));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.MastersHaveFrames;
var
  Subject: TAtlasSettingsGroups;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('X', 'a.x', 'integer', ''),
    Prop('Head', 'head', 'boolean', ',"x-node":"n1"'), Prop('Exp', 'exp', 'boolean', ',"x-experimental":true'),
    Prop('Plain', 'plain', 'boolean', ''), Prop('Choice', 'choice', 'string', ',"x-node":"n2"')]);
  try
    Assert.IsTrue(Subject.IsMaster('A'), 'mit Unteroptionen');
    Assert.IsTrue(Subject.IsMaster('Head'), 'Kopf eines Unterpunkts, auch ohne Unteroptionen');
    Assert.IsTrue(Subject.IsMaster('Exp'), 'experimentell: Rahmen mit Grund');
    Assert.IsFalse(Subject.IsMaster('Plain'));
    Assert.IsFalse(Subject.IsMaster('X'));
    Assert.IsFalse(Subject.IsMaster('Choice'), 'nur boolesche Einstellungen');
    Assert.IsFalse(Subject.IsMaster('GibtEsNicht'));
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.LockFollowsOutermostOffMaster;
var
  Subject: TAtlasSettingsGroups;
  Off: TList<string>;
  IsOn: TAtlasSettingIsOn;
  Lock: TAtlasSettingsLock;
begin
  Subject := Groups([Prop('A', 'a.enabled', 'boolean', ''), Prop('B', 'a.b', 'boolean', ''),
    Prop('C', 'a.b.c', 'integer', '')]);
  Off := TList<string>.Create;
  try
    IsOn :=
      function(const AName: string): Boolean
      begin
        Result := not Off.Contains(AName);
      end;
    Assert.IsFalse(Subject.LockOf('C', IsOn, True).Locked, 'alles an');
    Off.Add('B');
    Lock := Subject.LockOf('C', IsOn, True);
    Assert.IsTrue(Lock.Reason = lrMasterOff);
    Assert.AreEqual('B', Lock.Master);
    Assert.IsFalse(Subject.LockOf('B', IsOn, True).Locked, 'der Hauptschalter selbst bleibt bedienbar');
    Off.Add('A');
    Lock := Subject.LockOf('C', IsOn, True);
    Assert.AreEqual('A', Lock.Master, 'der äußerste ausgeschaltete Hauptschalter');
    Assert.AreEqual('A', Subject.LockOf('B', IsOn, True).Master, 'verschachtelte Gruppe mit gesperrt');
    Off.Remove('B');
    Assert.AreEqual('A', Subject.LockOf('C', IsOn, True).Master);
    Assert.IsFalse(Subject.LockOf('GibtEsNicht', IsOn, True).Locked);
  finally
    Off.Free;
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.LockForExperimental;
var
  Subject: TAtlasSettingsGroups;
  IsOn: TAtlasSettingIsOn;
  Lock: TAtlasSettingsLock;
begin
  Subject := Groups([Prop('ExperimentalEnabled', 'experimental.enabled', 'boolean', ''),
    Prop('Exp', 'exp', 'boolean', ',"x-experimental":true'), Prop('ExpWidth', 'exp.width', 'integer', ''),
    Prop('Plain', 'plain', 'boolean', '')]);
  try
    IsOn :=
      function(const AName: string): Boolean
      begin
        Result := True;
      end;
    Lock := Subject.LockOf('Exp', IsOn, False);
    Assert.IsTrue(Lock.Reason = lrExperimental, 'auch der Hauptschalter der Funktion');
    Assert.AreEqual(TAtlasExperimental.MasterName, Lock.Master);
    Assert.IsTrue(Subject.LockOf('ExpWidth', IsOn, False).Reason = lrExperimental, 'Unteroption mit gesperrt');
    Assert.IsTrue(Subject.IsExperimental('ExpWidth'));
    Assert.IsFalse(Subject.LockOf('Plain', IsOn, False).Locked);
    Assert.IsFalse(Subject.LockOf('ExperimentalEnabled', IsOn, False).Locked, 'der Hauptschalter nie');
    Assert.IsFalse(Subject.LockOf('Exp', IsOn, True).Locked, 'mit experimental.enabled frei');
    IsOn :=
      function(const AName: string): Boolean
      begin
        Result := AName <> 'Exp';
      end;
    Assert.IsTrue(Subject.LockOf('ExpWidth', IsOn, False).Reason = lrExperimental, 'experimentell geht vor');
    Assert.IsTrue(Subject.LockOf('ExpWidth', IsOn, True).Reason = lrMasterOff);
  finally
    Subject.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.RealCatalogMapsEveryKey;
var
  Catalog: TAtlasSettingsCatalog;
  Subject: TAtlasSettingsGroups;
  Name, Parent, Node: string;
  Index, Found: Integer;
  Used: TDictionary<string, Integer>;
  Entry: TAtlasCatalogEntry;
begin
  // Wächter (#890): jede Plugin-Einstellung genau ein Unterpunkt und höchstens ein boolescher Hauptschalter.
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  Subject := TAtlasSettingsGroups.Create(Catalog);
  Used := TDictionary<string, Integer>.Create;
  try
    Assert.AreEqual('', string.Join(' | ', Subject.Issues), 'Schema ohne Fehler');
    for Name in Subject.Names do
    begin
      Node := Subject.NodeOf(Name);
      Assert.IsTrue((Node = '') or Subject.HasNode(Node), Name + ': ' + Node);
      Used.AddOrSetValue(LowerCase(Node), 0);
      Found := 0;
      for Index := 0 to High(Subject.Nodes) do
        if SameText(Subject.NodeOf(Name), Subject.Nodes[Index].Id) then
          Inc(Found);
      if Node <> '' then
        Assert.AreEqual(1, Found, Name);
      Parent := Subject.ParentOf(Name);
      if Parent <> '' then
      begin
        Index := Catalog.IndexOfName(Parent);
        Assert.IsTrue(Index >= 0, Name + ' → ' + Parent);
        Entry := Catalog[Index];
        Assert.IsTrue(Entry.Kind = akBoolean, Name + ' → ' + Parent);
      end;
    end;
    for Index := 0 to High(Subject.Nodes) do
      Assert.IsTrue(Used.ContainsKey(LowerCase(Subject.Nodes[Index].Id)), 'Unterpunkt ohne Einstellung: ' +
        Subject.Nodes[Index].Id);
  finally
    Used.Free;
    Subject.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsGroupsTests.RealCatalogKnownGroups;
var
  Catalog: TAtlasSettingsCatalog;
  Subject: TAtlasSettingsGroups;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  Subject := TAtlasSettingsGroups.Create(Catalog);
  try
    // Präfixregel.
    Assert.AreEqual('Minimap', Subject.ParentOf('MinimapWidth'));
    Assert.AreEqual('WelcomePageSearch', Subject.ParentOf('WelcomePageSearchKey'));
    Assert.AreEqual('WelcomePage', Subject.ParentOf('WelcomePageSearch'));
    // x-parent: Abhängigkeit vom Atlas-Hauptschalter und Tasten unter ihrer Funktion.
    Assert.AreEqual('Enabled', Subject.ParentOf('HoverTooltip'));
    Assert.AreEqual('Enabled', Subject.ParentOf('PairColors'));
    Assert.AreEqual('PairColors', Subject.ParentOf('PairGuides'));
    Assert.AreEqual('MultiCursor', Subject.ParentOf('MultiCursorNextKey'));
    Assert.AreEqual('', Subject.ParentOf('MetricsReport'), 'Metrikbericht hängt nicht an den Kennzahlen');
    // Unterpunkte.
    Assert.AreEqual('editor.minimap', Subject.NodeOf('Minimap'));
    Assert.AreEqual('editor.minimap', Subject.NodeOf('MinimapWidth'));
    Assert.AreEqual('', Subject.NodeOf('PairColorsLight'), 'Reiter Farben: Hauptknoten');
    Assert.IsTrue(Subject.IsMaster('Minimap'));
    Assert.IsTrue(Subject.IsExperimental('MinimapWidth'));
  finally
    Subject.Free;
    Catalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsGroupsTests);

end.
