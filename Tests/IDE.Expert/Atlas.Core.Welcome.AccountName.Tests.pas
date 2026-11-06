unit Atlas.Core.Welcome.AccountName.Tests;

// Tests für den Anzeigenamen des Kontos im Kopf der Willkommensseite (2.0-stable: GetUserNameEx fragte bei jeder
// Änderung im Statusfeld im Hauptthread den Domänencontroller): Abfrage im Hintergrund, nur einmal, Meldung im
// Hauptthread, leerer Name ohne Meldung, keine Meldung nach der Freigabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeAccountNameTests = class
  public
    [Test]
    procedure NameComesFromBackgroundAndIsReported;
    [Test]
    procedure LookupRunsOnlyOnce;
    [Test]
    procedure EmptyNameIsNotReported;
    [Test]
    procedure NothingReportedAfterFree;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Welcome.AccountName;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

type
  /// <summary>Nachschlagen mit Zähler und Thread; Meldungen mit Zähler und Thread.</summary>
  TAccountProbe = class
  public
    Value: string;
    Lookups: Integer;
    LookupThread: TThreadID;
    Reports: Integer;
    ReportThread: TThreadID;
    Gate: TEvent;
    function Lookup: TFunc<string>;
    function Changed: TProc;
  end;

function TAccountProbe.Lookup: TFunc<string>;
begin
  Result :=
    function: string
    begin
      if Gate <> nil then
      begin
        Gate.WaitFor(5000);
      end;
      TInterlocked.Increment(Lookups);
      LookupThread := TThread.CurrentThread.ThreadID;
      Result := Value;
    end;
end;

function TAccountProbe.Changed: TProc;
begin
  Result :=
    procedure
    begin
      Inc(Reports);
      ReportThread := TThread.CurrentThread.ThreadID;
    end;
end;

/// <summary>Bedingung: Die Abfrage lief mindestens einmal.</summary>
function Looked(AProbe: TAccountProbe): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AProbe.Lookups > 0;
    end;
end;

/// <summary>Bedingung: Es wurde mindestens einmal gemeldet.</summary>
function Reported(AProbe: TAccountProbe): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AProbe.Reports > 0;
    end;
end;

{ TAtlasWelcomeAccountNameTests }

procedure TAtlasWelcomeAccountNameTests.NameComesFromBackgroundAndIsReported;
var
  mProbe: TAccountProbe;
  mName: TAtlasWelcomeAccountName;
begin
  mProbe := TAccountProbe.Create;
  try
    mProbe.Value := '  Muster, Erika  ';
    mName := TAtlasWelcomeAccountName.Create(mProbe.Lookup(), mProbe.Changed());
    try
      Assert.AreEqual('', mName.Name, 'vor der Antwort leer');
      Assert.IsTrue(WaitUntil(Reported(mProbe)));
      Assert.AreEqual('Muster, Erika', mName.Name);
      Assert.IsTrue(mProbe.LookupThread <> MainThreadID, 'Abfrage im Hintergrund');
      Assert.IsTrue(mProbe.ReportThread = MainThreadID, 'Meldung im Hauptthread');
    finally
      mName.Free;
    end;
  finally
    mProbe.Value := '';
    mProbe.Free;
  end;
end;

procedure TAtlasWelcomeAccountNameTests.LookupRunsOnlyOnce;
var
  mProbe: TAccountProbe;
  mName: TAtlasWelcomeAccountName;
  mIndex: Integer;
begin
  mProbe := TAccountProbe.Create;
  try
    mProbe.Value := 'Erika Muster';
    mName := TAtlasWelcomeAccountName.Create(mProbe.Lookup(), mProbe.Changed());
    try
      for mIndex := 1 to 5 do
      begin
        Assert.AreEqual('', mName.Name, 'vor der Antwort leer');
      end;
      Assert.IsTrue(WaitUntil(Reported(mProbe)));
      for mIndex := 1 to 5 do
      begin
        Assert.AreEqual('Erika Muster', mName.Name);
      end;
      // Etwas Zeit für eine zweite Abfrage, die es nicht geben darf.
      WaitUntil(
        function: Boolean
        begin
          Result := mProbe.Lookups > 1;
        end, 200);
      Assert.AreEqual(1, mProbe.Lookups);
      Assert.AreEqual(1, mProbe.Reports);
    finally
      mName.Free;
    end;
  finally
    mProbe.Value := '';
    mProbe.Free;
  end;
end;

procedure TAtlasWelcomeAccountNameTests.EmptyNameIsNotReported;
var
  mProbe: TAccountProbe;
  mName: TAtlasWelcomeAccountName;
begin
  mProbe := TAccountProbe.Create;
  try
    mProbe.Value := '   ';
    mName := TAtlasWelcomeAccountName.Create(mProbe.Lookup(), mProbe.Changed());
    try
      Assert.AreEqual('', mName.Name);
      Assert.IsTrue(WaitUntil(Looked(mProbe)));
      // Abschluss abarbeiten lassen: Er darf nichts melden.
      WaitUntil(Reported(mProbe), 200);
      Assert.AreEqual(0, mProbe.Reports);
      Assert.AreEqual('', mName.Name);
      Assert.AreEqual(1, mProbe.Lookups, 'auch ein leerer Name wird nicht erneut erfragt');
    finally
      mName.Free;
    end;
  finally
    mProbe.Value := '';
    mProbe.Free;
  end;
end;

procedure TAtlasWelcomeAccountNameTests.NothingReportedAfterFree;
var
  mProbe: TAccountProbe;
  mName: TAtlasWelcomeAccountName;
begin
  mProbe := TAccountProbe.Create;
  try
    mProbe.Value := 'Erika Muster';
    mProbe.Gate := TEvent.Create(nil, True, False, '');
    mName := TAtlasWelcomeAccountName.Create(mProbe.Lookup(), mProbe.Changed());
    try
      Assert.AreEqual('', mName.Name);
      // Abfrage hängt (Domänencontroller nicht erreichbar); sie endet erst während der Freigabe.
      TThread.CreateAnonymousThread(
        procedure
        begin
          Sleep(100);
          mProbe.Gate.SetEvent;
        end).Start;
    finally
      mName.Free;
    end;
    Assert.AreEqual(1, mProbe.Lookups, 'Freigabe wartet die Abfrage ab');
    WaitUntil(Reported(mProbe), 200);
    Assert.AreEqual(0, mProbe.Reports);
  finally
    mProbe.Gate.Free;
    mProbe.Value := '';
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeAccountNameTests);

end.
