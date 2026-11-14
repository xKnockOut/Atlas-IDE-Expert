unit Atlas.Core.Editor.LensAsk.Tests;

// Tests der ausstehenden Frage einer Code Lens im Hintergrund: Die Antwort
// erreicht den Besitzer nur für die jüngste Frage, nicht nach Drop oder Close;
// ohne Antwort zählt sie als Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLensAskTests = class
  public
    [Test]
    procedure OnlyLatestAskIsAnswered;
    [Test]
    procedure DropDiscardsPendingAnswer;
    [Test]
    procedure CloseDiscardsPendingAnswer;
    [Test]
    procedure AnsweredWithoutValueIsFailure;
    [Test]
    procedure DropWithoutAskKeepsNextAsk;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.LensAsk;

type
  TAnswerLog = class
  public
    Calls: Integer;
    Last: TJSONValue;
  end;

/// <summary>Rückruf, der jede Antwort in ALog zählt.</summary>
function Logging(ALog: TAnswerLog): TProc<TJSONValue>;
begin
  Result :=
    procedure(AAnswer: TJSONValue)
    begin
      Inc(ALog.Calls);
      ALog.Last := AAnswer;
    end;
end;

procedure TAtlasLensAskTests.OnlyLatestAskIsAnswered;
var
  mAsk: TAtlasLensAsk;
  mLog: TAnswerLog;
  mFirst, mSecond: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mAsk := Default(TAtlasLensAsk);
  mLog := TAnswerLog.Create;
  mValue := TJSONObject.Create;
  try
    mFirst := mAsk.Start('A.pas', 'alt', TAtlasFeature.CodeLens, Logging(mLog));
    mSecond := mAsk.Start('A.pas', 'neu', TAtlasFeature.CodeLens, Logging(mLog));
    Assert.IsTrue(mAsk.Waiting, 'Antwort steht aus');
    Assert.AreEqual('neu', mAsk.Text, 'Stand der jüngsten Frage');
    mFirst(mValue);
    Assert.AreEqual(0, mLog.Calls, 'Antwort einer älteren Frage gilt nicht');
    mSecond(mValue);
    Assert.AreEqual(1, mLog.Calls, 'Antwort der jüngsten Frage kommt an');
    Assert.AreSame(mValue, mLog.Last, 'Wert unverändert weitergegeben');
  finally
    mAsk.Close;
    mFirst := nil;
    mSecond := nil;
    mValue.Free;
    mLog.Free;
  end;
end;

procedure TAtlasLensAskTests.DropDiscardsPendingAnswer;
var
  mAsk: TAtlasLensAsk;
  mLog: TAnswerLog;
  mDone: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mAsk := Default(TAtlasLensAsk);
  mLog := TAnswerLog.Create;
  mValue := TJSONObject.Create;
  try
    mDone := mAsk.Start('A.pas', 'a', TAtlasFeature.CodeLens, Logging(mLog));
    mAsk.Drop;
    Assert.IsFalse(mAsk.Waiting, 'nach Drop steht nichts mehr aus');
    mDone(mValue);
    Assert.AreEqual(0, mLog.Calls, 'verworfene Antwort erreicht nichts');
  finally
    mAsk.Close;
    mDone := nil;
    mValue.Free;
    mLog.Free;
  end;
end;

procedure TAtlasLensAskTests.CloseDiscardsPendingAnswer;
var
  mAsk: TAtlasLensAsk;
  mLog: TAnswerLog;
  mDone: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mAsk := Default(TAtlasLensAsk);
  mLog := TAnswerLog.Create;
  mValue := TJSONObject.Create;
  try
    mDone := mAsk.Start('A.pas', 'a', TAtlasFeature.CodeLens, Logging(mLog));
    mAsk.Close;
    mDone(mValue);
    Assert.AreEqual(0, mLog.Calls, 'nach dem Ende des Besitzers kommt nichts an');
    Assert.IsFalse(mAsk.Waiting, 'nach Close steht nichts mehr aus');
  finally
    mDone := nil;
    mValue.Free;
    mLog.Free;
  end;
end;

procedure TAtlasLensAskTests.AnsweredWithoutValueIsFailure;
var
  mAsk: TAtlasLensAsk;
  mDone: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mAsk := Default(TAtlasLensAsk);
  mValue := TJSONObject.Create;
  try
    mDone := mAsk.Start('A.pas', 'a', TAtlasFeature.CodeLens, nil);
    Assert.IsTrue(Assigned(mDone), 'Rückruf für den Befehl');
    Assert.IsFalse(mAsk.Answered(nil), 'ohne Antwort: Fehler oder Zeitlimit');
    Assert.IsFalse(mAsk.Waiting, 'auch ohne Antwort steht nichts mehr aus');
    mDone := mAsk.Start('A.pas', 'b', TAtlasFeature.CodeLens, nil);
    Assert.IsTrue(Assigned(mDone), 'Rückruf für die zweite Frage');
    Assert.IsTrue(mAsk.Answered(mValue), 'mit Antwort');
    Assert.AreEqual('A.pas', mAsk.FileName, 'Datei der Frage bleibt');
    Assert.AreEqual('b', mAsk.Text, 'Text der Frage bleibt');
  finally
    mAsk.Close;
    mDone := nil;
    mValue.Free;
  end;
end;

procedure TAtlasLensAskTests.DropWithoutAskKeepsNextAsk;
var
  mAsk: TAtlasLensAsk;
  mLog: TAnswerLog;
  mDone: TProc<TJSONValue>;
  mValue: TJSONValue;
begin
  mAsk := Default(TAtlasLensAsk);
  mLog := TAnswerLog.Create;
  mValue := TJSONObject.Create;
  try
    mAsk.Drop;
    mDone := mAsk.Start('A.pas', 'a', TAtlasFeature.CodeLens, Logging(mLog));
    mDone(mValue);
    Assert.AreEqual(1, mLog.Calls, 'Drop ohne ausstehende Frage stört die nächste nicht');
  finally
    mAsk.Close;
    mDone := nil;
    mValue.Free;
    mLog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLensAskTests);

end.
