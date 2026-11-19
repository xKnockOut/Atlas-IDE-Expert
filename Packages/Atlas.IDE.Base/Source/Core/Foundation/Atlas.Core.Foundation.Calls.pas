unit Atlas.Core.Foundation.Calls;

// Rückrufe, die gesetzt sein können oder nicht: Ereignisse von Fenstern und Leisten (TProc) und das Meldungsziel
// eines Dienstes (TProc<string>), das ein Modul beim Start setzt und beim Stoppen wieder leert. Nicht gesetzt
// heißt: nichts tun. Base und Module rufen solche Rückrufe nur hierüber auf, statt die Prüfung je Unit zu
// wiederholen.

interface

uses
  System.SysUtils;

type
  TAtlasCalls = class
  public
    /// <summary>Ruft AProc auf, wenn es gesetzt ist.</summary>
    class procedure Call(const AProc: TProc); static;
    /// <summary>Gibt AText an ASink, wenn es gesetzt ist (Meldungsziel eines Dienstes).</summary>
    class procedure Send(const ASink: TProc<string>; const AText: string); static;
  end;

implementation

{ TAtlasCalls }

class procedure TAtlasCalls.Call(const AProc: TProc);
begin
  if Assigned(AProc) then
  begin
    AProc();
  end;
end;

class procedure TAtlasCalls.Send(const ASink: TProc<string>; const AText: string);
begin
  if Assigned(ASink) then
  begin
    ASink(AText);
  end;
end;

end.
