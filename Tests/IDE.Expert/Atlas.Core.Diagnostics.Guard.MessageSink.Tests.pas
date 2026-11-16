unit Atlas.Core.Diagnostics.Guard.MessageSink.Tests;

// Empfänger einer Meldungszeile, der fehlen darf (TAtlasMessageSink in Atlas.Core.Diagnostics.Guard).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMessageSinkTests = class
  private
    FLines: TArray<string>;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SaysToTheTarget;
    [Test]
    procedure WithoutTargetNothingHappens;
    [Test]
    procedure EmptyTextIsNotSaid;
    [Test]
    procedure ClearReleasesTheTarget;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasMessageSinkTests }

procedure TAtlasMessageSinkTests.TearDown;
begin
  FLines := nil;
end;

function Collect(ATests: TAtlasMessageSinkTests): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      ATests.FLines := ATests.FLines + [AText];
    end;
end;

procedure TAtlasMessageSinkTests.SaysToTheTarget;
var
  mSink: TAtlasMessageSink;
begin
  mSink := TAtlasMessageSink.Create(Collect(Self));
  mSink.Say('eins');
  mSink.Say('zwei');
  Assert.AreEqual(2, Integer(Length(FLines)));
  Assert.AreEqual('eins', FLines[0]);
  Assert.AreEqual('zwei', FLines[1]);
end;

procedure TAtlasMessageSinkTests.WithoutTargetNothingHappens;
var
  mSink: TAtlasMessageSink;
begin
  mSink := TAtlasMessageSink.Create(nil);
  mSink.Say('eins');
  mSink := Default(TAtlasMessageSink);
  mSink.Say('zwei');
  Assert.AreEqual(0, Integer(Length(FLines)));
end;

procedure TAtlasMessageSinkTests.EmptyTextIsNotSaid;
var
  mSink: TAtlasMessageSink;
begin
  mSink := TAtlasMessageSink.Create(Collect(Self));
  mSink.Say('');
  Assert.AreEqual(0, Integer(Length(FLines)));
end;

procedure TAtlasMessageSinkTests.ClearReleasesTheTarget;
var
  mSink: TAtlasMessageSink;
begin
  mSink := TAtlasMessageSink.Create(Collect(Self));
  mSink.Clear;
  mSink.Say('eins');
  Assert.AreEqual(0, Integer(Length(FLines)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMessageSinkTests);

end.
