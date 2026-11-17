unit Atlas.IDE.Tests.ExplorerTicker;

// Zeitgeber des Fensters „Atlas-Tests“ (#1776): folgt dem Läufer (Lauf beginnt
// bzw. endet, neuer Bericht), solange das Fenster zu sehen ist, und liest das
// Fenster beim nächsten Takt neu, wenn es dazu aufgefordert wurde (Lauf
// gemeldet, Unit gespeichert). Ohne Fenster hält er an. Er lebt nur so lange
// wie dieses Objekt; danach erreicht kein Takt mehr den Besitzer. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestExplorerTicker = class
  private const
    cTickMs = 500;
  private
    FTimer: TTimer;
    FTests: TAtlasIdeTests;
    FDirty: Boolean;
    FBusy: Boolean;
    FVersion: Integer;
    FOnReload: TProc;
    FOnBusy: TProc<Boolean>;
    procedure Tick(Sender: TObject);
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger. AOnReload liest das Fenster neu, AOnBusy zeigt einen
    /// neuen Stand des Läufers (läuft bzw. neuer Bericht).</summary>
    constructor Create(ATests: TAtlasIdeTests; const AOnReload: TProc; const AOnBusy: TProc<Boolean>);
    destructor Destroy; override;
    /// <summary>Beim nächsten Takt neu lesen.</summary>
    procedure MarkDirty;
    /// <summary>Das Fenster wurde gerade neu gelesen: nicht mehr veraltet, Stand des Läufers gesehen. Liefert, ob
    /// der Läufer gerade läuft.</summary>
    function Synced: Boolean;
    procedure Start;
    procedure Stop;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Tests.ExplorerWindow;

{ TAtlasIdeTestExplorerTicker }

constructor TAtlasIdeTestExplorerTicker.Create(ATests: TAtlasIdeTests; const AOnReload: TProc;
  const AOnBusy: TProc<Boolean>);
begin
  inherited Create;
  FTests := ATests;
  FOnReload := AOnReload;
  FOnBusy := AOnBusy;
  FDirty := True;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeTestExplorerTicker.Destroy;
begin
  FreeAndNil(FTimer);
  FOnReload := nil;
  FOnBusy := nil;
  inherited Destroy;
end;

procedure TAtlasIdeTestExplorerTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      if TAtlasIdeTestsExplorerWindow.ExistingFrame = nil then
      begin
        FTimer.Enabled := False;
        Exit;
      end;
      if not TAtlasIdeTestsExplorerWindow.Visible then
      begin
        Exit;
      end;
      if FDirty then
      begin
        FOnReload();
      end
      else if (FBusy <> FTests.Busy) or (FVersion <> FTests.Version) then
      begin
        FBusy := FTests.Busy;
        FVersion := FTests.Version;
        FOnBusy(FBusy);
      end;
    end);
end;

procedure TAtlasIdeTestExplorerTicker.MarkDirty;
begin
  FDirty := True;
end;

function TAtlasIdeTestExplorerTicker.Synced: Boolean;
begin
  FDirty := False;
  FBusy := FTests.Busy;
  FVersion := FTests.Version;
  Result := FBusy;
end;

procedure TAtlasIdeTestExplorerTicker.Start;
begin
  FTimer.Enabled := True;
end;

procedure TAtlasIdeTestExplorerTicker.Stop;
begin
  FTimer.Enabled := False;
end;

end.
