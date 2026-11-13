unit Atlas.Core.Rules.Ownership.Tests;

// Tests für die Marke „Wer gibt das frei?“ (#1877): Antwort lesen, Ton je Art, nur Problemfälle, Zeile nur mit
// gleichem Text, Beschriftung mit Behälter, Tooltip mit Weg und Sprung, wann neu gefragt wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasOwnershipMarksTests = class
  public
    [Test]
    procedure ParseReadsSites;
    [Test]
    procedure ParseSkipsUnknownKindsAndBadAnswers;
    [Test]
    procedure ToneFollowsKind;
    [Test]
    procedure OnlyProblemsDropsGreen;
    [Test]
    procedure AtLineNeedsSameText;
    [Test]
    procedure CaptionNamesLineAndContainer;
    [Test]
    procedure LineJoinsMarksWithStrongestTone;
    [Test]
    procedure TipExplainsWayAndJump;
    [Test]
    procedure FetchAfterNewCheckOrOtherFile;
    [Test]
    procedure ArgumentsCarryUri;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Rules.Ownership;

const
  cAnswer = '{"uri":"file:///C:/P/U.pas","sites":[' +
    '{"line":16,"character":12,"endLine":16,"endCharacter":31,"lineText":"  FNamen := TStringList.Create;",' +
    '"className":"TStringList","target":"FNamen","kind":"destroy","freeLine":21,"detail":"Destroy",' +
    '"container":"ownsElements","containerOwner":""},' +
    '{"line":17,"character":10,"endLine":17,"endCharacter":29,"lineText":"  FAlt := TStringList.Create;",' +
    '"className":"TStringList","target":"FAlt","kind":"never","detail":"","rule":"field-not-freed",' +
    '"message":"FAlt wird nie freigegeben"},' +
    '{"line":30,"character":2,"endLine":30,"endCharacter":20,"lineText":"x","className":"TFoo","target":"",' +
    '"kind":"something","detail":""}]}';

function Texts: TAtlasOwnershipTexts;
begin
  Result := Default(TAtlasOwnershipTexts);
  Result.Labels[TAtlasOwnershipKind.InDestroy] := 'frei in Destroy, Z. %d';
  Result.Labels[TAtlasOwnershipKind.InFinally] := 'frei in finally, Z. %d';
  Result.Labels[TAtlasOwnershipKind.Freed] := 'frei, Z. %d';
  Result.Labels[TAtlasOwnershipKind.Owner] := 'Owner %s';
  Result.Labels[TAtlasOwnershipKind.OwnedList] := 'gehört %s';
  Result.Labels[TAtlasOwnershipKind.RefCounted] := 'Referenzzählung';
  Result.Labels[TAtlasOwnershipKind.Returned] := 'an Aufrufer zurückgegeben';
  Result.Labels[TAtlasOwnershipKind.Passed] := 'weitergegeben an %s';
  Result.Labels[TAtlasOwnershipKind.Unknown] := 'unklar';
  Result.Labels[TAtlasOwnershipKind.Never] := 'nie freigegeben';
  Result.FreedIn := 'frei in %s, Z. %d';
  Result.PassedSomewhere := 'weitergegeben';
  Result.Reasons[TAtlasOwnershipKind.InDestroy] := 'Destructor gibt frei.';
  Result.Reasons[TAtlasOwnershipKind.Never] := 'Regel %s meldet:';
  Result.ContainerLabels[TAtlasOwnershipContainer.OwnsElements] := ' · besitzt Elemente';
  Result.ContainerLabels[TAtlasOwnershipContainer.ElementsOwned] := ' · Elemente gehören %s';
  Result.ContainerReasons[TAtlasOwnershipContainer.OwnsElements] := 'Liste gibt Elemente frei.';
  Result.ContainerReasons[TAtlasOwnershipContainer.ElementsOwned] := 'Elemente gehören %s.';
  Result.Title := 'Wer gibt %s frei?';
  Result.Jump := 'Klick: Zeile %d';
end;

function Mark(AKind: TAtlasOwnershipKind): TAtlasOwnershipMark;
begin
  Result := Default(TAtlasOwnershipMark);
  Result.Kind := AKind;
  Result.FreeLine := -1;
  Result.Line := 3;
  Result.LineText := '  X := TFoo.Create;';
  Result.ClassName := 'TFoo';
end;

procedure TAtlasOwnershipMarksTests.ParseReadsSites;
var
  mMarks: TArray<TAtlasOwnershipMark>;
