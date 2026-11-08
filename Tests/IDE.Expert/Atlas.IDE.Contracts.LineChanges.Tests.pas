unit Atlas.IDE.Contracts.LineChanges.Tests;

// Vertrag der Änderungsmarken (#1905): Null-Objekt ohne Modul, angemeldete Marken, Haken des Trackers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineChangeMarksTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutModuleNothingHappens;
    [Test]
    procedure BoundMarksAnswer;
    [Test]
    procedure HooksReachBoundMarks;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Editor.LineChanges,
  Atlas.IDE.Contracts.LineChanges;

type
  TFakeMarks = class(TInterfacedObject, IAtlasLineChanges)
  public
    Steps: Integer;
    HookCalls: Integer;
    function Enabled: Boolean;
    procedure GoToChange(AForward: Boolean);
    function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList; out ALineCount: Integer): Boolean;
    function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
    procedure RefreshBlameTip;
    procedure HideBlameTip;
    procedure BlameHooksChanged;
  end;

function TFakeMarks.Enabled: Boolean;
begin
  Result := True;
end;

procedure TFakeMarks.GoToChange(AForward: Boolean);
begin
  Inc(Steps);
end;

function TFakeMarks.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
begin
  AChanges := nil;
  ALineCount := 7;
  Result := True;
end;

function TFakeMarks.BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
begin
  ACommit := Default(TAtlasBlameCommit);
  ACommit.Revision := 'abc';
  Result := True;
end;

procedure TFakeMarks.RefreshBlameTip;
begin
end;

procedure TFakeMarks.HideBlameTip;
begin
end;

procedure TFakeMarks.BlameHooksChanged;
begin
  Inc(HookCalls);
end;

procedure TAtlasLineChangeMarksTests.TearDown;
begin
  TAtlasLineChangeMarks.Bind(nil);
  TAtlasLineChangeMarks.SetBlameHooks(Default(TAtlasBlameHooks));
end;

procedure TAtlasLineChangeMarksTests.WithoutModuleNothingHappens;
var
  mChanges: TAtlasLineChangeList;
  mLines: Integer;
  mCommit: TAtlasBlameCommit;
begin
  Assert.IsFalse(TAtlasLineChangeMarks.Available);
  Assert.IsFalse(TAtlasLineChangeMarks.Current.Enabled, 'ohne Modul keine Marken');
  TAtlasLineChangeMarks.Current.GoToChange(True);
  Assert.IsFalse(TAtlasLineChangeMarks.Current.Snapshot('a.pas', mChanges, mLines));
  Assert.AreEqual(0, mLines);
  Assert.IsFalse(TAtlasLineChangeMarks.Current.BlameAt(0, 1, 1, mCommit));
end;

procedure TAtlasLineChangeMarksTests.BoundMarksAnswer;
var
  mFake: TFakeMarks;
  mChanges: TAtlasLineChangeList;
  mLines: Integer;
  mCommit: TAtlasBlameCommit;
begin
  mFake := TFakeMarks.Create;
  TAtlasLineChangeMarks.Bind(mFake);
  Assert.IsTrue(TAtlasLineChangeMarks.Available);
  Assert.IsTrue(TAtlasLineChangeMarks.Current.Enabled);
  TAtlasLineChangeMarks.Current.GoToChange(False);
  Assert.AreEqual(1, mFake.Steps);
  Assert.IsTrue(TAtlasLineChangeMarks.Current.Snapshot('a.pas', mChanges, mLines));
  Assert.AreEqual(7, mLines);
  Assert.IsTrue(TAtlasLineChangeMarks.Current.BlameAt(0, 1, 1, mCommit));
  Assert.AreEqual('abc', mCommit.Revision);
end;

procedure TAtlasLineChangeMarksTests.HooksReachBoundMarks;
var
  mFake: TFakeMarks;
  mHooks: TAtlasBlameHooks;
begin
  // Haken vor dem Modul: liegen bei Base und sind da, sobald das Modul läuft.
  mHooks := Default(TAtlasBlameHooks);
  mHooks.Suffix :=
    function(AMessage: string): string
    begin
      Result := ' · ATL-1';
    end;
  TAtlasLineChangeMarks.SetBlameHooks(mHooks);
  mFake := TFakeMarks.Create;
  TAtlasLineChangeMarks.Bind(mFake);
  Assert.AreEqual(' · ATL-1', TAtlasLineChangeMarks.BlameHooks.Suffix('x'));
  Assert.AreEqual(0, mFake.HookCalls);
  // Neue Haken melden die Marken.
  TAtlasLineChangeMarks.SetBlameHooks(Default(TAtlasBlameHooks));
  Assert.AreEqual(1, mFake.HookCalls);
  Assert.IsFalse(Assigned(TAtlasLineChangeMarks.BlameHooks.Suffix));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineChangeMarksTests);

end.
