unit Atlas.Core.Designer.FormTexts.Tests;

// Tests für „Texte des Formulars“ (#728): Tastenkürzel je Gruppe,
// Schreibweisen mit und ohne Synonyme, Leerzeichen, Doppelpunkt,
// abgeschnittene Texte, ausgeschlossene Eigenschaften, Einstellungen und Filter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormTextsTests = class
  public
    [Test]
    procedure AcceleratorOf;
    [Test]
    procedure DuplicateAccelerators;
    [Test]
    procedure Variants;
    [Test]
    procedure SentenceStartIsNoVariant;
    [Test]
    procedure Synonyms;
    [Test]
    procedure WhitespaceAndColon;
    [Test]
    procedure TruncatedOnlyWhenOn;
    [Test]
    procedure ExcludedProperties;
    [Test]
    procedure ParseChecks;
    [Test]
    procedure FilterMatches;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FormTexts;

const
  cAll = [Low(TAtlasTextCheck) .. High(TAtlasTextCheck)];

function Entry(const AComponent, AText: string; const AGroup: string = 'pnlMain'): TAtlasTextEntry;
begin
  Result := TAtlasTextEntry.Create(AComponent, 'TButton', 'Caption', AText, AGroup);
end;

function Kinds(const AEntry: TAtlasTextEntry): string;
const
  cNames: array [TAtlasTextCheck] of string = ('A', 'V', 'T', 'W', 'C');
var
  mFinding: TAtlasTextFinding;
begin
  Result := '';
  for mFinding in AEntry.Findings do
  begin
    Result := Result + cNames[mFinding.Check];
  end;
end;

