unit Atlas.Core.Debug.BreakpointSets.Tests;

// Tests für Haltepunkt-Sätze (#586) ohne IDE: Namen und Ablage, Speichern und
// Laden (Pfade relativ zum Projektordner, Eigenschaften), Wiederfinden der
// Zeile nach eingefügten Zeilen, Zusammenführen, Branch, Plan für Wechseln
// und Hinzufügen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.BreakpointSets;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointSetsTests = class
  private
    FFolder: string;
    FText: string;
    function Entry(ALine: Integer): TAtlasBreakpointSetEntry;
    function TextOf(const AFileName: string; out AText: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NamesAndFiles;
    [Test]
    procedure JsonRoundTripKeepsProperties;
    [Test]
    procedure ForeignFormatIsRejected;
    /// <summary>Akzeptanzkriterium: zehn Zeilen über der Routine eingefügt, der Haltepunkt sitzt wieder richtig.
    /// </summary>
    [Test]
    procedure ResolveFollowsInsertedLines;
    [Test]
    procedure ResolveReportsUnreadableAndMissing;
    [Test]
    procedure MergeSkipsSameLine;
    [Test]
    procedure BranchLookup;
    /// <summary>Akzeptanzkriterium: zwei Sätze, wechseln: nur die des aktiven sind an.</summary>
    [Test]
    procedure SwitchDisablesOtherSetsOnly;
    [Test]
    procedure AddKeepsOtherSets;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor;

const
  cSource =
    'unit Kunden;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    '' + #10 +
    'procedure Speichere;' + #10 +
    'begin' + #10 +
    '  Pruefe;' + #10 +
    '  Schreibe;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'procedure Lade;' + #10 +
    'begin' + #10 +
    '  Lies;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'end.' + #10;

function FileIn(const AFolder, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + 'Src' + PathDelim + AName;
end;

{ TAtlasBreakpointSetsTests }

procedure TAtlasBreakpointSetsTests.Setup;
begin
  FFolder := PathDelim + 'P';
  FText := cSource;
end;

procedure TAtlasBreakpointSetsTests.TearDown;
begin
  FFolder := '';
  FText := '';
end;

function TAtlasBreakpointSetsTests.Entry(ALine: Integer): TAtlasBreakpointSetEntry;
begin
  Result := TAtlasBreakpointSets.Capture(FileIn(FFolder, 'Kunden.pas'), cSource, ALine,
    TAtlasBreakpointProps.Default);
end;

function TAtlasBreakpointSetsTests.TextOf(const AFileName: string; out AText: string): Boolean;
begin
  Result := AFileName.EndsWith('Kunden.pas');
  AText := FText;
end;

procedure TAtlasBreakpointSetsTests.NamesAndFiles;
begin
  Assert.IsTrue(TAtlasBreakpointSets.ValidName('Import 4711'));
  Assert.IsFalse(TAtlasBreakpointSets.ValidName('  '));
  Assert.IsFalse(TAtlasBreakpointSets.ValidName('a/b'));
  Assert.IsFalse(TAtlasBreakpointSets.ValidName('Satz.'));
  Assert.IsFalse(TAtlasBreakpointSets.ValidName(StringOfChar('x', 81)));
  Assert.AreEqual(FFolder + PathDelim + '.atlas' + PathDelim + 'breakpoints' + PathDelim + 'Import.json',
    TAtlasBreakpointSets.FileFor(FFolder, ' Import '));
end;

procedure TAtlasBreakpointSetsTests.JsonRoundTripKeepsProperties;
var
  mSet, mRead: TAtlasBreakpointSet;
  mJson: string;
begin
  mSet := Default(TAtlasBreakpointSet);
  mSet.Name := 'Import';
  mSet.Branch := 'feature/import';
  mSet.Entries := [Entry(7)];
  mSet.Entries[0].Props.Enabled := False;
  mSet.Entries[0].Props.Condition := 'Nr = 4711';
  mSet.Entries[0].Props.PassCount := 3;
  mSet.Entries[0].Props.Group := 'Speichern';
  mSet.Entries[0].Props.DoBreak := False;
  mSet.Entries[0].Props.LogMessage := 'gespeichert';
  mSet.Entries[0].Props.StackFrames := 5;
  mJson := TAtlasBreakpointSets.ToJson(mSet, FFolder);
  Assert.IsTrue(mJson.Contains('"file":"Src/Kunden.pas"'), mJson);
  Assert.IsTrue(TAtlasBreakpointSets.Parse(mJson, FFolder, 'Datei', mRead));
  Assert.AreEqual('Import', mRead.Name);
  Assert.AreEqual('feature/import', mRead.Branch);
  Assert.AreEqual(1, Integer(Length(mRead.Entries)));
  Assert.AreEqual(FileIn(FFolder, 'Kunden.pas'), mRead.Entries[0].FileName);
  Assert.AreEqual('Speichere', mRead.Entries[0].Anchor.Method);
  Assert.AreEqual(3, mRead.Entries[0].Anchor.Offset);
  Assert.IsFalse(mRead.Entries[0].Props.Enabled);
  Assert.AreEqual('Nr = 4711', mRead.Entries[0].Props.Condition);
  Assert.AreEqual(3, mRead.Entries[0].Props.PassCount);
  Assert.AreEqual('Speichern', mRead.Entries[0].Props.Group);
  Assert.IsFalse(mRead.Entries[0].Props.DoBreak);
  Assert.AreEqual('gespeichert', mRead.Entries[0].Props.LogMessage);
  Assert.IsTrue(mRead.Entries[0].Props.LogResult);
  Assert.AreEqual(5, mRead.Entries[0].Props.StackFrames);
end;

procedure TAtlasBreakpointSetsTests.ForeignFormatIsRejected;
var
  mSet: TAtlasBreakpointSet;
begin
  Assert.IsFalse(TAtlasBreakpointSets.Parse('{"format":2,"breakpoints":[]}', FFolder, 'x', mSet));
  Assert.IsFalse(TAtlasBreakpointSets.Parse('[]', FFolder, 'x', mSet));
  Assert.IsTrue(TAtlasBreakpointSets.Parse('{"format":1,"breakpoints":[{"line":3}]}', FFolder, 'Datei', mSet));
  Assert.AreEqual('Datei', mSet.Name, 'Name aus dem Dateinamen');
  Assert.AreEqual(0, Integer(Length(mSet.Entries)), 'ohne Datei kein Eintrag');
end;

procedure TAtlasBreakpointSetsTests.ResolveFollowsInsertedLines;
var
  mResolved: TAtlasResolvedBreakpoints;
  mIndex: Integer;
begin
  FText := cSource;
  for mIndex := 1 to 10 do
  begin
    FText := FText.Replace('implementation' + #10, 'implementation' + #10 + '// neu' + #10);
  end;
  mResolved := TAtlasBreakpointSets.Resolve([Entry(7), Entry(12)], TextOf);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(mResolved[0].Match));
  Assert.AreEqual(17, mResolved[0].Line);
  Assert.AreEqual(22, mResolved[1].Line);
end;

procedure TAtlasBreakpointSetsTests.ResolveReportsUnreadableAndMissing;
var
  mOther: TAtlasBreakpointSetEntry;
  mResolved: TAtlasResolvedBreakpoints;
begin
  mOther := Entry(7);
  mOther.FileName := FileIn(FFolder, 'Fehlt.pas');
  FText := cSource.Replace('  Lies;' + #10, '');
  mResolved := TAtlasBreakpointSets.Resolve([mOther, Entry(12)], TextOf);
  Assert.IsFalse(mResolved[0].Found, 'Datei nicht lesbar');
  Assert.IsFalse(mResolved[1].Found, 'Zeile entfernt');
  Assert.AreEqual(12, mResolved[1].Line, 'letzte bekannte Zeile');
end;

procedure TAtlasBreakpointSetsTests.MergeSkipsSameLine;
var
  mA, mB, mMerged: TAtlasBreakpointSet;
begin
  mA := Default(TAtlasBreakpointSet);
  mA.Name := 'A';
  mA.Entries := [Entry(6)];
  mB := Default(TAtlasBreakpointSet);
  mB.Entries := [Entry(6), Entry(12)];
  mMerged := TAtlasBreakpointSets.Merge(mA, mB);
  Assert.AreEqual('A', mMerged.Name);
  Assert.AreEqual(2, Integer(Length(mMerged.Entries)));
  Assert.AreEqual(1, Integer(Length(mA.Entries)), 'Ziel bleibt unverändert');
end;

procedure TAtlasBreakpointSetsTests.BranchLookup;
var
  mSets: TAtlasBreakpointSetList;
begin
  SetLength(mSets, 2);
  mSets[0].Name := 'Ohne';
  mSets[1].Name := 'Import';
  mSets[1].Branch := 'feature/Import';
  Assert.AreEqual(1, TAtlasBreakpointSets.ForBranch(mSets, 'feature/import'));
  Assert.AreEqual(-1, TAtlasBreakpointSets.ForBranch(mSets, 'main'));
  Assert.AreEqual(-1, TAtlasBreakpointSets.ForBranch(mSets, ''));
end;

procedure TAtlasBreakpointSetsTests.SwitchDisablesOtherSetsOnly;
var
  mCurrent: TAtlasBreakpointPlaces;
  mTarget, mOthers: TAtlasResolvedBreakpoints;
  mActions: TAtlasBreakpointSetActions;
  mFile: string;
begin
  mFile := FileIn(FFolder, 'Kunden.pas');
  // IDE: 6 (Satz B, an), 7 (Satz A, aus), 12 (ohne Satz, an).
  mCurrent := [TAtlasBreakpointPlace.Create(mFile, 6, True), TAtlasBreakpointPlace.Create(mFile.ToLower, 7, False),
    TAtlasBreakpointPlace.Create(mFile, 12, True)];
  mTarget := TAtlasBreakpointSets.Resolve([Entry(7), Entry(13)], TextOf);
  mOthers := TAtlasBreakpointSets.Resolve([Entry(6)], TextOf);
  mActions := TAtlasBreakpointSets.Plan(mCurrent, mTarget, mOthers, True);
  Assert.AreEqual(3, Integer(Length(mActions)));
  Assert.AreEqual(Ord(TAtlasBreakpointSetActionKind.Enable), Ord(mActions[0].Kind));
  Assert.AreEqual(1, mActions[0].Index);
  Assert.AreEqual(Ord(TAtlasBreakpointSetActionKind.Create), Ord(mActions[1].Kind));
  Assert.AreEqual(13, mActions[1].Line);
  Assert.AreEqual(Ord(TAtlasBreakpointSetActionKind.Disable), Ord(mActions[2].Kind));
  Assert.AreEqual(0, mActions[2].Index, 'Satz B aus, Zeile 12 ohne Satz bleibt');
end;

procedure TAtlasBreakpointSetsTests.AddKeepsOtherSets;
var
  mCurrent: TAtlasBreakpointPlaces;
  mTarget, mOthers: TAtlasResolvedBreakpoints;
  mActions: TAtlasBreakpointSetActions;
begin
  mCurrent := [TAtlasBreakpointPlace.Create(FileIn(FFolder, 'Kunden.pas'), 6, True)];
  FText := cSource.Replace('  Lies;' + #10, '');
  mTarget := TAtlasBreakpointSets.Resolve([Entry(7), Entry(12)], TextOf);
  mOthers := TAtlasBreakpointSets.Resolve([Entry(6)], TextOf);
  mActions := TAtlasBreakpointSets.Plan(mCurrent, mTarget, mOthers, False);
  Assert.AreEqual(2, Integer(Length(mActions)));
  Assert.AreEqual(Ord(TAtlasBreakpointSetActionKind.Create), Ord(mActions[0].Kind));
  Assert.AreEqual(Ord(TAtlasBreakpointSetActionKind.Missing), Ord(mActions[1].Kind));
end;

end.
