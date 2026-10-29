unit Cm.E2404;

// E2404 Cannot mix READ/WRITE property accessors with ADD/REMOVE accessors
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2404.
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
    property Ereignis: TNotifyEvent read FEreignis add Hinzu; // <- E2029
  end;

implementation

procedure TKlasse.Hinzu(AEreignis: TNotifyEvent);
begin
end;

end.