procedure TAtlasFormTextsTests.AcceleratorOf;
begin
  Assert.AreEqual('S', string(TAtlasFormTexts.AcceleratorOf('&speichern')));
  Assert.AreEqual('U', string(TAtlasFormTexts.AcceleratorOf('S&uchen')));
  Assert.AreEqual(#0, TAtlasFormTexts.AcceleratorOf('Laden && Speichern'), '&& ist kein Kürzel');
  Assert.AreEqual('P', string(TAtlasFormTexts.AcceleratorOf('A && B &prüfen')));
  Assert.AreEqual(#0, TAtlasFormTexts.AcceleratorOf('Ende&'));
end;

procedure TAtlasFormTextsTests.DuplicateAccelerators;
var
  mResult: TArray<TAtlasTextEntry>;
begin
  mResult := TAtlasFormTexts.Check([Entry('btnSave', '&Speichern'), Entry('btnSearch', '&Suchen'),
    Entry('btnOther', '&Suchen', 'pnlOther'), Entry('btnLoad', '&Laden'), Entry('mnuSave', '&Speichern', '')],
    [TAtlasTextCheck.Accelerators], nil);
  Assert.AreEqual('A', Kinds(mResult[0]));
  Assert.AreEqual('&S: btnSearch', mResult[0].Findings[0].Detail);
  Assert.AreEqual('A', Kinds(mResult[1]));
  Assert.AreEqual('', Kinds(mResult[2]), 'andere Gruppe');
  Assert.AreEqual('', Kinds(mResult[3]));
  Assert.AreEqual('', Kinds(mResult[4]), 'ohne Gruppe keine Prüfung');
end;

procedure TAtlasFormTextsTests.Variants;
var
  mResult: TArray<TAtlasTextEntry>;
begin
  mResult := TAtlasFormTexts.Check([Entry('lblMail', 'E-Mail:'), Entry('edtMail', 'Ihre Email-Adresse'),
    Entry('lblOther', 'Telefon'), Entry('lblThird', 'eMail senden'), Entry('lblFourth', 'Email')], [TAtlasTextCheck.Variants], nil);
  Assert.AreEqual('V', Kinds(mResult[0]));
  Assert.AreEqual('E-Mail / eMail / Email', mResult[0].Findings[0].Detail);
  Assert.AreEqual('', Kinds(mResult[1]), 'Email-Adresse ist ein eigenes Wort');
  Assert.AreEqual('V', Kinds(mResult[3]));
  Assert.AreEqual('', Kinds(mResult[2]));
end;

procedure TAtlasFormTextsTests.SentenceStartIsNoVariant;
var
  mResult: TArray<TAtlasTextEntry>;
begin
  mResult := TAtlasFormTexts.Check([Entry('btnA', 'Speichern'), Entry('btnB', 'Daten speichern')],
    [TAtlasTextCheck.Variants], nil);
  Assert.AreEqual('', Kinds(mResult[0]));
  Assert.AreEqual('', Kinds(mResult[1]));
end;

procedure TAtlasFormTextsTests.Synonyms;
var
  mSynonyms: TArray<TArray<string>>;
  mResult: TArray<TAtlasTextEntry>;
begin
  mSynonyms := TAtlasFormTexts.ParseSynonyms('Lieferant, Lieferer; Einzel');
  Assert.AreEqual(1, Integer(Length(mSynonyms)), 'Gruppe mit einem Begriff entfällt');
  mResult := TAtlasFormTexts.Check([Entry('lblA', 'Lieferant'), Entry('lblB', 'Neuer Lieferer'),
    Entry('lblC', 'Kunde')], [TAtlasTextCheck.Variants], mSynonyms);
  Assert.AreEqual('V', Kinds(mResult[0]));
  Assert.AreEqual('Lieferant / Lieferer', mResult[0].Findings[0].Detail);
  Assert.AreEqual('V', Kinds(mResult[1]));
  Assert.AreEqual('', Kinds(mResult[2]));
  mResult := TAtlasFormTexts.Check([Entry('lblA', 'Lieferant'), Entry('lblB', 'Neuer Lieferer')],
    [TAtlasTextCheck.Variants], nil);
  Assert.AreEqual('', Kinds(mResult[0]), 'ohne Synonyme kein Hinweis');
end;

procedure TAtlasFormTextsTests.WhitespaceAndColon;
var
  mEntries, mResult: TArray<TAtlasTextEntry>;
begin
  mEntries := [Entry('a', ' Name'), Entry('b', 'Vor  Name'), Entry('c', 'Name '), Entry('d', 'Name'),
    Entry('e', 'Name:'), Entry('f', 'Name')];
  mEntries[3].NeedsColon := True;
  mEntries[4].NeedsColon := True;
  mResult := TAtlasFormTexts.Check(mEntries, [TAtlasTextCheck.Whitespace, TAtlasTextCheck.LabelColon], nil);
  Assert.AreEqual('W', Kinds(mResult[0]));
  Assert.AreEqual('W', Kinds(mResult[1]));
  Assert.AreEqual('W', Kinds(mResult[2]));
  Assert.AreEqual('C', Kinds(mResult[3]));
  Assert.AreEqual('', Kinds(mResult[4]));
  Assert.AreEqual('', Kinds(mResult[5]), 'ohne FocusControl kein Doppelpunkt nötig');
  mResult := TAtlasFormTexts.Check(mEntries, [TAtlasTextCheck.Whitespace], nil);
  Assert.AreEqual('', Kinds(mResult[3]), 'labelColon aus');
end;

procedure TAtlasFormTextsTests.TruncatedOnlyWhenOn;
var
  mEntries, mResult: TArray<TAtlasTextEntry>;
begin
  mEntries := [Entry('lblLong', 'Ein sehr langer Text')];
  mEntries[0].Truncated := True;
  mResult := TAtlasFormTexts.Check(mEntries, cAll, nil);
  Assert.AreEqual('T', Kinds(mResult[0]));
  mResult := TAtlasFormTexts.Check(mEntries, [TAtlasTextCheck.Whitespace], nil);
  Assert.AreEqual('', Kinds(mResult[0]));
  Assert.AreEqual(0, Integer(Length(mEntries[0].Findings)), 'Eingabe bleibt unverändert');
end;

procedure TAtlasFormTextsTests.ExcludedProperties;
begin
  Assert.IsTrue(TAtlasFormTexts.Excluded('SQL[2]', TAtlasFormTexts.cDefaultExcluded));
  Assert.IsTrue(TAtlasFormTexts.Excluded('CommandText', TAtlasFormTexts.cDefaultExcluded));
  Assert.IsFalse(TAtlasFormTexts.Excluded('Caption', TAtlasFormTexts.cDefaultExcluded));
  Assert.IsTrue(TAtlasFormTexts.Excluded('Columns[1].Title.Caption', 'Hint, Columns'));
  Assert.IsFalse(TAtlasFormTexts.Excluded('Items[0]', ''));
end;

procedure TAtlasFormTextsTests.ParseChecks;
begin
  Assert.IsTrue(TAtlasFormTexts.ParseChecks(TAtlasFormTexts.cDefaultChecks) = [TAtlasTextCheck.Accelerators,
    TAtlasTextCheck.Variants, TAtlasTextCheck.Truncated, TAtlasTextCheck.Whitespace]);
  Assert.IsTrue(TAtlasFormTexts.ParseChecks('labelcolon; unknown') = [TAtlasTextCheck.LabelColon]);
  Assert.IsTrue(TAtlasFormTexts.ParseChecks('') = []);
end;

procedure TAtlasFormTextsTests.FilterMatches;
var
  mEntries: TArray<TAtlasTextEntry>;
begin
  mEntries := TAtlasFormTexts.Check([Entry('btnSave', '&Speichern'), Entry('btnSearch', '&Suchen'),
    Entry('btnLoad', '&Laden')], [TAtlasTextCheck.Accelerators], nil);
  Assert.IsTrue(TAtlasFormTexts.Matches(mEntries[2], '', False));
  Assert.IsFalse(TAtlasFormTexts.Matches(mEntries[2], '', True), 'nur mit Hinweisen');
  Assert.IsTrue(TAtlasFormTexts.Matches(mEntries[0], 'speich', True));
  Assert.IsTrue(TAtlasFormTexts.Matches(mEntries[1], 'TBUTTON', False), 'Klasse');
  Assert.IsTrue(TAtlasFormTexts.Matches(mEntries[1], 'caption', False), 'Eigenschaft');
  Assert.IsFalse(TAtlasFormTexts.Matches(mEntries[1], 'Laden', False));
end;

end.
