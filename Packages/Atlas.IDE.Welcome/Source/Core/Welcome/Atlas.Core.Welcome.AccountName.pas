unit Atlas.Core.Welcome.AccountName;

// Anzeigename des Windows-Kontos für den Gruß im Kopf der Willkommensseite (2.0-stable, abgebrochene Anfragen):
// GetUserNameEx(NameDisplay) fragt bei einem Domänenkonto den Domänencontroller. Im Firmennetz dauert das einige
// 10 ms, ohne Verbindung zum Controller (VPN, Netz weg) Sekunden. Der Kopf füllt sich bei jeder Änderung im
// Statusfeld neu, also mindestens alle 5 s, und fragte jedes Mal im Hauptthread: im Diagnose-Fenster 20 bis 90 ms
// alle 5 s und einmal 8,3 s.
// - Der Name ändert sich während der Sitzung nicht: Er wird beim ersten Bedarf einmal im Hintergrund
//   nachgeschlagen und dann behalten.
// - Bis die Antwort da ist, und wenn sie scheitert, ist Name leer; der Gruß nimmt dann den Kontonamen.
// - Kommt ein Name, meldet AChanged im Hauptthread, damit der Kopf ihn zeigt.
// - Freigeben wartet eine laufende Abfrage ab (TAtlasBackgroundRequest); danach meldet nichts mehr.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.BackgroundRequest;

type
  TAtlasWelcomeAccountName = class
  private
    FLookup: TFunc<string>;
    FChanged: TProc;
    FRequest: TAtlasBackgroundRequest;
    FName: string;
    FAsked: Boolean;
    procedure Ask;
  public
    /// <summary>ALookup: liefert den Anzeigenamen ('' = keiner), läuft im Hintergrund; AChanged: ein Name ist
    /// gekommen (Hauptthread).</summary>
    constructor Create(const ALookup: TFunc<string>; const AChanged: TProc);
    destructor Destroy; override;
    /// <summary>Anzeigename; '' solange er nicht bekannt ist. Der erste Aufruf startet die Abfrage.</summary>
    function Name: string;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard;

constructor TAtlasWelcomeAccountName.Create(const ALookup: TFunc<string>; const AChanged: TProc);
begin
  inherited Create;
  FLookup := ALookup;
  FChanged := AChanged;
  FRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.WelcomePage);
end;

destructor TAtlasWelcomeAccountName.Destroy;
begin
  // Zuerst: wartet die Abfrage ab, die noch FLookup aufruft, und verwirft ihren Abschluss.
  FreeAndNil(FRequest);
  inherited;
end;

procedure TAtlasWelcomeAccountName.Ask;
var
  mFound: string;
  mLookup: TFunc<string>;
begin
  FAsked := True;
  mFound := '';
  mLookup := FLookup;
  FRequest.Start(
    procedure
    begin
      // Im Hintergrund; mFound liest erst der Abschluss im Hauptthread.
      mFound := Trim(mLookup());
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if not AOk or (mFound = '') then
      begin
        Exit;
      end;
      FName := mFound;
      if Assigned(FChanged) then
      begin
        FChanged();
      end;
    end);
end;

function TAtlasWelcomeAccountName.Name: string;
begin
  if not FAsked and Assigned(FLookup) then
  begin
    Ask;
  end;
  Result := FName;
end;

end.
