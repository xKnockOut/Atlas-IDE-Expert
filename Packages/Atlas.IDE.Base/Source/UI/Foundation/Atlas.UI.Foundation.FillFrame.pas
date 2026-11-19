unit Atlas.UI.Foundation.FillFrame;

// Frame, das seine Listen, Bäume und Listenansichten erst mit Fenster füllt: Deren Einträge brauchen ein Fenster
// (Items, HandleNeeded). Ein neuer Stand füllt sofort, wenn das Fenster besteht, sonst beim Anlegen des Fensters
// (CreateWnd); so geht kein Stand verloren, solange ein Reiter oder ein andockbares Fenster noch nicht gezeigt wurde.

interface

uses
  Vcl.Forms;

type
  TAtlasFillFrame = class(TFrame)
  private
    FFilled: Boolean;
  protected
    procedure CreateWnd; override;
    /// <summary>Steuerelemente aus dem aktuellen Stand füllen; läuft nur mit Fenster.</summary>
    procedure FillControls; virtual; abstract;
    /// <summary>Jetzt füllen (braucht das Fenster).</summary>
    procedure Fill;
    /// <summary>Neuer Stand: mit Fenster sofort füllen, sonst beim Anlegen des Fensters.</summary>
    procedure Refill;
    /// <summary>Erst beim nächsten Anlegen des Fensters füllen.</summary>
    procedure FillLater;
  end;

implementation

{ TAtlasFillFrame }

procedure TAtlasFillFrame.CreateWnd;
begin
  inherited CreateWnd;
  if not FFilled then
  begin
    Fill;
  end;
end;

procedure TAtlasFillFrame.Fill;
begin
  FFilled := True;
  FillControls;
end;

procedure TAtlasFillFrame.Refill;
begin
  FFilled := False;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasFillFrame.FillLater;
begin
  FFilled := False;
end;

end.