begin
  mMarks := TAtlasOwnershipMarks.Parse(cAnswer);
  Assert.AreEqual(2, Integer(Length(mMarks)));
  Assert.AreEqual(16, mMarks[0].Line);
  Assert.AreEqual(12, mMarks[0].Character);
  Assert.AreEqual('  FNamen := TStringList.Create;', mMarks[0].LineText);
  Assert.AreEqual('FNamen', mMarks[0].Target);
  Assert.IsTrue(mMarks[0].Kind = TAtlasOwnershipKind.InDestroy);
  Assert.AreEqual(21, mMarks[0].FreeLine);
  Assert.IsTrue(mMarks[0].Container = TAtlasOwnershipContainer.OwnsElements);
  Assert.IsTrue(mMarks[1].Kind = TAtlasOwnershipKind.Never);
  Assert.AreEqual(-1, mMarks[1].FreeLine);
  Assert.AreEqual('field-not-freed', mMarks[1].Rule);
  Assert.AreEqual('FAlt wird nie freigegeben', mMarks[1].Message);
end;

procedure TAtlasOwnershipMarksTests.ParseSkipsUnknownKindsAndBadAnswers;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.Parse(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.Parse('kein JSON'))));
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.Parse('{"uri":"x"}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.Parse('{"sites":[{"kind":"destroy"}]}'))),
    'ohne Zeile');
end;

procedure TAtlasOwnershipMarksTests.ToneFollowsKind;
var
  mKind: TAtlasOwnershipKind;
begin
  for mKind in [TAtlasOwnershipKind.InDestroy, TAtlasOwnershipKind.InFinally, TAtlasOwnershipKind.Owner,
    TAtlasOwnershipKind.OwnedList, TAtlasOwnershipKind.RefCounted] do
  begin
    Assert.IsTrue(Mark(mKind).Tone = TAtlasOwnershipTone.Safe, TAtlasOwnershipMarks.cKindNames[mKind]);
  end;
  for mKind in [TAtlasOwnershipKind.Freed, TAtlasOwnershipKind.Returned, TAtlasOwnershipKind.Passed,
    TAtlasOwnershipKind.Unknown] do
  begin
    Assert.IsTrue(Mark(mKind).Tone = TAtlasOwnershipTone.Elsewhere, TAtlasOwnershipMarks.cKindNames[mKind]);
  end;
  Assert.IsTrue(Mark(TAtlasOwnershipKind.Never).Tone = TAtlasOwnershipTone.Never);
end;

procedure TAtlasOwnershipMarksTests.OnlyProblemsDropsGreen;
var
  mMarks: TArray<TAtlasOwnershipMark>;
begin
  mMarks := TAtlasOwnershipMarks.Parse(cAnswer);
  Assert.AreEqual(2, Integer(Length(TAtlasOwnershipMarks.Visible(mMarks, False))));
  mMarks := TAtlasOwnershipMarks.Visible(mMarks, True);
  Assert.AreEqual(1, Integer(Length(mMarks)));
  Assert.AreEqual('FAlt', mMarks[0].Target);
end;

procedure TAtlasOwnershipMarksTests.AtLineNeedsSameText;
var
  mMarks: TArray<TAtlasOwnershipMark>;
begin
  mMarks := TAtlasOwnershipMarks.Parse(cAnswer);
  Assert.AreEqual(1, Integer(Length(TAtlasOwnershipMarks.AtLine(mMarks, 16, '  FNamen := TStringList.Create;  '))),
    'Leerraum am Ende zählt nicht');
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.AtLine(mMarks, 16, '  FNamen := nil;'))),
    'Zeile geändert');
  Assert.AreEqual(0, Integer(Length(TAtlasOwnershipMarks.AtLine(mMarks, 15, '  FNamen := TStringList.Create;'))),
    'andere Zeile');
end;

procedure TAtlasOwnershipMarksTests.CaptionNamesLineAndContainer;
var
  mMark: TAtlasOwnershipMark;
