unit Atlas.Core.Commands.Palette.Tests;

// Tests für die Befehlspalette (#502) und ihre Zusatzgruppe (#1270): Zeilen,
// wählbare Zeilen, Schritte über Überschrift und Status, Tasten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommandPaletteTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure FuzzyFindsBuildProject;
    [Test]
    procedure LastExecutedFirst;
    [Test]
    procedure PathHelpsWhenCaptionDoesNot;
    [Test]
    procedure CleansCaptions;
    [Test]
    procedure HistoryRoundTrip;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben (Bericht N3).</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure KeepsListOrderForCodeActions;
    [Test]
    procedure RegistryInterfaceIsUsableWithoutVcl;
    /// <summary>Ohne Gruppe nur Befehle; Gruppe ohne Titel zählt nicht (#1270).</summary>
    [Test]
    procedure RowsWithoutGroup;
    /// <summary>Befehle, Überschrift, Status, Einträge in dieser Reihenfolge (#1270).</summary>
    [Test]
    procedure RowsOfGroup;
    /// <summary>Pfeiltasten überspringen Überschrift und Status; am Rand zurück (#1270).</summary>
    [Test]
    procedure StepSkipsHeaderAndStatus;
    /// <summary>Strg+Enter startet, Umschalt+Enter öffnet im Browser, Enter öffnet (#1270).</summary>
    [Test]
    procedure ActionOfModifiers;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Commands.Palette;

function Command(const AId, ACaption: string; const APath: string = ''): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Path := APath;
end;

function Captions(const ACommands: TArray<TAtlasCommand>; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    Result := Result + ACommands[Index].Caption + '|';
end;

function Sample: TArray<TAtlasCommand>;
begin
  Result := [Command('ProjectBuild', 'Build Project', 'Project'), Command('ProjectCompile', 'Compile Project', 'Project'),
    Command('FileOpen', 'Open', 'File'), Command('Atlas.Options', 'Atlas: Optionen')];
end;

type
  /// <summary>Registry ohne Palette: zählt Anmeldungen und merkt Sichtbarkeit.</summary>
  TFakeRegistry = class(TInterfacedObject, IAtlasCommandRegistry)
  public
    Ids: TArray<string>;
    Conditional: Integer;
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
  end;

procedure TFakeRegistry.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc);
begin
  Ids := Ids + [AId];
end;

procedure TFakeRegistry.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
  const AVisible: TFunc<Boolean>);
begin
  RegisterCommand(AId, ACaption, ADescription, AProc);
  if Assigned(AVisible) and AVisible() then
    Inc(Conditional);
end;

/// <summary>Wie ein Feature, das seine Befehle anmeldet (A-09: nur die Schnittstelle aus dem Core).</summary>
procedure RegisterSample(const ARegistry: IAtlasCommandRegistry);
begin
  ARegistry.RegisterCommand('Atlas.Eins', 'Eins', '',
    procedure
    begin
    end);
  ARegistry.RegisterCommand('Atlas.Zwei', 'Zwei', 'Beschreibung',
    procedure
    begin
    end,
    function: Boolean
    begin
      Result := True;
    end);
end;

procedure TAtlasCommandPaletteTests.WarmUpFirstUse;
begin
  BrokenFileSetAsideLockedFileKept;
end;

procedure TAtlasCommandPaletteTests.FuzzyFindsBuildProject;
var
  Commands: TArray<TAtlasCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Build Project|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'bpj', nil)));
end;

procedure TAtlasCommandPaletteTests.LastExecutedFirst;
var
  Commands: TArray<TAtlasCommand>;
  History: TAtlasCommandHistory;
begin
  Commands := Sample;
  History := TAtlasCommandHistory.Create;
  try
    // Ohne Eingabe alphabetisch, der eben ausgeführte Befehl oben.
    Assert.AreEqual('Atlas: Optionen|Build Project|Compile Project|Open|',
      Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)));
    History.Executed('FileOpen');
    Assert.AreEqual('Open|Atlas: Optionen|Build Project|Compile Project|',
      Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)));
    History.Executed('ProjectCompile');
    Assert.AreEqual('Compile Project|Open|', Copy(Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)), 1, 21));
  finally
    History.Free;
  end;
end;

procedure TAtlasCommandPaletteTests.PathHelpsWhenCaptionDoesNot;
var
  Commands: TArray<TAtlasCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Open|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'file open', nil)));
end;

