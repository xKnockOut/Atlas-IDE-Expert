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
  end;

implementation

uses
  System.SysUtils,
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
  Row: TAtlasGenerateRow;
begin
  Result := '';
  for Row in ARows do
  begin
    if Result <> '' then
      Result := Result + ' ';
    if Row.IsHeader then
      Result := Result + '#' + TAtlasGenerateOptions.GroupName(Row.Group)
    else
      Result := Result + IntToStr(Row.Digit) + ':' + AEntries[Row.Entry].Name;
  end;
end;

procedure TAtlasGenerateMenuTests.GroupsInConfiguredOrder;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Options: TAtlasGenerateOptions;
begin
  Entries := Sample;
  Options := TAtlasGenerateOptions.Default;
  Assert.AreEqual('#generate 1:ctor 2:dtor 3:prop 4:override 5:implement 6:equals #surround 7:try ' +
    '#templates 8:tryf', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, '')));
  // Reihenfolge und Auswahl der Gruppen aus keys.generateMenu.groups.
  Options := TAtlasGenerateOptions.Create('templates, generate', '', True, True);
  Assert.AreEqual('#templates 1:tryf #generate 2:ctor 3:dtor 4:prop 5:override 6:implement 7:equals',
    Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, '')));
  // Leere Gruppen haben keinen Kopf.
  Assert.AreEqual('#generate 1:ctor', Show([Entries[0]], TAtlasGenerateMenu.Rows([Entries[0]],
    TAtlasGenerateOptions.Default, nil, '')));
end;

procedure TAtlasGenerateMenuTests.DigitsForFirstNineEntries;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Rows: TArray<TAtlasGenerateRow>;
  Index: Integer;
begin
  Entries := nil;
  for Index := 1 to 12 do
    Entries := Entries + [Slash('c' + IntToStr(Index), 'Befehl ' + IntToStr(Index))];
  Rows := TAtlasGenerateMenu.Rows(Entries, TAtlasGenerateOptions.Default, nil, '');
  Assert.AreEqual(13, Integer(Length(Rows)));
  Assert.AreEqual(9, Rows[9].Digit);
  Assert.AreEqual(0, Rows[10].Digit, 'ab dem zehnten ohne Ziffer');
  Assert.AreEqual(1, TAtlasGenerateMenu.RowOfDigit(Rows, 1));
  Assert.AreEqual(9, TAtlasGenerateMenu.RowOfDigit(Rows, 9));
  Assert.AreEqual(-1, TAtlasGenerateMenu.RowOfDigit(Rows, 0));
  Assert.AreEqual(-1, TAtlasGenerateMenu.RowOfDigit(TAtlasGenerateMenu.Rows([Entries[0]],
    TAtlasGenerateOptions.Default, nil, ''), 2));
end;

procedure TAtlasGenerateMenuTests.HiddenByIdOrName;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Options: TAtlasGenerateOptions;
  Action: TAtlasGenerateEntry;
begin
  Entries := Sample;
  Options := TAtlasGenerateOptions.Create('', '/ctor, slash:equals, tryf, dtor', True, True);
  Assert.AreEqual('#generate 1:prop 2:override 3:implement #surround 4:try',
    Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, '')));
  // Code-Aktionen nur über ihre Kennung; ein Name wie „ctor“ trifft sie nicht.
  Action := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate, 'ctor', 'ctor');
  Assert.IsFalse(Options.IsHidden(Action));
  Options := TAtlasGenerateOptions.Create('', 'action:ctor', True, True);
  Assert.IsTrue(Options.IsHidden(Action));
end;

procedure TAtlasGenerateMenuTests.FilterIsFuzzyAndKeepsGroups;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Options: TAtlasGenerateOptions;
begin
  Entries := Sample;
  Options := TAtlasGenerateOptions.Default;
  // Über die Beschriftung …
  Assert.AreEqual('#generate 1:prop', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, 'Property')));
  // … und den Befehlsnamen, auch mit "/".
  Assert.AreEqual('#generate 1:ctor', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, '/ctor')));
  // Unscharf über Wortanfänge (#229): „EG“ trifft „Equals / GetHashCode“.
  Assert.AreEqual('#generate 1:equals', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, 'EG')));
  // Gruppen bleiben, Ziffern zählen weiter.
  Assert.AreEqual('#surround 1:try #templates 2:tryf', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil,
    'try')));
  Assert.AreEqual('', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, 'xyzzy')));
