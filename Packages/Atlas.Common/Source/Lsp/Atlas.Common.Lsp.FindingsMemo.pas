unit Atlas.Common.Lsp.FindingsMemo;

// Treffer der Prüfregeln je Datei und Text, damit textDocument/codeAction die Regeln nicht noch einmal rechnet
// (2.0-stable: Die Atlas-Spalte fragt bei jeder Cursorbewegung nach der Glühbirne; jede Anfrage rechnete alle
// Regeln der Datei neu, stand dabei hinter dem Prüflauf an und lief in den Wächter des Servers).
// - Put: Die Diagnose legt nach jedem vollständigen Lauf die Treffer ab (vor der Baseline, wie RuleFindings),
//   die Code-Aktion nach einem eigenen Lauf ebenso. Ein abgebrochener Lauf legt nichts ab.
// - TryGet: nur bei genau demselben Text. Ändern sich Einstellungen oder Index, prüft die Diagnose die offenen
//   Dokumente ohnehin neu (RefreshLater) und ersetzt den Eintrag; bis dahin zeigen Glühbirne und Diagnose
//   denselben Stand.
// - Obtain: Je Datei und Text rechnet nur ein Lauf (#1761). Diagnose und Glühbirne warten auf einen laufenden
//   Lauf am selben Text, statt die Regeln daneben noch einmal zu rechnen; bei großen Units liefen sonst je
//   Cursorbewegung weitere volle Läufe parallel (Speicher, CPU, Zeitlimit).
//   Wartende schlafen auf der Sperre (TMonitor.Wait); das Ende eines Laufs weckt
//   sie sofort (PulseAll), den Abbruch prüfen sie im Takt WaitSliceMs.
// - Höchstens MaxEntries Dateien; der am längsten nicht benutzte Eintrag fällt heraus.
// - Threadsicher; Treffer gehen als Kopie hinein und heraus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Rechnet die Treffer der Prüfregeln einer Datei.</summary>
  TRuleFindingsRun = reference to function: TArray<TRuleFinding>;

  /// <summary>Zuletzt gerechnete Treffer der Prüfregeln je Datei und Text.</summary>
  IRuleFindingsMemo = interface
    ['{4C7E9A21-6B3D-4F85-A0C2-9E1D7B53F468}']
    /// <summary>Treffer für AFileName mit genau dem Text AText ablegen.</summary>
    procedure Put(const AFileName, AText: string; const AFindings: TArray<TRuleFinding>);
    /// <summary>Abgelegte Treffer, wenn der Eintrag zu AFileName genau zu AText gehört.</summary>
    function TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
    /// <summary>Treffer für AFileName mit dem Text AText: abgelegte, die eines laufenden Laufs am selben Text
    /// (wartet darauf) oder mit ARun selbst gerechnete (legt sie ab). ACancelled (nil = nie) beendet das Warten
    /// mit ERuleCheckCancelled.</summary>
    function Obtain(const AFileName, AText: string; const ARun: TRuleFindingsRun;
      const ACancelled: TRuleCancelled): TArray<TRuleFinding>;
  end;

  TRuleFindingsMemo = class(TInterfacedObject, IRuleFindingsMemo)
  public const
    cMaxEntries = 32;
    /// <summary>Takt, in dem Obtain beim Warten auf einen laufenden Lauf den Abbruch prüft; das Ende des Laufs weckt
    /// sofort.</summary>
    cWaitSliceMs = 100;
  private type
    TEntry = record
      Text: string;
      Findings: TArray<TRuleFinding>;
      Used: Int64;
    end;
  private
    FLock: TObject;
    FEntries: TDictionary<string, TEntry>;
    FClock: Int64;
    /// <summary>Laufende Läufe: Schlüssel der Datei -> Text. Unter FLock; Release weckt Wartende mit PulseAll.
    /// </summary>
    FRunning: TDictionary<string, string>;
    /// <summary>Den am längsten nicht benutzten Eintrag entfernen; nur unter FLock.</summary>
    procedure DropOldest;
    /// <summary>Abgelegte Treffer zu AKey und AText; nur unter FLock.</summary>
    function Lookup(const AKey, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
    /// <summary>True: Der Aufrufer rechnet AKey/AText jetzt selbst. False mit ACached: abgelegte Treffer. False
    /// ohne: Ein anderer Lauf rechnet denselben Text.</summary>
    function Claim(const AKey, AText: string; out AFindings: TArray<TRuleFinding>; out ACached: Boolean): Boolean;
    procedure Release(const AKey, AText: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; const AFindings: TArray<TRuleFinding>);
    function TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
    function Obtain(const AFileName, AText: string; const ARun: TRuleFindingsRun;
      const ACancelled: TRuleCancelled): TArray<TRuleFinding>;
  end;

implementation

constructor TRuleFindingsMemo.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FRunning := TDictionary<string, string>.Create;
end;

destructor TRuleFindingsMemo.Destroy;
begin
  FRunning.Free;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

procedure TRuleFindingsMemo.DropOldest;
var
  mPair: TPair<string, TEntry>;
  mOldest: string;
  mUsed: Int64;
begin
  mOldest := '';
  mUsed := High(Int64);
  for mPair in FEntries do
  begin
    // Bei Gleichstand der kleinere Schlüssel: Die Reihenfolge des Wörterbuchs ist nicht festgelegt.
    if (mPair.Value.Used < mUsed) or ((mPair.Value.Used = mUsed) and (mPair.Key < mOldest)) then
    begin
      mOldest := mPair.Key;
      mUsed := mPair.Value.Used;
    end;
  end;
  FEntries.Remove(mOldest);
end;

procedure TRuleFindingsMemo.Put(const AFileName, AText: string; const AFindings: TArray<TRuleFinding>);
var
  mKey: string;
  mEntry: TEntry;
begin
  mKey := AnsiUpperCase(AFileName);
  mEntry.Text := AText;
  mEntry.Findings := Copy(AFindings);
  System.TMonitor.Enter(FLock);
  try
    Inc(FClock);
    mEntry.Used := FClock;
    if not FEntries.ContainsKey(mKey) and (FEntries.Count >= cMaxEntries) then
    begin
      DropOldest;
    end;
    FEntries.AddOrSetValue(mKey, mEntry);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TRuleFindingsMemo.Lookup(const AKey, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  mEntry: TEntry;
begin
  AFindings := nil;
  Result := FEntries.TryGetValue(AKey, mEntry) and (mEntry.Text = AText);
  if Result then
  begin
    Inc(FClock);
    mEntry.Used := FClock;
    FEntries[AKey] := mEntry;
    AFindings := Copy(mEntry.Findings);
  end;
end;

function TRuleFindingsMemo.TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := Lookup(AnsiUpperCase(AFileName), AText, AFindings);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TRuleFindingsMemo.Claim(const AKey, AText: string; out AFindings: TArray<TRuleFinding>;
  out ACached: Boolean): Boolean;
var
  mText: string;
begin
  System.TMonitor.Enter(FLock);
  try
    ACached := Lookup(AKey, AText, AFindings);
    Result := not ACached and not (FRunning.TryGetValue(AKey, mText) and (mText = AText));
    if Result then
    begin
      FRunning.AddOrSetValue(AKey, AText);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TRuleFindingsMemo.Release(const AKey, AText: string);
var
  mText: string;
begin
  System.TMonitor.Enter(FLock);
  try
    // Ein neuerer Lauf mit anderem Text bleibt vermerkt.
    if FRunning.TryGetValue(AKey, mText) and (mText = AText) then
    begin
      FRunning.Remove(AKey);
    end;
    // Wartende auf denselben Text finden jetzt die Treffer (oder rechnen selbst, wenn der Lauf scheiterte).
    System.TMonitor.PulseAll(FLock);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TRuleFindingsMemo.Obtain(const AFileName, AText: string; const ARun: TRuleFindingsRun;
  const ACancelled: TRuleCancelled): TArray<TRuleFinding>;
var
  mKey: string;
  mCached, mClaimed: Boolean;
begin
  mKey := AnsiUpperCase(AFileName);
  repeat
    System.TMonitor.Enter(FLock);
    try
      mClaimed := Claim(mKey, AText, Result, mCached);
      if not mClaimed and not mCached then
      begin
        // Gibt die Sperre frei, bis Release weckt oder der Takt für die Abbruchprüfung abläuft. Claim und Wait
        // stehen unter derselben Sperre: Ein Release dazwischen geht nicht verloren.
        System.TMonitor.Wait(FLock, cWaitSliceMs);
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if mCached then
    begin
      Exit;
    end;
    // Abbruch außerhalb der Sperre fragen: ACancelled darf andere Sperren nehmen (Dokumentspeicher).
    if not mClaimed and Assigned(ACancelled) and ACancelled() then
    begin
      raise ERuleCheckCancelled.Create(AFileName);
    end;
  until mClaimed;
  try
    Result := ARun();
    Put(AFileName, AText, Result);
  finally
    Release(mKey, AText);
  end;
end;

end.