procedure TAtlasCommandPaletteTests.CleansCaptions;
begin
  Assert.AreEqual('Datei öffnen', TAtlasCommandPalette.CleanCaption('&Datei öffnen...'));
  Assert.AreEqual('Suchen & Ersetzen', TAtlasCommandPalette.CleanCaption('Suchen && &Ersetzen'));
end;

procedure TAtlasCommandPaletteTests.HistoryRoundTrip;
var
  History, Loaded: TAtlasCommandHistory;
  FileName: string;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'atlas-palette-test.json');
  History := TAtlasCommandHistory.Create;
  Loaded := TAtlasCommandHistory.Create;
  try
    History.Executed('A');
    History.Executed('B');
    History.SaveToFile(FileName);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(History.Boost('A'), Loaded.Boost('A'));
    Assert.AreEqual(History.Boost('B'), Loaded.Boost('B'));
    Assert.IsTrue(Loaded.Boost('B') > Loaded.Boost('A'));
  finally
    Loaded.Free;
    History.Free;
    TFile.Delete(FileName);
  end;
end;

procedure TAtlasCommandPaletteTests.KeepsListOrderForCodeActions;
var
  Commands: TArray<TAtlasCommand>;
begin
  // Code-Aktionen (#399): bevorzugte zuerst, so wie der Server sie liefert.
  Commands := [Command('0', 'try/finally ergänzen'), Command('1', 'Befund kopieren'), Command('2', 'Als Konstante')];
  Assert.AreEqual('try/finally ergänzen|Befund kopieren|Als Konstante|',
    Captions(Commands, TAtlasCommandPalette.Order(Commands, '', nil, True)));
  Assert.AreEqual('Als Konstante|Befund kopieren|try/finally ergänzen|',
    Captions(Commands, TAtlasCommandPalette.Order(Commands, '', nil)), 'ohne KeepOrder alphabetisch');
  Assert.AreEqual('Befund kopieren|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'befund', nil, True)));
end;

procedure TAtlasCommandPaletteTests.RegistryInterfaceIsUsableWithoutVcl;
var
  Fake: TFakeRegistry;
  Registry: IAtlasCommandRegistry;
begin
  Fake := TFakeRegistry.Create;
  Registry := Fake;
  RegisterSample(Registry);
  Assert.AreEqual(2, Integer(Length(Fake.Ids)));
  Assert.AreEqual('Atlas.Zwei', Fake.Ids[1]);
  Assert.AreEqual(1, Fake.Conditional);
end;

procedure TAtlasCommandPaletteTests.BrokenFileSetAsideLockedFileKept;
var
  History: TAtlasCommandHistory;
  FileName: string;
  Lock: TFileStream;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'atlas-palette-' + IntToStr(Random(MaxInt)) + '.json');
  History := TAtlasCommandHistory.Create;
  try
    TFile.WriteAllText(FileName, '[1, 2]');
    Assert.IsTrue(History.LoadFromFile(FileName) = TAtlasDataLoad.Renewed);
    Assert.IsTrue(TFile.Exists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
    History.Executed('A');
    Assert.IsTrue(History.SaveToFile(FileName));
    Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(History.LoadFromFile(FileName) = TAtlasDataLoad.Kept);
    finally
      Lock.Free;
    end;
    Assert.AreEqual(0, History.Boost('A'));
    History.Executed('B');
    Assert.IsFalse(History.SaveToFile(FileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(FileName, TEncoding.UTF8), '"A"');
    Assert.DoesNotContain(TFile.ReadAllText(FileName, TEncoding.UTF8), '"B"');
  finally
    History.Free;
    System.SysUtils.DeleteFile(FileName);
    System.SysUtils.DeleteFile(FileName + TAtlasDataFile.DefectExtension);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

function Group(const AStatus: string; ACount: Integer): TAtlasPaletteGroup;
var
  mItems: TArray<TAtlasCommand>;
  mIndex: Integer;
begin
  mItems := nil;
  SetLength(mItems, ACount);
  for mIndex := 0 to ACount - 1 do
    mItems[mIndex] := Command('ATL-' + IntToStr(mIndex + 1), 'Eintrag ' + IntToStr(mIndex + 1));
  Result := TAtlasPaletteGroup.Create('Issues', AStatus, '', mItems);
end;

procedure TAtlasCommandPaletteTests.RowsWithoutGroup;
var
  mRows: TAtlasPaletteRows;
  mIndex: Integer;
begin
  mRows := TAtlasPaletteRows.Create(3, TAtlasPaletteGroup.None);
  Assert.AreEqual(3, mRows.Count);
  Assert.IsTrue(mRows.Kind(2, mIndex) = TAtlasPaletteRowKind.Command);
  Assert.AreEqual(2, mIndex);
  Assert.AreEqual(0, mRows.First);
  // Einträge ohne Titel: keine Gruppe.
  mRows := TAtlasPaletteRows.Create(0, TAtlasPaletteGroup.Create('', 'Status', '', [Command('a', 'A')]));
  Assert.AreEqual(0, mRows.Count);
  Assert.AreEqual(-1, mRows.First);
  Assert.IsFalse(mRows.Selectable(0));
  Assert.AreEqual(-1, TAtlasPaletteRows.Create(-1, TAtlasPaletteGroup.None).First, 'negative Anzahl wie 0');
end;

procedure TAtlasCommandPaletteTests.RowsOfGroup;
var
  mRows: TAtlasPaletteRows;
  mIndex: Integer;
begin
  mRows := TAtlasPaletteRows.Create(2, Group('Suche im Tracker …', 2));
  Assert.AreEqual(6, mRows.Count, '2 Befehle, Überschrift, Status, 2 Einträge');
  Assert.IsTrue(mRows.Kind(1, mIndex) = TAtlasPaletteRowKind.Command);
  Assert.IsTrue(mRows.Kind(2, mIndex) = TAtlasPaletteRowKind.Header);
  Assert.IsTrue(mRows.Kind(3, mIndex) = TAtlasPaletteRowKind.Status);
  Assert.IsTrue(mRows.Kind(4, mIndex) = TAtlasPaletteRowKind.Item);
  Assert.AreEqual(0, mIndex);
  Assert.IsTrue(mRows.Kind(5, mIndex) = TAtlasPaletteRowKind.Item);
  Assert.AreEqual(1, mIndex);
  Assert.IsFalse(mRows.Selectable(2));
  Assert.IsFalse(mRows.Selectable(3));
  Assert.IsTrue(mRows.Selectable(4));
  Assert.IsFalse(mRows.Selectable(6));
  // Ohne Status folgen die Einträge direkt der Überschrift.
  mRows := TAtlasPaletteRows.Create(0, Group('', 1));
  Assert.AreEqual(2, mRows.Count);
  Assert.IsTrue(mRows.Kind(1, mIndex) = TAtlasPaletteRowKind.Item);
  Assert.AreEqual(1, mRows.First, 'ohne Befehle der erste Eintrag');
  // Nur Status ("Suche im Tracker …"): nichts wählbar.
  Assert.AreEqual(-1, TAtlasPaletteRows.Create(0, Group('Suche im Tracker …', 0)).First);
end;

procedure TAtlasCommandPaletteTests.StepSkipsHeaderAndStatus;
var
  mRows: TAtlasPaletteRows;
begin
  mRows := TAtlasPaletteRows.Create(2, Group('Status', 2));
  Assert.AreEqual(4, mRows.Step(1, 1), 'über Überschrift und Status');
  Assert.AreEqual(1, mRows.Step(4, -1), 'zurück zum letzten Befehl');
  Assert.AreEqual(5, mRows.Step(5, 1), 'am Ende bleiben');
  Assert.AreEqual(0, mRows.Step(0, -1), 'am Anfang bleiben');
  Assert.AreEqual(5, mRows.Step(0, 10), 'Bild ab bis zum Ende');
  // Nur Gruppe ohne Befehle: Bild auf endet beim ersten Eintrag, nicht auf der Überschrift.
  mRows := TAtlasPaletteRows.Create(0, Group('Status', 3));
  Assert.AreEqual(2, mRows.Step(4, -10));
  // Nichts wählbar: Auswahl bleibt.
  mRows := TAtlasPaletteRows.Create(0, Group('Status', 0));
  Assert.AreEqual(-1, mRows.Step(-1, 1));
end;

procedure TAtlasCommandPaletteTests.ActionOfModifiers;
begin
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(False, False) = TAtlasPaletteAction.Open);
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(True, False) = TAtlasPaletteAction.Start);
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(False, True) = TAtlasPaletteAction.Browse);
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(True, True) = TAtlasPaletteAction.Start, 'Strg vor Umschalt');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommandPaletteTests);

end.