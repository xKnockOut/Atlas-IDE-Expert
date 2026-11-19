unit Atlas.Core.Tracker.KnownErrors.Tests;

// Tests der bekannten Fehler beim Exception-Halt (#2460) ohne VCL: Signatur (Zahlen, Adressen, Pfade und
// Anführungsinhalte entfernt, eigene Methode ohne Unit), Suchtexte, Rangfolge, Zwischenspeicher, Kommentartext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasKnownErrorsTests = class
  public
    [Test]
    procedure MessageWithoutNumbersAddressesPaths;
    [Test]
    procedure MessageWithoutQuotedParts;
    [Test]
    procedure MethodWithoutUnit;
    [Test]
    procedure SignatureFromTopOwnMethod;
    [Test]
    procedure QueriesInRankOrder;
    [Test]
    procedure NoQueryWithClassOnly;
    [Test]
    procedure RankKeepsOrderAndDropsDuplicates;
    [Test]
    procedure RankMarksResolved;
    [Test]
    procedure CacheBusyThenDone;
    [Test]
    procedure CommentNamesExceptionPlaceAndStack;
    [Test]
    procedure TitleAndBranch;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.KnownErrors.Contract,
  Atlas.Core.Tracker.KnownErrors;

function Halt: TAtlasDebugExceptionReport;
begin
  Result := Default(TAtlasDebugExceptionReport);
  Result.Project := 'C:\Src\Kasse.dproj';
  Result.ExceptionClass := 'EConvertError';
  Result.ExceptionMessage := '''12,5 kg'' is not a valid floating point value';
  Result.OwnMethods := TArray<string>.Create('Kasse.Gewicht.TGewicht.Parse', 'Kasse.Main.TMainForm.ButtonClick');
  Result.OwnFrames := TArray<string>.Create('Kasse.Gewicht.TGewicht.Parse (Kasse.Gewicht.pas:42)',
    'Kasse.Main.TMainForm.ButtonClick (Kasse.Main.pas:88)');
  Result.FileName := 'C:\Src\Kasse.Gewicht.pas';
  Result.Line := 42;
end;

function Issue(const AKey, AState: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Title := 'Absturz in ' + AKey;
  Result.State := AState;
  Result.Assignee := 'Kim';
end;

{ TAtlasKnownErrorsTests }

procedure TAtlasKnownErrorsTests.MessageWithoutNumbersAddressesPaths;
begin
  Assert.AreEqual('Access violation at address in module. Read of address',
    TAtlasKnownErrorSignature.CleanMessage(
    'Access violation at address 0040A1B2 in module ''Kasse.exe''. Read of address 00000000'));
  Assert.AreEqual('Cannot open file Zugriff verweigert',
    TAtlasKnownErrorSignature.CleanMessage('Cannot open file C:\Daten\kunde7.csv. Zugriff verweigert'));
  Assert.AreEqual('List index out of bounds', TAtlasKnownErrorSignature.CleanMessage('List index out of bounds (5)'),
    'Zahl in Klammern');
  Assert.AreEqual('Fehler an', TAtlasKnownErrorSignature.CleanMessage('Fehler an $7FF6A0B1 /usr/lib/x.so'));
end;

procedure TAtlasKnownErrorsTests.MessageWithoutQuotedParts;
begin
  Assert.AreEqual('is not a valid floating point value',
    TAtlasKnownErrorSignature.CleanMessage('''12,5 kg'' is not a valid floating point value'));
  Assert.AreEqual('Kunde nicht gefunden', TAtlasKnownErrorSignature.CleanMessage('Kunde „Meier“ nicht gefunden'));
  Assert.AreEqual('Can''t do it', TAtlasKnownErrorSignature.CleanMessage('Can''t do it'),
    'Apostroph im Wort ist kein Anführungszeichen');
end;

