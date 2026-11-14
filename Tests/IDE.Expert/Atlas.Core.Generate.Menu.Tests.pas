unit Atlas.Core.Generate.Menu.Tests;

// Tests für das Erzeugen-Menü (#719), Teil ohne Editor: Gruppen und ihre
// Reihenfolge, Ausblenden, unscharfes Filtern, Ziffern 1–9, zuletzt gewählte
// Einträge oben, Gruppenfilter für #759, Auswahl von Argumenten und die
// Einstellungen der Liste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGenerateMenuTests = class
  public
    [Test]
    procedure GroupsInConfiguredOrder;
    [Test]
    procedure DigitsForFirstNineEntries;
    [Test]
    procedure HiddenByIdOrName;
    [Test]
    procedure FilterIsFuzzyAndKeepsGroups;
    [Test]
    procedure RecentFirstWithoutDuplicates;
    [Test]
    procedure RecentCanBeSwitchedOff;
    [Test]
    procedure OnlyShowsRequestedGroups;
    [Test]
    procedure StepsOverHeaders;
    [Test]
    procedure ChoicesFilterAndJoin;
    [Test]
    procedure SettingsAreNormalized;
    [Test]
    procedure RecentListRoundTrips;
    [Test]
    procedure EntryIdsAndSteps;
    [Test]
    procedure SelectionEndLineSkipsLineStart;
    [Test]
    procedure ContractListsMatchOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Generate.Contract,
  Atlas.Core.Generate.Menu;

function Slash(const AName, ACaption: string; AGroup: TAtlasGenerateGroup): TAtlasGenerateEntry; overload;
begin
  Result := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Slash, AGroup, AName, ACaption);
end;

function Slash(const AName, ACaption: string): TAtlasGenerateEntry; overload;
begin
  Result := Slash(AName, ACaption, TAtlasGenerateGroup.Generate);
end;

function Template(const APrefix, ACaption: string): TAtlasGenerateEntry;
begin
  Result := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates, APrefix, ACaption);
end;

/// <summary>Wie im Mockup AC7 plus Umschließen und Vorlagen.</summary>
function Sample: TArray<TAtlasGenerateEntry>;
begin
  Result := [Slash('ctor', 'Konstruktor aus Feldern'), Slash('dtor', 'Destruktor mit Freigabe'),
    Slash('prop', 'Property mit Feld'), Slash('override', 'Methoden überschreiben…'),
    Slash('implement', 'Interface implementieren…'), Slash('equals', 'Equals / GetHashCode'),
    Slash('try', 'try … finally', TAtlasGenerateGroup.Surround), Template('tryf', 'try…finally mit Create/Free')];
end;

/// <summary>Zeilen als Text: "#Gruppe" für Köpfe, sonst "Ziffer:Name".</summary>
function Show(const AEntries: TArray<TAtlasGenerateEntry>; const ARows: TArray<TAtlasGenerateRow>): string;
var
  mRow: TAtlasGenerateRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    if mRow.IsHeader then
    begin
      Result := Result + '#' + TAtlasGenerateOptions.GroupName(mRow.Group);
    end
    else
    begin
      Result := Result + IntToStr(mRow.Digit) + ':' + AEntries[mRow.Entry].Name;
    end;
  end;
end;

procedure TAtlasGenerateMenuTests.GroupsInConfiguredOrder;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mOptions: TAtlasGenerateOptions;
begin
  mEntries := Sample;
  mOptions := TAtlasGenerateOptions.Default;
  Assert.AreEqual('#generate 1:ctor 2:dtor 3:prop 4:override 5:implement 6:equals #surround 7:try ' +
    '#templates 8:tryf', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, '')));
  // Reihenfolge und Auswahl der Gruppen aus keys.generateMenu.groups.
  mOptions := TAtlasGenerateOptions.Create('templates, generate', '', True, True);
  Assert.AreEqual('#templates 1:tryf #generate 2:ctor 3:dtor 4:prop 5:override 6:implement 7:equals',
    Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, '')));
  // Leere Gruppen haben keinen Kopf.
  Assert.AreEqual('#generate 1:ctor', Show([mEntries[0]], TAtlasGenerateMenu.Rows([mEntries[0]],
    TAtlasGenerateOptions.Default, nil, '')));
end;

procedure TAtlasGenerateMenuTests.DigitsForFirstNineEntries;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mRows: TArray<TAtlasGenerateRow>;
  mIndex: Integer;
