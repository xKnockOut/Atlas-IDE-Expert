unit Cm.E2404;

// E2404 Cannot mix READ/WRITE property accessors with ADD/REMOVE accessors
// Erwartet: E2404
// Vermutung; .NET-Syntax.

interface

uses
  System.Classes;

type
  TKlasse = class
  private
    FEreignis: TNotifyEvent;
    procedure Hinzu(AEreignis: TNotifyEvent);
  public
    property Ereignis: TNotifyEvent read FEreignis add Hinzu; // <- E2404
  end;

implementation

procedure TKlasse.Hinzu(AEreignis: TNotifyEvent);
begin
end;

end.