end;

procedure TAtlasGenerateMenuTests.RecentFirstWithoutDuplicates;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Recent: TAtlasGenerateRecent;
begin
  Entries := Sample;
  Recent := TAtlasGenerateRecent.Create;
  try
    Recent.Chosen('slash:prop');
    Recent.Chosen('snippet:tryf');
    Recent.Chosen('slash:equals');
    Recent.Chosen('slash:dtor');
    // Höchstens drei, der zuletzt gewählte zuerst; in ihrer Gruppe stehen sie nicht noch einmal.
    Assert.AreEqual('#recent 1:dtor 2:equals 3:tryf #generate 4:ctor 5:prop 6:override 7:implement ' +
      '#surround 8:try', Show(Entries, TAtlasGenerateMenu.Rows(Entries, TAtlasGenerateOptions.Default, Recent, '')));
    // Auch beim Filtern oben.
    Assert.AreEqual('#recent 1:tryf #surround 2:try',
      Show(Entries, TAtlasGenerateMenu.Rows(Entries, TAtlasGenerateOptions.Default, Recent, 'try')));
    // Ausgeblendete zählen nicht.
    Assert.StartsWith('#recent 1:equals 2:tryf 3:prop #generate', Show(Entries, TAtlasGenerateMenu.Rows(Entries,
      TAtlasGenerateOptions.Create('', 'dtor', True, True), Recent, '')));
  finally
    Recent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.RecentCanBeSwitchedOff;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Recent: TAtlasGenerateRecent;
begin
  Entries := Sample;
  Recent := TAtlasGenerateRecent.Create;
  try
    Recent.Chosen('slash:equals');
    Assert.StartsWith('#generate 1:ctor', Show(Entries, TAtlasGenerateMenu.Rows(Entries,
      TAtlasGenerateOptions.Create('', '', False, True), Recent, '')));
  finally
    Recent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.OnlyShowsRequestedGroups;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Options: TAtlasGenerateOptions;
begin
  Entries := Sample;
  // #759: „Neu mit Atlas“ öffnet das Menü nur mit Vorlagen.
  Options := TAtlasGenerateOptions.Default.Only([TAtlasGenerateGroup.Templates]);
  Assert.AreEqual('#templates 1:tryf', Show(Entries, TAtlasGenerateMenu.Rows(Entries, Options, nil, '')));
  // Eingestellte Reihenfolge bleibt.
  Options := TAtlasGenerateOptions.Create('templates,generate,surround', '', True, True).Only(
    [TAtlasGenerateGroup.Generate, TAtlasGenerateGroup.Templates]);
  Assert.AreEqual(2, Integer(Length(Options.Groups)));
  Assert.IsTrue(Options.Groups[0] = TAtlasGenerateGroup.Templates);
  // Abgeschaltet, aber verlangt: trotzdem da.
  Options := TAtlasGenerateOptions.Create('generate', '', True, True).Only([TAtlasGenerateGroup.Templates]);
  Assert.IsTrue(Options.HasGroup(TAtlasGenerateGroup.Templates));
end;

procedure TAtlasGenerateMenuTests.StepsOverHeaders;
var
  Entries: TArray<TAtlasGenerateEntry>;
  Rows: TArray<TAtlasGenerateRow>;
begin
  Entries := Sample;
  Rows := TAtlasGenerateMenu.Rows(Entries, TAtlasGenerateOptions.Default, nil, '');
  Assert.AreEqual(1, TAtlasGenerateMenu.FirstEntryRow(Rows));
  // Zeile 6 ist equals, 7 der Kopf Umschließen, 8 try.
  Assert.AreEqual(8, TAtlasGenerateMenu.StepRow(Rows, 6, 1));
  Assert.AreEqual(6, TAtlasGenerateMenu.StepRow(Rows, 8, -1));
  Assert.AreEqual(1, TAtlasGenerateMenu.StepRow(Rows, 1, -1), 'oben bleibt stehen');
  Assert.AreEqual(High(Rows), TAtlasGenerateMenu.StepRow(Rows, High(Rows), 1), 'unten bleibt stehen');
  Assert.AreEqual(-1, TAtlasGenerateMenu.StepRow(nil, 0, 1));