begin
  mEntries := nil;
  for mIndex := 1 to 12 do
  begin
    mEntries := mEntries + [Slash('c' + IntToStr(mIndex), 'Befehl ' + IntToStr(mIndex))];
  end;
  mRows := TAtlasGenerateMenu.Rows(mEntries, TAtlasGenerateOptions.Default, nil, '');
  Assert.AreEqual(13, Integer(Length(mRows)));
  Assert.AreEqual(9, mRows[9].Digit);
  Assert.AreEqual(0, mRows[10].Digit, 'ab dem zehnten ohne Ziffer');
  Assert.AreEqual(1, TAtlasGenerateMenu.RowOfDigit(mRows, 1));
  Assert.AreEqual(9, TAtlasGenerateMenu.RowOfDigit(mRows, 9));
  Assert.AreEqual(-1, TAtlasGenerateMenu.RowOfDigit(mRows, 0));
  Assert.AreEqual(-1, TAtlasGenerateMenu.RowOfDigit(TAtlasGenerateMenu.Rows([mEntries[0]],
    TAtlasGenerateOptions.Default, nil, ''), 2));
end;

procedure TAtlasGenerateMenuTests.HiddenByIdOrName;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mOptions: TAtlasGenerateOptions;
  mAction: TAtlasGenerateEntry;
begin
  mEntries := Sample;
  mOptions := TAtlasGenerateOptions.Create('', '/ctor, slash:equals, tryf, dtor', True, True);
  Assert.AreEqual('#generate 1:prop 2:override 3:implement #surround 4:try',
    Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, '')));
  // Code-Aktionen nur über ihre Kennung; ein Name wie „ctor“ trifft sie nicht.
  mAction := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate, 'ctor', 'ctor');
  Assert.IsFalse(mOptions.IsHidden(mAction));
  mOptions := TAtlasGenerateOptions.Create('', 'action:ctor', True, True);
  Assert.IsTrue(mOptions.IsHidden(mAction));
end;

procedure TAtlasGenerateMenuTests.FilterIsFuzzyAndKeepsGroups;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mOptions: TAtlasGenerateOptions;
begin
  mEntries := Sample;
  mOptions := TAtlasGenerateOptions.Default;
  // Über die Beschriftung …
  Assert.AreEqual('#generate 1:prop', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, 'Property')));
  // … und den Befehlsnamen, auch mit "/".
  Assert.AreEqual('#generate 1:ctor', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, '/ctor')));
  // Unscharf über Wortanfänge (#229): „EG“ trifft „Equals / GetHashCode“.
  Assert.AreEqual('#generate 1:equals', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, 'EG')));
  // Gruppen bleiben, Ziffern zählen weiter.
  Assert.AreEqual('#surround 1:try #templates 2:tryf', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil,
    'try')));
  Assert.AreEqual('', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, 'xyzzy')));
end;

procedure TAtlasGenerateMenuTests.RecentFirstWithoutDuplicates;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mRecent: TAtlasGenerateRecent;
begin
  mEntries := Sample;
  mRecent := TAtlasGenerateRecent.Create;
  try
    mRecent.Chosen('slash:prop');
    mRecent.Chosen('snippet:tryf');
    mRecent.Chosen('slash:equals');
    mRecent.Chosen('slash:dtor');
    // Höchstens drei, der zuletzt gewählte zuerst; in ihrer Gruppe stehen sie nicht noch einmal.
    Assert.AreEqual('#recent 1:dtor 2:equals 3:tryf #generate 4:ctor 5:prop 6:override 7:implement ' +
      '#surround 8:try', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, TAtlasGenerateOptions.Default, mRecent, '')));
    // Auch beim Filtern oben.
    Assert.AreEqual('#recent 1:tryf #surround 2:try',
      Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, TAtlasGenerateOptions.Default, mRecent, 'try')));
    // Ausgeblendete zählen nicht.
    Assert.StartsWith('#recent 1:equals 2:tryf 3:prop #generate', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries,
      TAtlasGenerateOptions.Create('', 'dtor', True, True), mRecent, '')));
  finally
    mRecent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.RecentCanBeSwitchedOff;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mRecent: TAtlasGenerateRecent;
begin
  mEntries := Sample;
  mRecent := TAtlasGenerateRecent.Create;
  try
    mRecent.Chosen('slash:equals');
    Assert.StartsWith('#generate 1:ctor', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries,
      TAtlasGenerateOptions.Create('', '', False, True), mRecent, '')));
  finally
    mRecent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.OnlyShowsRequestedGroups;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mOptions: TAtlasGenerateOptions;