procedure TAtlasKnownErrorsTests.MethodWithoutUnit;
begin
  Assert.AreEqual('TGewicht.Parse', TAtlasKnownErrorSignature.ShortMethod('Kasse.Gewicht.TGewicht.Parse'));
  Assert.AreEqual('DoIt', TAtlasKnownErrorSignature.ShortMethod('Unit1.DoIt'));
  Assert.AreEqual('TOuter.TInner.Run', TAtlasKnownErrorSignature.ShortMethod('Unit1.TOuter.TInner.Run'));
  Assert.AreEqual('', TAtlasKnownErrorSignature.ShortMethod(''));
end;

procedure TAtlasKnownErrorsTests.SignatureFromTopOwnMethod;
var
  mSignature: TAtlasKnownErrorSignature;
  mOther: TAtlasDebugExceptionReport;
begin
  mSignature := TAtlasKnownErrorSignature.FromReport(Halt);
  Assert.AreEqual('EConvertError', mSignature.ExceptionClass);
  Assert.AreEqual('TGewicht.Parse', mSignature.Method, 'oberste eigene Methode');
  Assert.AreEqual('is not a valid floating point value', mSignature.Message);
  // Andere Zahl im Anführungsteil, anderer Ort: dieselbe Signatur.
  mOther := Halt;
  mOther.ExceptionMessage := '''7 g'' is not a valid floating point value';
  mOther.Line := 43;
  Assert.AreEqual(mSignature.Key, TAtlasKnownErrorSignature.FromReport(mOther).Key);
  Assert.AreEqual(4, Integer(Length(mSignature.Words)));
  Assert.AreEqual('valid', mSignature.Words[0]);
end;

procedure TAtlasKnownErrorsTests.QueriesInRankOrder;
var
  mQueries: TArray<string>;
begin
  mQueries := TAtlasKnownErrorSearch.Queries(TAtlasKnownErrorSignature.FromReport(Halt));
  Assert.AreEqual(3, Integer(Length(mQueries)));
  Assert.AreEqual('"EConvertError" "TGewicht.Parse"', mQueries[0], 'Klasse und Methode');
  Assert.AreEqual('"EConvertError" valid floating point value', mQueries[1], 'Klasse und Meldung');
  Assert.AreEqual('"TGewicht.Parse"', mQueries[2], 'nur Methode');
end;

procedure TAtlasKnownErrorsTests.NoQueryWithClassOnly;
var
  mReport: TAtlasDebugExceptionReport;
begin
  mReport := Default(TAtlasDebugExceptionReport);
  mReport.ExceptionClass := 'EAbort';
  Assert.AreEqual(0, Integer(Length(TAtlasKnownErrorSearch.Queries(TAtlasKnownErrorSignature.FromReport(mReport)))));
  mReport.ExceptionClass := '';
  mReport.OwnMethods := TArray<string>.Create('Unit1.TFoo.Bar');
  Assert.AreEqual(0, Integer(Length(TAtlasKnownErrorSearch.Queries(TAtlasKnownErrorSignature.FromReport(mReport)))),
    'ohne Klasse keine Suche');
end;

procedure TAtlasKnownErrorsTests.RankKeepsOrderAndDropsDuplicates;
var
  mFound: TArray<TArray<TAtlasTrackerIssue>>;
  mErrors: TArray<TAtlasKnownError>;
begin
  mFound := [TArray<TAtlasTrackerIssue>.Create(Issue('ATL-2', 'Open')),
    TArray<TAtlasTrackerIssue>.Create(Issue('ATL-5', 'Open'), Issue('ATL-2', 'Open')),
    TArray<TAtlasTrackerIssue>.Create(Issue('ATL-7', 'Open'), Issue('ATL-8', 'Open'), Issue('ATL-9', 'Open'))];
  mErrors := TAtlasKnownErrorSearch.Rank(mFound, 'youtrack', nil);
  Assert.AreEqual(4, Integer(Length(mErrors)), 'höchstens vier');
  Assert.AreEqual('ATL-2', mErrors[0].Key, 'Klasse und Methode zuerst');
  Assert.AreEqual('ATL-5', mErrors[1].Key);
  Assert.AreEqual('ATL-7', mErrors[2].Key);
  Assert.AreEqual('ATL-8', mErrors[3].Key);
end;

procedure TAtlasKnownErrorsTests.RankMarksResolved;
var
  mErrors: TArray<TAtlasKnownError>;
begin
  mErrors := TAtlasKnownErrorSearch.Rank([TArray<TAtlasTrackerIssue>.Create(Issue('#3', 'closed'),
    Issue('#4', 'open'))], 'github', nil);
  Assert.IsTrue(mErrors[0].Resolved);
  Assert.IsFalse(mErrors[1].Resolved);
  Assert.AreEqual('Absturz in #3', mErrors[0].Title);
  Assert.AreEqual('closed', mErrors[0].State);
  Assert.AreEqual('Kim', mErrors[0].Assignee);
  mErrors := TAtlasKnownErrorSearch.Rank([TArray<TAtlasTrackerIssue>.Create(Issue('ATL-1', 'Abgenommen'))],
    'youtrack', TArray<string>.Create('Abgenommen'));
  Assert.IsTrue(mErrors[0].Resolved, 'Zielzustand aus issues.endStates');
end;

procedure TAtlasKnownErrorsTests.CacheBusyThenDone;
var
  mCache: TAtlasKnownErrorsCache;
  mErrors: TArray<TAtlasKnownError>;
  mError: TAtlasKnownError;
begin
  mCache := TAtlasKnownErrorsCache.Create;
  try
    Assert.AreEqual<TAtlasKnownErrorsState>(TAtlasKnownErrorsState.Off, mCache.StateOf('a', mErrors));
    mCache.Started('a');
    Assert.AreEqual<TAtlasKnownErrorsState>(TAtlasKnownErrorsState.Busy, mCache.StateOf('a', mErrors));
    mError := Default(TAtlasKnownError);
    mError.Key := '#1';
    mCache.Finished('a', [mError]);
    Assert.AreEqual<TAtlasKnownErrorsState>(TAtlasKnownErrorsState.Done, mCache.StateOf('a', mErrors));
    Assert.AreEqual('#1', mErrors[0].Key);
    mCache.Finished('b', nil);
    Assert.AreEqual<TAtlasKnownErrorsState>(TAtlasKnownErrorsState.Done, mCache.StateOf('b', mErrors),
      'ohne Netz: fertig ohne Treffer, keine neue Suche');
    Assert.AreEqual(0, Integer(Length(mErrors)));
  finally
    mCache.Free;
  end;
end;

procedure TAtlasKnownErrorsTests.CommentNamesExceptionPlaceAndStack;
var
  mLabels: TAtlasKnownErrorLabels;
  mText: string;
begin
  mLabels.Again := 'Wieder aufgetreten';
  mLabels.Location := 'Ort';
  mLabels.Stack := 'Aufrufstapel';
  mLabels.Branch := 'Branch';
  mText := TAtlasKnownErrorSearch.CommentText(Halt, mLabels, 'feature/7');
  Assert.IsTrue(mText.StartsWith('**Wieder aufgetreten**' + #10#10 + '`EConvertError`: ''12,5 kg'''), mText);
  Assert.IsTrue(Pos('Ort: `Kasse.Gewicht.pas:42`', mText) > 0, mText);
  Assert.IsTrue(Pos('Branch: `feature/7`', mText) > 0, mText);
  Assert.IsTrue(Pos('Aufrufstapel:' + #10 + '- `Kasse.Gewicht.TGewicht.Parse (Kasse.Gewicht.pas:42)`', mText) > 0,
    mText);
  Assert.AreEqual(0, Pos('C:\Src', mText), 'nur der Dateiname');
  Assert.IsFalse(TAtlasKnownErrorSearch.IssueText(Halt, mLabels, '').StartsWith('**'), 'ohne erste Zeile');
end;

procedure TAtlasKnownErrorsTests.TitleAndBranch;
begin
  Assert.AreEqual('EConvertError in TGewicht.Parse: is not a valid floating point value',
    TAtlasKnownErrorSearch.IssueTitle(Halt));
  Assert.AreEqual('feature/7', TAtlasKnownErrorSearch.BranchOfHead('ref: refs/heads/feature/7' + #10));
  Assert.AreEqual('0123abcd', TAtlasKnownErrorSearch.BranchOfHead('0123abcdef0123'));
end;

end.
