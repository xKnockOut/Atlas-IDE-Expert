unit Atlas.Common.Lsp.FindingsMemo;

// Treffer der Prüfregeln je Datei und Text, damit textDocument/codeAction die Regeln nicht noch einmal rechnet
// (2.0-stable: Die Atlas-Spalte fragt bei jeder Cursorbewegung nach der Glühbirne; jede Anfrage rechnete alle
// Regeln der Datei neu, stand dabei hinter dem Prüflauf an und lief in den Wächter des Servers).
// - Put: Die Diagnose legt nach jedem vollständigen Lauf die Treffer ab (vor der Baseline, wie RuleFindings),
//   die Code-Aktion nach einem eigenen Lauf ebenso. Ein abgebrochener Lauf legt nichts ab.
// - TryGet: nur bei genau demselben Text. Ändern sich Einstellungen oder Index, prüft die Diagnose die offenen
//   Dokumente ohnehin neu (RefreshLater) und ersetzt den Eintrag; bis dahin zeigen Glühbirne und Diagnose
//   denselben Stand.
// - Höchstens MaxEntries Dateien; der am längsten nicht benutzte Eintrag fällt heraus.
// - Threadsicher; Treffer gehen als Kopie hinein und heraus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Zuletzt gerechnete Treffer der Prüfregeln je Datei und Text.</summary>
  IRuleFindingsMemo = interface
    ['{4C7E9A21-6B3D-4F85-A0C2-9E1D7B53F468}']
    /// <summary>Treffer für AFileName mit genau dem Text AText ablegen.</summary>
    procedure Put(const AFileName, AText: string; const AFindings: TArray<TRuleFinding>);
    /// <summary>Abgelegte Treffer, wenn der Eintrag zu AFileName genau zu AText gehört.</summary>
    function TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
  end;

  TRuleFindingsMemo = class(TInterfacedObject, IRuleFindingsMemo)
  public const
    MaxEntries = 32;
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
    /// <summary>Den am längsten nicht benutzten Eintrag entfernen; nur unter FLock.</summary>
    procedure DropOldest;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; const AFindings: TArray<TRuleFinding>);
    function TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
  end;

implementation

constructor TRuleFindingsMemo.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TRuleFindingsMemo.Destroy;
begin
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
    if not FEntries.ContainsKey(mKey) and (FEntries.Count >= MaxEntries) then
    begin
      DropOldest;
    end;
    FEntries.AddOrSetValue(mKey, mEntry);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TRuleFindingsMemo.TryGet(const AFileName, AText: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  mKey: string;
  mEntry: TEntry;
begin
  AFindings := nil;
  mKey := AnsiUpperCase(AFileName);
  System.TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(mKey, mEntry) and (mEntry.Text = AText);
    if Result then
    begin
      Inc(FClock);
      mEntry.Used := FClock;
      FEntries[mKey] := mEntry;
      AFindings := Copy(mEntry.Findings);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