begin
  mEntries := Sample;
  // #759: „Neu mit Atlas“ öffnet das Menü nur mit Vorlagen.
  mOptions := TAtlasGenerateOptions.Default.Only([TAtlasGenerateGroup.Templates]);
  Assert.AreEqual('#templates 1:tryf', Show(mEntries, TAtlasGenerateMenu.Rows(mEntries, mOptions, nil, '')));
  // Eingestellte Reihenfolge bleibt.
  mOptions := TAtlasGenerateOptions.Create('templates,generate,surround', '', True, True).Only(
    [TAtlasGenerateGroup.Generate, TAtlasGenerateGroup.Templates]);
  Assert.AreEqual(2, Integer(Length(mOptions.Groups)));
  Assert.AreEqual<TAtlasGenerateGroup>(TAtlasGenerateGroup.Templates, mOptions.Groups[0]);
  // Abgeschaltet, aber verlangt: trotzdem da.
  mOptions := TAtlasGenerateOptions.Create('generate', '', True, True).Only([TAtlasGenerateGroup.Templates]);
  Assert.IsTrue(mOptions.HasGroup(TAtlasGenerateGroup.Templates));
end;

procedure TAtlasGenerateMenuTests.StepsOverHeaders;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mRows: TArray<TAtlasGenerateRow>;
begin
  mEntries := Sample;
  mRows := TAtlasGenerateMenu.Rows(mEntries, TAtlasGenerateOptions.Default, nil, '');
  Assert.AreEqual(1, TAtlasGenerateMenu.FirstEntryRow(mRows));
  // Zeile 6 ist equals, 7 der Kopf Umschließen, 8 try.
  Assert.AreEqual(8, TAtlasGenerateMenu.StepRow(mRows, 6, 1));
  Assert.AreEqual(6, TAtlasGenerateMenu.StepRow(mRows, 8, -1));
  Assert.AreEqual(1, TAtlasGenerateMenu.StepRow(mRows, 1, -1), 'oben bleibt stehen');
  Assert.AreEqual(Integer(High(mRows)), TAtlasGenerateMenu.StepRow(mRows, High(mRows), 1), 'unten bleibt stehen');
  Assert.AreEqual(-1, TAtlasGenerateMenu.StepRow(nil, 0, 1));
end;

procedure TAtlasGenerateMenuTests.ChoicesFilterAndJoin;
var
  mChoices: TArray<string>;
  mOrder: TArray<Integer>;
begin
  mChoices := ['FListe', 'FName', 'FAlter'];
  mOrder := TAtlasGenerateMenu.FilterChoices(mChoices, '');
  Assert.AreEqual(3, Integer(Length(mOrder)));
  Assert.AreEqual(0, mOrder[0]);
  mOrder := TAtlasGenerateMenu.FilterChoices(mChoices, 'na');
  Assert.AreEqual(1, Integer(Length(mOrder)));
  Assert.AreEqual(1, mOrder[0]);
  // Alle bzw. keins angehakt = ohne Argument (/ctor nimmt dann alle Felder).
  Assert.AreEqual('', TAtlasGenerateMenu.JoinChoices(mChoices, [True, True, True], ', ', True));
  Assert.AreEqual('', TAtlasGenerateMenu.JoinChoices(mChoices, [False, False, False], ', ', True));
  Assert.AreEqual('FListe, FAlter', TAtlasGenerateMenu.JoinChoices(mChoices, [True, False, True], ', ', True));
  Assert.AreEqual('FListe FName FAlter', TAtlasGenerateMenu.JoinChoices(mChoices, [True, True, True], ' ', False));
end;

procedure TAtlasGenerateMenuTests.SettingsAreNormalized;
begin
  Assert.AreEqual('generate,surround,templates', TAtlasGenerateOptions.NormalizeGroups(''));
  Assert.AreEqual('templates,generate', TAtlasGenerateOptions.NormalizeGroups(' Templates ; generate,templates'));
  Assert.AreEqual('generate,surround,templates', TAtlasGenerateOptions.NormalizeGroups('quatsch, recent'));
  Assert.AreEqual('/ctor, tryf', TAtlasGenerateOptions.NormalizeHidden(' /ctor ,, tryf, /CTOR '));
  Assert.AreEqual('/ctor, slash:dtor', TAtlasGenerateOptions.AddHidden('/ctor', 'slash:dtor'));
  Assert.AreEqual('slash:dtor', TAtlasGenerateOptions.AddHidden('', 'slash:dtor'));