end;

procedure TAtlasGenerateMenuTests.ChoicesFilterAndJoin;
var
  Choices: TArray<string>;
  Order: TArray<Integer>;
begin
  Choices := ['FListe', 'FName', 'FAlter'];
  Order := TAtlasGenerateMenu.FilterChoices(Choices, '');
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual(0, Order[0]);
  Order := TAtlasGenerateMenu.FilterChoices(Choices, 'na');
  Assert.AreEqual(1, Integer(Length(Order)));
  Assert.AreEqual(1, Order[0]);
  // Alle bzw. keins angehakt = ohne Argument (/ctor nimmt dann alle Felder).
  Assert.AreEqual('', TAtlasGenerateMenu.JoinChoices(Choices, [True, True, True], ', ', True));
  Assert.AreEqual('', TAtlasGenerateMenu.JoinChoices(Choices, [False, False, False], ', ', True));
  Assert.AreEqual('FListe, FAlter', TAtlasGenerateMenu.JoinChoices(Choices, [True, False, True], ', ', True));
  Assert.AreEqual('FListe FName FAlter', TAtlasGenerateMenu.JoinChoices(Choices, [True, True, True], ' ', False));
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
  Recent: TAtlasGenerateRecent;
  Index: Integer;
begin
  Recent := TAtlasGenerateRecent.Create;
  try
    Recent.LoadFromText('slash:ctor'#13#10#13#10'snippet:tryf'#10'slash:ctor');
    Assert.AreEqual(2, Integer(Length(Recent.Ids)));
    Assert.AreEqual(0, Recent.Rank('slash:ctor'));
    Assert.AreEqual(-1, Recent.Rank('slash:dtor'));
    Recent.Chosen('snippet:tryf');
    Assert.AreEqual('snippet:tryf'#13#10'slash:ctor', Recent.ToText);
    for Index := 1 to 30 do
      Recent.Chosen('slash:c' + IntToStr(Index));
    Assert.AreEqual(TAtlasGenerateRecent.MaxCount, Integer(Length(Recent.Ids)));
    Recent.Clear;
    Assert.AreEqual('', Recent.ToText);
  finally
    Recent.Free;
  end;
end;

procedure TAtlasGenerateMenuTests.EntryIdsAndSteps;
var
  Entry: TAtlasGenerateEntry;
begin
  Entry := Slash('ctor', 'Konstruktor aus Feldern');
  Assert.AreEqual('slash:ctor', Entry.Id);
  Assert.AreEqual('/ctor', Entry.CommandName);
  Assert.AreEqual(-1, Entry.Source);
  Assert.IsFalse(Entry.NeedsStep, 'ohne Argument sofort');
  Entry.HasChoices := True;
  Assert.IsTrue(Entry.NeedsStep, 'Felder wählen');
  Entry := Slash('prop', 'Property');
  Entry.Argument := TAtlasGenerateArgument.Required;
  Assert.IsTrue(Entry.NeedsStep, 'Argument eingeben');
  Entry := Template('tryf', 'try');
  Assert.AreEqual('snippet:tryf', Entry.Id);
  Assert.AreEqual('tryf', Entry.CommandName);
  Assert.IsFalse(Entry.NeedsStep);
  Entry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate, 'Umbauen', 'Umbauen');
  Assert.AreEqual('action:Umbauen', Entry.Id);
  Assert.AreEqual('', Entry.CommandName);
end;

procedure TAtlasGenerateMenuTests.SelectionEndLineSkipsLineStart;
begin
  Assert.AreEqual(-1, TAtlasGenerateMenu.SelectionEndLine(3, 3, 5, False));
  Assert.AreEqual(4, TAtlasGenerateMenu.SelectionEndLine(3, 4, 7, True));
  // Ganze Zeilen 3 und 4 markiert: Ende am Anfang von Zeile 5.
  Assert.AreEqual(4, TAtlasGenerateMenu.SelectionEndLine(3, 5, 0, True));
  Assert.AreEqual(3, TAtlasGenerateMenu.SelectionEndLine(3, 3, 0, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGenerateMenuTests);

end.
