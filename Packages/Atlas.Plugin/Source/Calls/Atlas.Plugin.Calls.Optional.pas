unit Atlas.Plugin.Calls.Optional;

// Rückrufe, die gesetzt sein können oder nicht: Ereignisse von Fenstern und Leisten (TProc) und das Meldungsziel
// eines Dienstes (TProc<string>), das ein Modul beim Start setzt und beim Stoppen wieder leert. Nicht gesetzt
// heißt: nichts tun. Base und Module rufen solche Rückrufe nur hierüber auf, statt die Prüfung je Unit zu
// wiederholen.

interface

uses
  System.SysUtils,
  Atlas.Plugin.Calls.Contract;

type
  TAtlasCalls = class
  public
    /// <summary>Ruft AProc auf, wenn es gesetzt ist.</summary>
    class procedure Call(const AProc: TProc); static;
    /// <summary>Gibt AText an ASink, wenn es gesetzt ist (Meldungsziel eines Dienstes).</summary>
    class procedure Send(const ASink: TProc<string>; const AText: string); static;
    /// <summary>Neue Quelle eines Bereichs zeigen: AUpdate (Inhalt neu), danach ASource.Shown, wenn ASource gesetzt
    /// ist.</summary>
    class procedure ShowSource(const ASource: IAtlasShownSource; const AUpdate: TProc); static;
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

class procedure TAtlasCalls.ShowSource(const ASource: IAtlasShownSource; const AUpdate: TProc);
begin
  AUpdate();
  if ASource <> nil then
  begin
    ASource.Shown;
  end;
end;

end.