end;

procedure TAtlasGenerateMenuTests.RecentListRoundTrips;
var
  mRecent: TAtlasGenerateRecent;
  mIndex: Integer;
begin
  mRecent := TAtlasGenerateRecent.Create;
  try
    mRecent.LoadFromText('slash:ctor'#13#10#13#10'snippet:tryf'#10'slash:ctor');
    Assert.AreEqual(2, Integer(Length(mRecent.Ids)));
    Assert.AreEqual(0, mRecent.Rank('slash:ctor'));
    Assert.AreEqual(-1, mRecent.Rank('slash:dtor'));
    mRecent.Chosen('snippet:tryf');
    Assert.AreEqual('snippet:tryf'#13#10'slash:ctor', mRecent.ToText);
    for mIndex := 1 to 30 do
    begin
      mRecent.Chosen('slash:c' + IntToStr(mIndex));
    end;
    Assert.AreEqual(TAtlasGenerateRecent.cMaxCount, Integer(Length(mRecent.Ids)));
    mRecent.Clear;
    Assert.AreEqual('', mRecent.ToText);
  finally
    mRecent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.EntryIdsAndSteps;
var
  mEntry: TAtlasGenerateEntry;
begin
  mEntry := Slash('ctor', 'Konstruktor aus Feldern');
  Assert.AreEqual('slash:ctor', mEntry.Id);
  Assert.AreEqual('/ctor', mEntry.CommandName);
  Assert.AreEqual(-1, mEntry.Source);
  Assert.IsFalse(mEntry.NeedsStep, 'ohne Argument sofort');
  mEntry.HasChoices := True;
  Assert.IsTrue(mEntry.NeedsStep, 'Felder wählen');
  mEntry := Slash('prop', 'Property');
  mEntry.Argument := TAtlasGenerateArgument.Required;
  Assert.IsTrue(mEntry.NeedsStep, 'Argument eingeben');
  mEntry := Template('tryf', 'try');
  Assert.AreEqual('snippet:tryf', mEntry.Id);
  Assert.AreEqual('tryf', mEntry.CommandName);
  Assert.IsFalse(mEntry.NeedsStep);
  mEntry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate, 'Umbauen', 'Umbauen');
  Assert.AreEqual('action:Umbauen', mEntry.Id);
  Assert.AreEqual('', mEntry.CommandName);
end;

procedure TAtlasGenerateMenuTests.SelectionEndLineSkipsLineStart;
begin
  Assert.AreEqual(-1, TAtlasGenerateMenu.SelectionEndLine(3, 3, 5, False));
  Assert.AreEqual(4, TAtlasGenerateMenu.SelectionEndLine(3, 4, 7, True));
  // Ganze Zeilen 3 und 4 markiert: Ende am Anfang von Zeile 5.
  Assert.AreEqual(4, TAtlasGenerateMenu.SelectionEndLine(3, 5, 0, True));
  Assert.AreEqual(3, TAtlasGenerateMenu.SelectionEndLine(3, 3, 0, True));
end;

procedure TAtlasGenerateMenuTests.ContractListsMatchOptions;
var
  mGroup: TAtlasGenerateGroup;
begin
  // Die Einstellungen normalisieren über den Contract, das Menü leitet nur weiter.
  Assert.AreEqual('templates,generate', TAtlasGenerateLists.NormalizeGroups(' Templates; quatsch, generate '));
  Assert.AreEqual(TAtlasGenerateOptions.NormalizeGroups('surround'), TAtlasGenerateLists.NormalizeGroups('surround'));
  Assert.AreEqual('/json, tryf', TAtlasGenerateLists.NormalizeHidden('/json, , /json,tryf'));
  Assert.AreEqual(2, Integer(Length(TAtlasGenerateLists.Split('a;; b,'#10))));
  Assert.IsTrue(TAtlasGenerateLists.TryParseGroup(' Surround ', mGroup));
  Assert.AreEqual<TAtlasGenerateGroup>(TAtlasGenerateGroup.Surround, mGroup);
  Assert.AreEqual('recent', TAtlasGenerateLists.GroupName(TAtlasGenerateGroup.Recent));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateMenuTests);

end.