begin
  mMark := Mark(TAtlasOwnershipKind.InDestroy);
  mMark.FreeLine := 47;
  Assert.AreEqual('frei in Destroy, Z. 48', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Kind := TAtlasOwnershipKind.Freed;
  mMark.Detail := 'Clear';
  Assert.AreEqual('frei in Clear, Z. 48', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Detail := '';
  Assert.AreEqual('frei, Z. 48', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Kind := TAtlasOwnershipKind.Passed;
  Assert.AreEqual('weitergegeben', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Detail := 'Registry.Add';
  Assert.AreEqual('weitergegeben an Registry.Add', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Kind := TAtlasOwnershipKind.Owner;
  mMark.Detail := 'Self';
  Assert.AreEqual('Owner Self', TAtlasOwnershipMarks.Caption(mMark, Texts));
  mMark.Kind := TAtlasOwnershipKind.OwnedList;
  mMark.Detail := 'FItems';
  mMark.Container := TAtlasOwnershipContainer.ElementsOwned;
  mMark.ContainerOwner := 'FAlle';
  Assert.AreEqual('gehört FItems · Elemente gehören FAlle', TAtlasOwnershipMarks.Caption(mMark, Texts));
end;

procedure TAtlasOwnershipMarksTests.LineJoinsMarksWithStrongestTone;
var
  mMarks: TArray<TAtlasOwnershipMark>;
begin
  mMarks := [Mark(TAtlasOwnershipKind.RefCounted), Mark(TAtlasOwnershipKind.Returned)];
  Assert.AreEqual('Referenzzählung | an Aufrufer zurückgegeben', TAtlasOwnershipMarks.LineCaption(mMarks, Texts));
  Assert.IsTrue(TAtlasOwnershipMarks.LineTone(mMarks) = TAtlasOwnershipTone.Elsewhere);
  mMarks := mMarks + [Mark(TAtlasOwnershipKind.Never)];
  Assert.IsTrue(TAtlasOwnershipMarks.LineTone(mMarks) = TAtlasOwnershipTone.Never);
  Assert.IsTrue(TAtlasOwnershipMarks.LineTone(nil) = TAtlasOwnershipTone.Safe);
  Assert.AreEqual(-1, TAtlasOwnershipMarks.JumpLine(mMarks));
  mMarks[1].FreeLine := 9;
  Assert.AreEqual(9, TAtlasOwnershipMarks.JumpLine(mMarks));
end;

procedure TAtlasOwnershipMarksTests.TipExplainsWayAndJump;
var
  mMarks: TArray<TAtlasOwnershipMark>;
  mText: string;
begin
  mMarks := TAtlasOwnershipMarks.Parse(cAnswer);
  Assert.AreEqual('Wer gibt FNamen frei?', TAtlasOwnershipMarks.TipTitle(mMarks, Texts));
  mText := TAtlasOwnershipMarks.TipText([mMarks[0]], Texts);
  Assert.IsTrue(mText.StartsWith('TStringList: frei in Destroy, Z. 22 · besitzt Elemente'), mText);
  Assert.IsTrue(mText.Contains('Destructor gibt frei.'), mText);
  Assert.IsTrue(mText.Contains('Liste gibt Elemente frei.'), mText);
  Assert.IsTrue(mText.EndsWith('Klick: Zeile 22'), mText);
  mText := TAtlasOwnershipMarks.TipText([mMarks[1]], Texts);
  Assert.IsTrue(mText.Contains('Regel field-not-freed meldet:' + sLineBreak + 'FAlt wird nie freigegeben'), mText);
  Assert.IsFalse(mText.Contains('Klick'), 'ohne Freigabe kein Sprung');
  mMarks[1].Target := '';
  Assert.AreEqual('Wer gibt TStringList frei?', TAtlasOwnershipMarks.TipTitle([mMarks[1]], Texts));
  Assert.AreEqual('', TAtlasOwnershipMarks.TipTitle(nil, Texts));
end;

procedure TAtlasOwnershipMarksTests.FetchAfterNewCheckOrOtherFile;
var
  mFetch: TAtlasOwnershipFetch;
begin
  mFetch := Default(TAtlasOwnershipFetch);
  Assert.IsFalse(mFetch.Due('', '', 0), 'ohne Datei');
  Assert.IsTrue(mFetch.Due('C:\P\U.pas', '', 0), 'erste Datei');
  mFetch.Asked('C:\P\U.pas', '', 0);
  Assert.IsFalse(mFetch.Due('C:\P\U.pas', '', 0), 'gleicher Stand');
  Assert.IsTrue(mFetch.Due('C:\P\U.pas', 'c:\p\u.pas', 10), 'neue Prüfung');
  mFetch.Asked('C:\P\U.pas', 'c:\p\u.pas', 10);
  Assert.IsFalse(mFetch.Due('C:\P\U.pas', 'c:\p\u.pas', 10), 'gefragt');
  Assert.IsFalse(mFetch.Due('C:\P\U.pas', 'C:\P\V.pas', 20), 'Prüfung einer anderen Datei');
  Assert.IsTrue(mFetch.Due('C:\P\V.pas', 'C:\P\V.pas', 20), 'andere Datei vorn');
  mFetch.Reset;
  Assert.IsTrue(mFetch.Due('C:\P\U.pas', 'c:\p\u.pas', 10), 'nach Reset');
end;

procedure TAtlasOwnershipMarksTests.ArgumentsCarryUri;
var
  mValue: TJSONValue;
begin
  // Schrägstriche darf ToJSON maskieren; es zählt der gelesene Wert.
  mValue := TJSONObject.ParseJSONValue(TAtlasOwnershipMarks.Arguments('file:///C:/P/%C3%9Cber.pas'));
  try
    Assert.IsTrue(mValue is TJSONArray);
    Assert.AreEqual(1, TJSONArray(mValue).Count);
    Assert.AreEqual('file:///C:/P/%C3%9Cber.pas', TJSONArray(mValue).Items[0].Value);
  finally
    mValue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOwnershipMarksTests);

end.
