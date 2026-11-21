unit Atlas.Core.Foundation.Calls.Tests;

// Tests zu TAtlasCalls: gesetzte Rückrufe laufen, nicht gesetzte nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCallsTests = class
  public
    [Test]
    procedure CallRunsAssignedProc;
    [Test]
    procedure CallWithoutProcDoesNothing;
    [Test]
    procedure SendPassesText;
    [Test]
    procedure SendWithoutSinkDoesNothing;
    /// <summary>ShowSource zeigt erst den Inhalt, meldet dann Shown; ohne Quelle nur den Inhalt.</summary>
    [Test]
    procedure ShowSourceUpdatesThenTellsSource;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Foundation.Calls,
  Atlas.Core.Foundation.Contract;

type
  /// <summary>Schreibt Shown ins Protokoll des Tests.</summary>
  TShownProbe = class(TInterfacedObject, IAtlasShownSource)
  private
    FLog: TStringBuilder;
  public
    constructor Create(ALog: TStringBuilder);
    procedure Shown;
  end;

procedure TAtlasCallsTests.CallRunsAssignedProc;
var
  mCount: Integer;
begin
  mCount := 0;
  TAtlasCalls.Call(
    procedure
    begin
      Inc(mCount);
    end);
  Assert.AreEqual(1, mCount);
end;

procedure TAtlasCallsTests.CallWithoutProcDoesNothing;
var
  mProc: TProc;
begin
  mProc := nil;
  TAtlasCalls.Call(mProc);
  // Ohne Rückruf keine Ausnahme. Kein Assert.Pass: Der Leckmonitor zählt dessen Meldung als Leck.
  Assert.IsFalse(Assigned(mProc));
end;

procedure TAtlasCallsTests.SendPassesText;
var
  mText: string;
begin
  mText := '';
  TAtlasCalls.Send(
    procedure(AText: string)
    begin
      mText := mText + AText + ';';
    end, 'Größe');
  Assert.AreEqual('Größe;', mText);
  mText := '';
end;

procedure TAtlasCallsTests.SendWithoutSinkDoesNothing;
var
  mSink: TProc<string>;
begin
  mSink := nil;
  TAtlasCalls.Send(mSink, 'x');
  // Ohne Meldungsziel keine Ausnahme. Kein Assert.Pass: Der Leckmonitor zählt dessen Meldung als Leck.
  Assert.IsFalse(Assigned(mSink));
end;

constructor TShownProbe.Create(ALog: TStringBuilder);
begin
  inherited Create;
  FLog := ALog;
end;

procedure TShownProbe.Shown;
begin
  FLog.Append('s');
end;

procedure TAtlasCallsTests.ShowSourceUpdatesThenTellsSource;
var
  mLog: TStringBuilder;
  mSource: IAtlasShownSource;
  mUpdate: TProc;
begin
  mLog := TStringBuilder.Create;
  try
    mUpdate :=
      procedure
      begin
        mLog.Append('u');
      end;
    mSource := TShownProbe.Create(mLog);
    TAtlasCalls.ShowSource(mSource, mUpdate);
    mSource := nil;
    TAtlasCalls.ShowSource(mSource, mUpdate);
    Assert.AreEqual('usu', mLog.ToString);
    mUpdate := nil;
  finally
    mLog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallsTests);

end.
