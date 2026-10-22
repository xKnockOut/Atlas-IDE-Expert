unit Atlas.Common.Lsp.Internals.Namespaces.Tests;

// Namespaces der LSP-Features unter gemeinsamer Sperre (Code-Review A-03).

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
  Field, Value: TArray<string>;
begin
  Field := nil;
  TLspNamespaces.Write(Field, ['System', 'Vcl']);
  Value := TLspNamespaces.Read(Field);
  Assert.AreEqual(2, Integer(Length(Value)));
  Assert.AreEqual('System', Value[0]);
  Assert.AreEqual('Vcl', Value[1]);
end;

procedure TLspNamespacesTests.ParallelReadAndWriteKeepArraysIntact;
const
  Rounds = 200000;
var
  Field, Value: TArray<string>;
  Writer: TThread;
  Done: Boolean;
  Bad: Integer;
begin
  Field := ['A', 'B'];
  Done := False;
  Bad := 0;
  Writer := TThread.CreateAnonymousThread(
    procedure
    var
      Index: Integer;
    begin
      for Index := 1 to Rounds do
        if Odd(Index) then
          TLspNamespaces.Write(Field, ['C'])
        else
          TLspNamespaces.Write(Field, ['A', 'B']);
      Done := True;
    end);
  Writer.FreeOnTerminate := False;
  try
    Writer.Start;
    repeat
      Value := TLspNamespaces.Read(Field);
      if Length(Value) = 1 then
      begin
        if Value[0] <> 'C' then
          Inc(Bad);
      end
      else if (Length(Value) <> 2) or (Value[0] <> 'A') or (Value[1] <> 'B') then
        Inc(Bad);
    until Done;
  finally
    Writer.WaitFor;
    Writer.Free;
  end;
  Assert.AreEqual(0, Bad);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspNamespacesTests);

end.
