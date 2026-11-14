unit Atlas.Common.Lsp.Internals.Namespaces.Tests;

// Namespaces der LSP-Features unter gemeinsamer Sperre.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspNamespacesTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ReadReturnsWrittenValue;
    /// <summary>Ein Thread ersetzt fortlaufend, ein anderer liest: kein zerrissenes Array, keine
    /// Zugriffsverletzung.</summary>
    [Test]
    procedure ParallelReadAndWriteKeepArraysIntact;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Lsp.Internals.Namespaces;

{ TLspNamespacesTests }

procedure TLspNamespacesTests.WarmUpFirstUse;
begin
  ReadReturnsWrittenValue;
end;

procedure TLspNamespacesTests.ReadReturnsWrittenValue;
var
  mField, mValue: TArray<string>;
begin
  mField := nil;
  TLspNamespaces.Write(mField, ['System', 'Vcl']);
  mValue := TLspNamespaces.Read(mField);
  Assert.AreEqual(2, Integer(Length(mValue)));
  Assert.AreEqual('System', mValue[0]);
  Assert.AreEqual('Vcl', mValue[1]);
end;

procedure TLspNamespacesTests.ParallelReadAndWriteKeepArraysIntact;
const
  cRounds = 200000;
var
  mField, mValue: TArray<string>;
  mWriter: TThread;
  mDone: Boolean;
  mBad: Integer;
begin
  mField := ['A', 'B'];
  mDone := False;
  mBad := 0;
  mWriter := TThread.CreateAnonymousThread(
    procedure
    var
      Index: Integer;
    begin
      for Index := 1 to cRounds do
      begin
        if Odd(Index) then
        begin
          TLspNamespaces.Write(mField, ['C']);
        end
        else
        begin
          TLspNamespaces.Write(mField, ['A', 'B']);
        end;
      end;
      mDone := True;
    end);
  mWriter.FreeOnTerminate := False;
  try
    mWriter.Start;
    repeat
      mValue := TLspNamespaces.Read(mField);
      if Length(mValue) = 1 then
      begin
        if mValue[0] <> 'C' then
        begin
          Inc(mBad);
        end;
      end
      else if (Length(mValue) <> 2) or (mValue[0] <> 'A') or (mValue[1] <> 'B') then
      begin
        Inc(mBad);
      end;
    until mDone;
  finally
    mWriter.WaitFor;
    mWriter.Free;
  end;
  Assert.AreEqual(0, mBad);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspNamespacesTests);

end.
